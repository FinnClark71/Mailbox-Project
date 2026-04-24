// BRISKI Core with Mailbox Simulation Testbench updated

// Changes:
//   - new network simu: tb simulates the network side.
//     It automatically drains the TX queue and re-injects every descriptor back as an RX message (creating the loopback). 
//     This enables thread->mailbox->thread communication tests in simulation.

// Test hex programs used with this tb:
//   test5_mailbox.hex - TX send, poll init_done, write PASS  
//   test6_mailbox_loopback.hex - TX send, RX receive, verify {len} field
//   test7_mailbox_slotread.hex - TX send, read back slot, verify range, release

// Pass condition is same:
//   Write 0x00000001 to BRAM word address 0xFF (byte 0x3FC) = pass
//   Write 0xDEADBEEF to BRAM word address 0xFF              = fail
//-------------------------------------------------------------------------------------------

`timescale 1ns / 1ps

module RISCV_core_top_tb;

    
    // Parameters
    parameter CLK_PERIOD     = 10;
    parameter TIMEOUT_CYCLES = 200000;   // double previous as loopback adds latency

    parameter [13:0] PASS_ADDR = 14'h00FF;
    parameter [31:0] PASS_DATA = 32'h0000_0001;
    parameter [31:0] FAIL_DATA = 32'hDEAD_BEEF;

    
    // declarations
    logic clk;
    logic reset;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    
    // DUT signals
    //--------------------------------------------------
    
    logic        o_URAM_en;
    logic [11:0] o_URAM_addr;
    logic [31:0] o_URAM_wr_data;
    logic        o_URAM_wr_en;

    logic        o_txq_deq_valid;
    logic        o_txq_deq_ready;
    logic [19:0] o_txq_deq_data;
    logic        o_rx_in_ready;
    logic        o_irq_rx;

    
    // Tieofs replaced by network driven signals
    
    logic        tb_txq_deq;       
    logic        tb_rx_in_valid;   
    logic [15:0] tb_rx_in_data;    

    // Storage for captured TX descriptors (up to 16)
    logic [19:0] tb_drain_buf [0:15];
    integer      tb_drain_cnt;     // total descriptors drained so far
    integer      tb_inject_done;   // total descriptors injected so far

    
    // DUT 
    RISCV_core_top dut (
        .clk              (clk),
        .reset            (reset),
        .o_URAM_en        (o_URAM_en),
        .o_URAM_addr      (o_URAM_addr),
        .o_URAM_wr_data   (o_URAM_wr_data),
        .o_URAM_wr_en     (o_URAM_wr_en),
        .i_txq_deq        (tb_txq_deq),
        .o_txq_deq_data   (o_txq_deq_data),
        .o_txq_deq_valid  (o_txq_deq_valid),
        .o_txq_deq_ready  (o_txq_deq_ready),
        .i_rx_in_valid    (tb_rx_in_valid),
        .i_rx_in_data     (tb_rx_in_data),
        .o_rx_in_ready    (o_rx_in_ready),
        .i_tx_done_valid  (1'b0),
        .i_tx_done_slot   (8'b0),
        .o_irq_rx         (o_irq_rx)
    );

    
    // debug signals
    wire [4:0]  dbg_wr_addr      = dut.DEBUG_regfile_wr_addr;
    wire [31:0] dbg_wr_data      = dut.DEBUG_regfile_wr_data;
    wire        dbg_wr_en        = dut.DEBUG_regfile_wr_en;
    wire [3:0]  dbg_thread_wb    = dut.DEBUG_thread_index_wb;

    wire [9:0]  dbg_rom_addr     = dut.rom_addr;
    wire [31:0] dbg_rom_data     = dut.rom_data;

    wire [13:0] dbg_dmem_addr    = dut.RVcore_addr;
    wire [31:0] dbg_dmem_wr_data = dut.RVcore_wr_data;
    wire [3:0]  dbg_dmem_wr_en   = dut.RVcore_wr_en;
    wire [31:0] dbg_dmem_rd_data = dut.RVcore_rd_data;

    // Mailbox internal state
    wire        dbg_mb_init_done = dut.u_mailbox.init_done;
    wire        dbg_txq_empty    = dut.u_mailbox.txq_empty;
    wire        dbg_rxq_empty    = dut.u_mailbox.rxq_empty;
    wire        dbg_fl_empty     = dut.u_mailbox.fl_empty;

    
    // Cycle counter
    integer cycle_count;
    always_ff @(posedge clk) begin
        if (reset) 
            cycle_count <= 0;
        else       
            cycle_count <= cycle_count + 1;
    end

    
    // active network sim
    initial begin
        tb_txq_deq     = 0;
        tb_rx_in_valid = 0;
        tb_rx_in_data  = '0;
        tb_drain_cnt   = 0;
        tb_inject_done = 0;

        // Wait until out of reset
        wait (reset === 1'b0);
        @(posedge clk);

        forever begin

            // DRAIN: wait for TX descriptor then pop it
  
            // Block until something is in TX queue
            while (!o_txq_deq_ready) @(posedge clk);

            // Pulse deq for 1 clock edge
            // (tx_queue latches mem[rd_ptr] and sets deq_valid_q on the NEXT edge)
            tb_txq_deq = 1;
            @(posedge clk);  
            tb_txq_deq = 0;
            @(posedge clk);   

            // Capture descriptor on the cycle deq_valid is asserted
            if (o_txq_deq_valid) begin
                automatic logic [3:0]  cap_dest = o_txq_deq_data[19:16];
                automatic logic [7:0]  cap_len  = o_txq_deq_data[15:8];
                automatic logic [7:0]  cap_slot = o_txq_deq_data[7:0];

                tb_drain_buf[tb_drain_cnt] = o_txq_deq_data;
                $display("");
                $display("[Cycle %0d] TB-NET DRAIN  #%0d: dest=%0d  len=0x%02h  slot=%0d",
                         cycle_count, tb_drain_cnt, cap_dest, cap_len, cap_slot);

   
                // INJECT: redeliver the same descriptor as an RX message
                // Sim 8 cycles of network latency
                repeat (8) @(posedge clk);

                tb_rx_in_data  = {cap_len, cap_slot};   // {len[7:0], slot[7:0]}
                tb_rx_in_valid = 1;

                // Hold valid until mailbox handshake completes.
                while (!o_rx_in_ready) @(posedge clk);
                @(posedge clk);  
                tb_rx_in_valid = 0;

                $display("[Cycle %0d] TB-NET INJECT #%0d: len=0x%02h  slot=%0d  → rxq",
                         cycle_count, tb_inject_done, cap_len, cap_slot);
                $display("");

                tb_drain_cnt++;
                tb_inject_done++;
            end

            @(posedge clk);
        end
    end



    // BRAM load check 
    integer zero_fetch_count;
    initial zero_fetch_count = 0;

    always @(posedge clk) begin
        if (!reset && cycle_count < 50) begin
            if (dbg_rom_data == 32'h0 || dbg_rom_data === 32'hxxxxxxxx)
                zero_fetch_count <= zero_fetch_count + 1;
        end
        if (!reset && cycle_count == 50) begin
            if (zero_fetch_count >= 45)
                $display(" BRAM EMPTY (all zero/X fetches)");
            else
                $display("  >> BRAM loaded ok");
        end
    end

    

    // Monitors:
    //--------------------------------------------------------------------------------

    // instruction fetches (first 10 cycles)
    always @(posedge clk) begin
        if (!reset && cycle_count < 10) begin
            $display("[Cycle %0d] FETCH: rom_addr=%0d (0x%03h)  instr=0x%08h",
                     cycle_count, dbg_rom_addr, dbg_rom_addr, dbg_rom_data);
        end
    end

    
    // reg file writes
    always @(posedge clk) begin
        if (!reset && dbg_wr_en && dbg_wr_addr != 0) begin
            $display("[Cycle %0d] Thread %0d: x%0d <- 0x%08h",
                     cycle_count, dbg_thread_wb, dbg_wr_addr, dbg_wr_data);
        end
    end

    
    // BRAM data mem writes
    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b00) begin
            $display("[Cycle %0d] MEM WRITE:  addr=0x%04h  data=0x%08h  we=0b%04b",
                     cycle_count, dbg_dmem_addr, dbg_dmem_wr_data, dbg_dmem_wr_en);
        end
    end

    
    // mailbox init done
    always @(posedge clk) begin
        if (!reset && dbg_mb_init_done && !$past(dbg_mb_init_done, 1)) begin
            $display("");
            $display("[Cycle %0d] MAILBOX: freelist init done, mailbox ready", cycle_count);
            $display("");
        end
    end

    // MMIO (mailbox) writes from core 
    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b10) begin
            $display("[Cycle %0d] MMIO WRITE: byte_offset=0x%02h  data=0x%08h",
                     cycle_count,
                     {dbg_dmem_addr[5:0], 2'b00},   // reconstruct byte offset
                     dbg_dmem_wr_data);
        end
    end


    // MMIO (mailbox) reads from core
    always @(posedge clk) begin
        if (!reset && !(|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b10
                   && dut.MMIO_EN) begin
            $display("[Cycle %0d] MMIO READ:  byte_offset=0x%02h  -> 0x%08h",
                     cycle_count,
                     {dbg_dmem_addr[5:0], 2'b00},
                     dbg_dmem_rd_data);
        end
    end

    
    // IRQ_RX rising edge
    always @(posedge clk) begin
        if (!reset && o_irq_rx && !$past(o_irq_rx, 1)) begin
            $display("[Cycle %0d] MAILBOX IRQ_RX: incoming RX descriptor available",
                     cycle_count);
        end
    end

    
    // pass detection
    logic test_done;
    logic test_passed;

    initial begin
        test_done   = 0;
        test_passed = 0;
    end

    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b00) begin
            if (dbg_dmem_addr[11:0] == PASS_ADDR[11:0] && dbg_dmem_wr_data == PASS_DATA) begin
                $display("");
                $display("--------------------------------------------");
                $display("  test passed at cycle %0d", cycle_count);
                $display("--------------------------------------------");
                $display("");
                test_done   = 1;
                test_passed = 1;
            end
            if (dbg_dmem_addr[11:0] == PASS_ADDR[11:0] && dbg_dmem_wr_data == FAIL_DATA) begin
                $display("");
                $display("--------------------------------------------");
                $display("  test failed at cycle %0d", cycle_count);
                $display("--------------------------------------------");
                $display("");
                test_done   = 1;
                test_passed = 0;
            end
        end
    end

    
    // Timeout 
    
    always @(posedge clk) begin
        if (cycle_count >= TIMEOUT_CYCLES && !test_done) begin
            $display("");
            $display("----------------------------------------------------");
            $display("  timeout after %0d cycles", TIMEOUT_CYCLES);
            $display("  mailbox init_done at timeout: %0b", dbg_mb_init_done);
            $display("  txq_empty = %0b  rxq_empty = %0b  fl_empty = %0b",
                     dbg_txq_empty, dbg_rxq_empty, dbg_fl_empty);
            $display("  tb_drain_cnt = %0d  tb_inject_done = %0d",
                     tb_drain_cnt, tb_inject_done);
            $display("----------------------------------------------------");
            $display("");
            test_done = 1;
        end
    end

    
    // Finish sim
    always @(posedge clk) begin
        if (test_done) begin
            repeat (64) @(posedge clk);
            $finish;
        end
    end

    
    // Waveform dump
    initial begin
        $dumpfile("briski_tb.vcd");
        $dumpvars(0, RISCV_core_top_tb);
    end

    
    // Reset
    initial begin
        $display("");
        $display("--------------------------------------------");
        $display("  BRISKI Core with Mailbox tx/rx communication test ");
        $display("--------------------------------------------");
        $display("");

        reset = 1;
        repeat (300) @(posedge clk);
        reset = 0;
        $display("[Cycle 0] Reset - core is running");
        $display("");
        $display("  Mailbox freelist initialises ~256 cycles after reset.");
        $display("");
    end

endmodule
