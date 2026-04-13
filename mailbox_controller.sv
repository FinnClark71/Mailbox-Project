
`timescale 1ns/1ps
// Mailbox controller

// Glues together scratchpad, freelist, tx_queue, rx_queue, and refcount_mem
// into one MMIO addressable block that the BRISKI core can communicate with.

// The outsied world sees 2 clean interfaces:
//   - TX side: the network drains tx_queue and signals back tx_done when finished
//   - RX side: the network pushes rx descriptors in, and can also hit the scratchpad

// The FIFOs (freelist/rx_queue/tx_queue) can't handle an enq and deq
// on the same cycle without breaking so the controller:
//   - freelist: never push and pop together
//   - tx_queue: controller only enquues; the network dequeues externally
//   - rx_queue: network enqueues externally, controller only dequeues

// Register map (byte offsets from the MMIO base):
//   0x00 STATUS      [R]  bit0 = tx_can_send  (init done, slot available, txq not full)
//                         bit1 = rx_has_msg   (rxq not empty)
//                         bit2 = init_done
//                         bit3 = error_flag
//   0x04 TX_DEST     [RW] destination core id
//   0x08 TX_LEN      [RW] length/metadata for the message
//   0x0C TX_SEND     [W]  write 1 to start a send (grabs a free slot + enqueues tx descriptor)
//                    [R]  slot that was just alocated
//   0x10 RX_POP      [W]  write 1 to pop the next rx descriptor
//                    [R]  the descriptor that was just popped, packed as {len, slot}
//   0x14 REL_SLOT    [W]  write a slot id here to release it (decrements refcount)

//   0x18 SP_WADDR    [RW] scratchpad write address
//   0x1C SP_WDATA    [RW] scratchpad write data
//   0x20 SP_WE       [W]  write 1 to actually do the scratchpad write
//   0x24 SP_RADDR    [RW] scratchpad read address
//   0x28 SP_RE       [W]  write 1 to kick off a scratchpad read
//   0x2C SP_RDATA    [R]  data from the last scratchpad read
//   0x30 SP_RVALID   [R]  bit0 pulses high when the scratchpad read result is ready

module mailbox_controller #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 8,

    parameter int DEST_W = 4,
    parameter int LEN_W  = 8,
    parameter int SLOT_W = 8,

    parameter int NUM_SLOTS      = (1 << SLOT_W), // 256
    parameter int FREELIST_DEPTH = (1 << SLOT_W), // 256

    parameter int TXQ_DEPTH = 16,
    parameter int RXQ_DEPTH = 16,

    parameter int COUNT_W = 4
)(
    input  logic                   clk,
    input  logic                   rst,

    // BRISKI-friendly simple bus
    input  logic                   bus_valid,
    input  logic                   bus_we,
    input  logic [7:0]             bus_addr,
    input  logic [DATA_WIDTH-1:0]  bus_wdata,
    output logic [DATA_WIDTH-1:0]  bus_rdata,
    output logic                   bus_ready,

    output logic                   irq_rx,

    // Network-side: drain tx_queue
    input  logic                   txq_deq,
    output logic [DEST_W+LEN_W+SLOT_W-1:0] txq_deq_data,
    output logic                   txq_deq_valid,
    output logic                   txq_deq_ready,

    // Network-side: enqueue rx descriptor
    input  logic                   rx_in_valid,
    input  logic [LEN_W+SLOT_W-1:0] rx_in_data,   // {len,slot}
    output logic                   rx_in_ready,

    // Network-side: mark transmit complete for slot (dec refcount)
    input  logic                   tx_done_valid,
    input  logic [SLOT_W-1:0]      tx_done_slot,

    // Network scratchpad access (simple priority over core)
    input  logic                   net_sp_we,
    input  logic [ADDR_WIDTH-1:0]  net_sp_waddr,
    input  logic [DATA_WIDTH-1:0]  net_sp_wdata,

    input  logic                   net_sp_re,
    input  logic [ADDR_WIDTH-1:0]  net_sp_raddr,
    output logic [DATA_WIDTH-1:0]  net_sp_rdata,
    output logic                   net_sp_rvalid
);

    localparam int TX_W = DEST_W + LEN_W + SLOT_W;
    localparam int RX_W = LEN_W + SLOT_W;

   
    // Submodule wires ----------------------------

    // Scratchpad (one write port, one read port)
    logic sp_we, sp_re;
    logic [ADDR_WIDTH-1:0] sp_waddr, sp_raddr;
    logic [DATA_WIDTH-1:0] sp_wdata;
    logic [DATA_WIDTH-1:0] sp_rdata;
    logic sp_rvalid;

    scratchpad #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_scratchpad (
        .clk   (clk),
        .rst   (rst),
        .we    (sp_we),
        .waddr (sp_waddr),
        .wdata (sp_wdata),
        .re    (sp_re),
        .raddr (sp_raddr),
        .rdata (sp_rdata),
        .rvalid(sp_rvalid)
    );

    assign net_sp_rdata  = sp_rdata;
    assign net_sp_rvalid = sp_rvalid;

    // Free list
    logic fl_pop, fl_push;
    logic [SLOT_W-1:0] fl_pop_data, fl_push_data;
    logic fl_pop_valid, fl_full, fl_empty;

    freelist #(
        .WIDTH(SLOT_W),
        .DEPTH(FREELIST_DEPTH)
    ) u_freelist (
        .clk       (clk),
        .rst       (rst),
        .pop       (fl_pop),
        .pop_data  (fl_pop_data),
        .pop_valid (fl_pop_valid),
        .push      (fl_push),
        .push_data (fl_push_data),
        .full      (fl_full),
        .empty     (fl_empty)
    );

    // TX queue
    logic txq_enq;
    logic [TX_W-1:0] txq_enq_data;
    logic txq_enq_ready, txq_full, txq_empty;

    tx_queue #(
        .DEST_W(DEST_W),
        .SLOT_W(SLOT_W),
        .LEN_W (LEN_W),
        .DEPTH (TXQ_DEPTH)
    ) u_txq (
        .clk       (clk),
        .rst       (rst),
        .enq       (txq_enq),
        .enq_data  (txq_enq_data),
        .enq_ready (txq_enq_ready),
        .deq       (txq_deq),
        .deq_data  (txq_deq_data),
        .deq_valid (txq_deq_valid),
        .deq_ready (txq_deq_ready),
        .full      (txq_full),
        .empty     (txq_empty)
    );

    // RX queue
    logic rxq_enq;
    logic [RX_W-1:0] rxq_enq_data;
    logic rxq_enq_ready, rxq_deq;
    logic [RX_W-1:0] rxq_deq_data;
    logic rxq_deq_valid, rxq_deq_ready;
    logic rxq_full, rxq_empty;

    rx_queue #(
        .SLOT_W(SLOT_W),
        .LEN_W (LEN_W),
        .DEPTH (RXQ_DEPTH)
    ) u_rxq (
        .clk       (clk),
        .rst       (rst),
        .enq       (rxq_enq),
        .enq_data  (rxq_enq_data),
        .enq_ready (rxq_enq_ready),
        .deq       (rxq_deq),
        .deq_data  (rxq_deq_data),
        .deq_valid (rxq_deq_valid),
        .deq_ready (rxq_deq_ready),
        .full      (rxq_full),
        .empty     (rxq_empty)
    );

    // Refcount
    logic rc_inc, rc_dec;
    logic [SLOT_W-1:0] rc_inc_slot, rc_dec_slot;
    logic rc_free_valid;
    logic [SLOT_W-1:0] rc_free_slot;

    refcount_mem #(
        .SLOT_W   (SLOT_W),
        .COUNT_W  (COUNT_W),
        .NUM_SLOTS(NUM_SLOTS)
    ) u_refcount (
        .clk       (clk),
        .rst       (rst),
        .inc       (rc_inc),
        .inc_slot  (rc_inc_slot),
        .dec       (rc_dec),
        .dec_slot  (rc_dec_slot),
        .free_valid(rc_free_valid),
        .free_slot (rc_free_slot)
    );

    
    //  Bus side registers ----------------------------------------------------
 
    logic [DEST_W-1:0] reg_tx_dest;
    logic [LEN_W-1:0]  reg_tx_len;

    logic [ADDR_WIDTH-1:0] reg_sp_waddr, reg_sp_raddr;
    logic [DATA_WIDTH-1:0] reg_sp_wdata;

    logic [DATA_WIDTH-1:0] reg_last_sp_rdata;
    logic                  reg_last_sp_rvalid;

    logic [SLOT_W-1:0] reg_last_alloc_slot;  // slot grabbed during last TX_SEND
    logic [RX_W-1:0]   reg_last_rx_desc;     // descriptor popped during last RX_POP

    logic error_flag;

    assign bus_ready = 1'b1;  // always ready, no wait states on this bus
    assign irq_rx    = !rxq_empty;  // interrupt core any time there's a message waiting

    
    // ---------- Init FSM ----------
    // On reset, walk through all slot IDs and push them into the freelist.
    // Once full, init_done goes high and normmal operation can start.
   
    logic init_done;
    logic [SLOT_W-1:0] init_slot;

   
    // ---------- Command FSM ----------
    // Sequences multi-cycle operations: TX send (pop freelist → enq txq)
    // and RX pop (deq rxq). Everything else is single-cycle.
    
    typedef enum logic [2:0] {
        S_IDLE,
        S_SEND_POP,    // waiting one cycle for freelist pop to register
        S_SEND_WAIT,   // waiting for fl_pop_valid
        S_SEND_ENQ,    // enqueue the tx descriptor with the allocated slot
        S_RX_DEQ,      // assert rxq_deq for one cycle
        S_RX_WAIT      // wait for rxq_deq_valid to come back
    } state_t;

    state_t state;

    // one cycle command pulses decoded from bus writes
    logic cmd_send_pulse;
    logic cmd_rx_pop_pulse;
    logic cmd_sp_we_pulse;
    logic cmd_sp_re_pulse;
    logic cmd_release_pulse;
    logic [SLOT_W-1:0] cmd_release_slot;

    // if tx_done and a core release arrive in the same cycle, only do one dec at a time, so buffer the second one for next cycle
    logic pending_dec;
    logic [SLOT_W-1:0] pending_dec_slot;

    
    // ---------- Bus write decode ----------
    
    always_ff @(posedge clk) begin
        if (rst) begin
            reg_tx_dest <= '0;
            reg_tx_len  <= '0;

            reg_sp_waddr <= '0;
            reg_sp_wdata <= '0;
            reg_sp_raddr <= '0;

            reg_last_sp_rdata  <= '0;
            reg_last_sp_rvalid <= 1'b0;

            //reg_last_alloc_slot <= '0;
            //reg_last_rx_desc    <= '0;

            cmd_send_pulse    <= 1'b0;
            cmd_rx_pop_pulse  <= 1'b0;
            cmd_sp_we_pulse   <= 1'b0;
            cmd_sp_re_pulse   <= 1'b0;
            cmd_release_pulse <= 1'b0;
            cmd_release_slot  <= '0;

            error_flag <= 1'b0;
        end else begin
            // all pulses default to off every cycle
            cmd_send_pulse    <= 1'b0;
            cmd_rx_pop_pulse  <= 1'b0;
            cmd_sp_we_pulse   <= 1'b0;
            cmd_sp_re_pulse   <= 1'b0;
            cmd_release_pulse <= 1'b0;

            // latch scratchpad read result when it comes back
            reg_last_sp_rvalid <= sp_rvalid;
            if (sp_rvalid) reg_last_sp_rdata <= sp_rdata;

            // freelist going full while refcount wants to free a slot = something went wrong
            if (rc_free_valid && fl_full) error_flag <= 1'b1;

            if (bus_valid && bus_we) begin
                unique case (bus_addr)
                    8'h04: reg_tx_dest <= bus_wdata[DEST_W-1:0];
                    8'h08: reg_tx_len  <= bus_wdata[LEN_W-1:0];

                    8'h0C: if (bus_wdata[0]) cmd_send_pulse <= 1'b1;

                    8'h10: if (bus_wdata[0]) cmd_rx_pop_pulse <= 1'b1;

                    8'h14: begin
                        cmd_release_pulse <= 1'b1;
                        cmd_release_slot  <= bus_wdata[SLOT_W-1:0];
                    end

                    8'h18: reg_sp_waddr <= bus_wdata[ADDR_WIDTH-1:0];
                    8'h1C: reg_sp_wdata <= bus_wdata;
                    8'h20: if (bus_wdata[0]) cmd_sp_we_pulse <= 1'b1;

                    8'h24: reg_sp_raddr <= bus_wdata[ADDR_WIDTH-1:0];
                    8'h28: if (bus_wdata[0]) cmd_sp_re_pulse <= 1'b1;

                    default: /*no-op*/;
                endcase
            end
        end
    end

    
    //  Bus read mux -------------------------------------------------------------

    always_comb begin
        logic tx_can_send;
        tx_can_send = init_done && (!fl_empty) && txq_enq_ready;

        bus_rdata = '0;
        if (bus_valid && !bus_we) begin
            unique case (bus_addr)
                8'h00: bus_rdata = {28'b0, error_flag, init_done, !rxq_empty, tx_can_send};
                8'h04: bus_rdata = {{(DATA_WIDTH-DEST_W){1'b0}}, reg_tx_dest};
                8'h08: bus_rdata = {{(DATA_WIDTH-LEN_W){1'b0}},  reg_tx_len};
                8'h0C: bus_rdata = {{(DATA_WIDTH-SLOT_W){1'b0}}, reg_last_alloc_slot};
                8'h10: bus_rdata = {{(DATA_WIDTH-RX_W){1'b0}},   reg_last_rx_desc};
                8'h2C: bus_rdata = reg_last_sp_rdata;
                8'h30: bus_rdata = {{(DATA_WIDTH-1){1'b0}}, reg_last_sp_rvalid};
                default: bus_rdata = '0;
            endcase
        end
    end


    // Main FSM + init + dec buffering -------------------------------
  
    always_ff @(posedge clk) begin
        if (rst) begin
            init_done <= 1'b0;
            init_slot <= '0;

            state <= S_IDLE;

            pending_dec      <= 1'b0;
            pending_dec_slot <= '0;
			
			reg_last_alloc_slot <= '0;
			reg_last_rx_desc    <= '0;
			
        end else begin
            // init: keep incrimenting init_slot and pushing until the freelist is full
            if (!init_done && !fl_full) begin
                init_slot <= init_slot + 1'b1;
            end
            if (!init_done && fl_full) begin
                init_done <= 1'b1;
            end

            // if both tx_done and a core release arrive at the same time,
            // we can only issue one dec this cycle, buffer the other for next cycle
            if (!pending_dec) begin
                if (tx_done_valid && cmd_release_pulse) begin
                    pending_dec      <= 1'b1;
                    pending_dec_slot <= cmd_release_slot;
                end
            end else begin
                // pending dec was issued combinationally this cycle, clear it
                pending_dec <= 1'b0;
            end

            // FSM - sequences the multi-cycle TX send and RX pop operations
            case (state)
                S_IDLE: begin
                    if (cmd_send_pulse) begin
                        if (init_done && !fl_empty && txq_enq_ready) begin
                            state <= S_SEND_POP;
                        end
                    end else if (cmd_rx_pop_pulse) begin
                        if (!rxq_empty) begin
                            state <= S_RX_DEQ;
                        end
                    end
                end

                S_SEND_POP: begin
                    state <= S_SEND_WAIT;  // give the freelist a cycle to respond
                end
                S_SEND_WAIT: begin
                    if (fl_pop_valid) begin
                        reg_last_alloc_slot <= fl_pop_data;  // save slot for enqueue step
                        state <= S_SEND_ENQ;
                    end
                end
                S_SEND_ENQ: begin
                    state <= S_IDLE;  // enqueue happens combinationally in this state
                end

                S_RX_DEQ: begin
                    state <= S_RX_WAIT;  // deq asserted this cycle, wait for valid
                end
                S_RX_WAIT: begin
                    if (rxq_deq_valid) begin
                        reg_last_rx_desc <= rxq_deq_data;  // latch for the core to read back
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

  
    // Combinational control ----------------------------------------------
    // Drives all the submodule inputs based on FSM state and incoming pulses.
    // Net has priority over core for scratchpad access.
   
    always_comb begin
        // defaults - nothing active unless explicitly driven below
        fl_pop       = 1'b0;
        fl_push      = 1'b0;
        fl_push_data = '0;

        txq_enq      = 1'b0;
        txq_enq_data = '0;

        rxq_enq      = 1'b0;
        rxq_enq_data = '0;
        rxq_deq      = 1'b0;

        rc_inc      = 1'b0;
        rc_inc_slot = '0;
        rc_dec      = 1'b0;
        rc_dec_slot = '0;

        // scratchpad arbitration (net has priority)
        sp_we    = 1'b0;
        sp_waddr = '0;
        sp_wdata = '0;

        sp_re    = 1'b0;
        sp_raddr = '0;

        // scratchpad: network wins if both net and core want access at the same time
        if (net_sp_we) begin
            sp_we    = 1'b1;
            sp_waddr = net_sp_waddr;
            sp_wdata = net_sp_wdata;
        end else if (cmd_sp_we_pulse) begin
            sp_we    = 1'b1;
            sp_waddr = reg_sp_waddr;
            sp_wdata = reg_sp_wdata;
        end

        if (net_sp_re) begin
            sp_re    = 1'b1;
            sp_raddr = net_sp_raddr;
        end else if (cmd_sp_re_pulse) begin
            sp_re    = 1'b1;
            sp_raddr = reg_sp_raddr;
        end

        // freelist push policy:
        // during init we push slot IDs sequentially until full;
        // after init we push slots back when refcount_mem says they're free
        if (!init_done) begin
            if (!fl_full) begin
                fl_push      = 1'b1;
                fl_push_data = init_slot;
            end
        end else begin
            // After init: push slots freed by refcount_mem
            if (rc_free_valid && !fl_full) begin
                fl_push      = 1'b1;
                fl_push_data = rc_free_slot;
            end
        end

        // rx_in: gate ready so we never enq and deq the rxq in the same cycle
        rx_in_ready = rxq_enq_ready && (state != S_RX_DEQ);

        if (rx_in_valid && rx_in_ready) begin
            rxq_enq      = 1'b1;
            rxq_enq_data = rx_in_data;

            // incoming slot is now owned by the receiver - start its refcount at 1
            rc_inc      = 1'b1;
            rc_inc_slot = rx_in_data[SLOT_W-1:0];
        end

        // FSM-driven ops
        if (state == S_SEND_POP) begin
            fl_pop = 1'b1;
        end

        if (state == S_SEND_ENQ) begin
            txq_enq      = 1'b1;
            txq_enq_data = {reg_tx_dest, reg_tx_len, reg_last_alloc_slot};

            // sender owns the slot until network confirms it was delivered - refcount = 1
            rc_inc      = 1'b1;
            rc_inc_slot = reg_last_alloc_slot;
        end

        if (state == S_RX_DEQ) begin
            rxq_deq = 1'b1;
        end

        // refcount dec arbitration - only one dec per cycle
        // priority: pending buffered dec > tx_done from network > core release
        if (pending_dec) begin
            rc_dec      = 1'b1;
            rc_dec_slot = pending_dec_slot;
        end else if (tx_done_valid) begin
            rc_dec      = 1'b1;
            rc_dec_slot = tx_done_slot;
        end else if (cmd_release_pulse) begin
            rc_dec      = 1'b1;
            rc_dec_slot = cmd_release_slot;
        end
    end

endmodule
