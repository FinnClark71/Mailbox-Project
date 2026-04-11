// BRISKI Core with mailbox Simulation Testbench 

// Changes from standalone:
//   - Updated DUT port list to match RISCV_core_top with mailbox integrated.
//     Old sync ports (i_uram_emptied, o_core_req etc...) removed.
//   - Added mailbox monitor: watches STATUS register via the TX queue drain 
//     port, prints when core asserts a send, and watches irq_rx.
//   - Timeout increased to 100000 cycles (freelist init takes ~256 cycles
//     before any mailbox op can proceed).

// Pass/fail convention is the same:
//   Write 0x00000001 to BRAM word address 0xFF (byte 0x3FC) = PASS
//   Write 0xDEADBEEF to BRAM word address 0xFF              = FAIL
//-------------------------------------------------------------------------------------------

`timescale 1ns / 1ps

module RISCV_core_top_tb;


    // Parameters
    parameter CLK_PERIOD     = 10;
    parameter TIMEOUT_CYCLES = 100000;

    parameter [13:0] PASS_ADDR = 14'h00FF;
    parameter [31:0] PASS_DATA = 32'h0000_0001;
    parameter [31:0] FAIL_DATA = 32'hDEAD_BEEF;


    // Clock and Reset
    logic clk;
    logic reset;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;


    // DUT signals
    //--------------------------------------------------

    // URAM (unused in standalone, driven by DUT)
    logic        o_URAM_en;
    logic [11:0] o_URAM_addr;
    logic [31:0] o_URAM_wr_data;
    logic        o_URAM_wr_en;

    // Mailbox: TX queue drain (network side)
    logic        o_txq_deq_valid;
    logic        o_txq_deq_ready;
    logic [19:0] o_txq_deq_data;

    // Mailbox: RX descriptor inject (network side)
    logic        o_rx_in_ready;

    // Mailbox: RX interrupt
    logic        o_irq_rx;

    
    // Standalone tie offs
    // Nothing drains the TX queue from the network side
    // Nothing injects RX messages
    // Nothing sends TX done acknowledgements

    
    // DUT Instantiation
    RISCV_core_top dut (
        .clk              (clk),
        .reset            (reset),

        // URAM (not used in standalone)
        .o_URAM_en        (o_URAM_en),
        .o_URAM_addr      (o_URAM_addr),
        .o_URAM_wr_data   (o_URAM_wr_data),
        .o_URAM_wr_en     (o_URAM_wr_en),

        // Mailbox TX drain tied off (no network to drain)
        .i_txq_deq        (1'b0),
        .o_txq_deq_data   (o_txq_deq_data),
        .o_txq_deq_valid  (o_txq_deq_valid),
        .o_txq_deq_ready  (o_txq_deq_ready),

        // Mailbox RX inject tied off (no network to inject from)
        .i_rx_in_valid    (1'b0),
        .i_rx_in_data     (16'b0),
        .o_rx_in_ready    (o_rx_in_ready),

        // TX done tied off
        .i_tx_done_valid  (1'b0),
        .i_tx_done_slot   (8'b0),

        // RX interrupt
        .o_irq_rx         (o_irq_rx)
    );

    
    // Internal debug signals via hierarchical references
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
    wire        dbg_mailbox_init_done = dut.u_mailbox.init_done;
    wire        dbg_txq_empty         = dut.u_mailbox.txq_empty;
    wire        dbg_rxq_empty         = dut.u_mailbox.rxq_empty;
    wire        dbg_fl_empty          = dut.u_mailbox.fl_empty;

    
    // Cycle counter
    integer cycle_count;

    always_ff @(posedge clk) begin
        if (reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    
    // BRAM load check
    integer zero_fetch_count;
    initial zero_fetch_count = 0;

    always @(posedge clk) begin
        if (!reset && cycle_count < 50) begin
            if (dbg_rom_data == 32'h00000000 || dbg_rom_data === 32'hxxxxxxxx)
                zero_fetch_count <= zero_fetch_count + 1;
        end
        if (!reset && cycle_count == 50) begin
            if (zero_fetch_count >= 45) begin
                $display("");
                $display(" BRAM EMPTY (all zero/X fetches)");
                $display("");
            end else begin
                $display("");
                $display("  >> BRAM loaded, non-zero instructions detected");
                $display("");
            end
        end
    end

    
    // Monitor: instruction fetches (first 10 cycles)
    always @(posedge clk) begin
        if (!reset && cycle_count < 10) begin
            $display("[Cycle %0d] FETCH: rom_addr=%0d (0x%03h)  instr=0x%08h",
                     cycle_count, dbg_rom_addr, dbg_rom_addr, dbg_rom_data);
        end
    end

    
    // Monitor: register file writes
    always @(posedge clk) begin
        if (!reset && dbg_wr_en && dbg_wr_addr != 0) begin
            $display("[Cycle %0d] Thread %0d: x%0d <- 0x%08h",
                     cycle_count, dbg_thread_wb, dbg_wr_addr, dbg_wr_data);
        end
    end

    
    // Monitor: BRAM data memory writes
    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b00) begin
            $display("[Cycle %0d] MEM WRITE: addr=0x%04h data=0x%08h we=0b%04b",
                     cycle_count, dbg_dmem_addr, dbg_dmem_wr_data, dbg_dmem_wr_en);
        end
    end

    
    // Monitor: mailbox init done
    always @(posedge clk) begin
        if (!reset && dbg_mailbox_init_done &&
            !$past(dbg_mailbox_init_done, 1)) begin
            $display("");
            $display("[Cycle %0d] MAILBOX: freelist init complete, mailbox ready",
                     cycle_count);
            $display("");
        end
    end

    
    // Monitor: MMIO (mailbox) writes from core
    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b10) begin
            $display("[Cycle %0d] MMIO WRITE: offset=0x%02h data=0x%08h",
                     cycle_count, dbg_dmem_addr[7:0], dbg_dmem_wr_data);
        end
    end

    
    // Monitor: MMIO (mailbox) reads from core
    always @(posedge clk) begin
        if (!reset && !(|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b10 &&
            dut.MMIO_EN) begin
            $display("[Cycle %0d] MMIO READ:  offset=0x%02h -> 0x%08h",
                     cycle_count, dbg_dmem_addr[7:0], dbg_dmem_rd_data);
        end
    end

    
    // Monitor: TX queue gets a new entry (core triggered a send)
    always @(posedge clk) begin
        if (!reset && o_txq_deq_valid && !$past(o_txq_deq_valid, 1)) begin
            $display("[Cycle %0d] MAILBOX TX: message queued -- dest=%0d len=%0d slot=%0d",
                     cycle_count,
                     o_txq_deq_data[19:16],   // dest [DEST_W-1:0] = top 4 bits
                     o_txq_deq_data[15:8],    // len  [LEN_W-1:0]
                     o_txq_deq_data[7:0]);    // slot [SLOT_W-1:0]
        end
    end

    
    // Monitor: IRQ_RX assertion (incoming message waiting)
    always @(posedge clk) begin
        if (!reset && o_irq_rx && !$past(o_irq_rx, 1)) begin
            $display("[Cycle %0d] MAILBOX RX IRQ: incoming message in RX queue",
                     cycle_count);
        end
    end

    
    // Self check: PASS/FAIL detection (BRAM write to word 0xFF)
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
                $display("  TEST PASSED at cycle %0d", cycle_count);
                $display("--------------------------------------------");
                $display("");
                test_done   = 1;
                test_passed = 1;
            end
            if (dbg_dmem_addr[11:0] == PASS_ADDR[11:0] && dbg_dmem_wr_data == FAIL_DATA) begin
                $display("");
                $display("--------------------------------------------");
                $display("  TEST FAILED at cycle %0d", cycle_count);
                $display("--------------------------------------------");
                $display("");
                test_done   = 1;
                test_passed = 0;
            end
        end
    end

    
    // Timeout watchdog
    always @(posedge clk) begin
        if (cycle_count >= TIMEOUT_CYCLES && !test_done) begin
            $display("");
            $display("----------------------------------------------------");
            $display("  TIMEOUT after %0d cycles - no pass or fail detected",
                     TIMEOUT_CYCLES);
            $display("  Mailbox init_done at timeout: %0b", dbg_mailbox_init_done);
            $display("  txq_empty=%0b  rxq_empty=%0b  fl_empty=%0b",
                     dbg_txq_empty, dbg_rxq_empty, dbg_fl_empty);
            $display("----------------------------------------------------");
            $display("");
            test_done = 1;
        end
    end

    
    // Finish simulation after test completes
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

    
    // Reset sequence
    // Hold reset long enough for:
    //   - Pipeline flush: NUM_THREADS * NUM_PIPE_STAGES cycles
    //   - Mailbox freelist init: ~256 cycles (256 slots, 1 push/cycle)
    // 300 cycles covers the pipeline. The freelist finishes during normal
    // execution so the core must poll STATUS bit2 before using the mailbox.
    initial begin
        $display("");
        $display("--------------------------------------------");
        $display("  BRISKI Core with Mailbox communication test");
        $display("-------------------------------------------");
        $display("");

        reset = 1;
        repeat (300) @(posedge clk);
        reset = 0;
        $display("[Cycle 0] Reset de-asserted - core is running");
        $display("");
        $display("  NOTE: Mailbox freelist initialises ~256 cycles after reset.");
        $display("  Test programs using the mailbox must poll STATUS bit2 first.");
        $display("");
    end

endmodule
