// RISCV_two_core_tb.sv - Testbench 
// Tests communication across cores and mailboxes: Core0 thread -> mailbox -> Core1 thread

// Architecture:
//   RISCV_two_core_top
//     - core0  (sender:   test8_core0_sender.hex)
//     - core1  (receiver: test8_core1_receiver.hex)
//     - router (inter_core_router: forwards TX->RX between cores)

// Pass condition: BOTH cores must write 0x00000001 to their own BRAM word 0xFF.
//   Core 0 PASS = successfully initiated TX send
//   Core 1 PASS = received the message, verified len == 0xC0, released slot
//---------------------------------------------------------------------------------------

`timescale 1ns / 1ps

module RISCV_two_core_tb;

    
    // Parameters
    parameter CLK_PERIOD     = 10;
    parameter TIMEOUT_CYCLES = 200000;

    parameter [11:0] PASS_WORD_ADDR = 12'h0FF;   // BRAM word 255
    parameter [31:0] PASS_DATA      = 32'h0000_0001;
    parameter [31:0] FAIL_DATA      = 32'hDEAD_BEEF;

    
    // Clock and Reset
    logic clk;
    logic reset;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    
    // DUT
    RISCV_two_core_top dut (
        .clk   (clk),
        .reset (reset)
    );

    
    // Hierarchical debug access
    

    //  Core 0 signals ------------------------------------------------
    wire [4:0]  c0_wr_addr    = dut.core0.DEBUG_regfile_wr_addr;
    wire [31:0] c0_wr_data    = dut.core0.DEBUG_regfile_wr_data;
    wire        c0_wr_en      = dut.core0.DEBUG_regfile_wr_en;
    wire [3:0]  c0_thread_wb  = dut.core0.DEBUG_thread_index_wb;
    wire [9:0]  c0_rom_addr   = dut.core0.rom_addr;
    wire [31:0] c0_rom_data   = dut.core0.rom_data;
    wire [13:0] c0_mem_addr   = dut.core0.RVcore_addr;
    wire [31:0] c0_mem_wdata  = dut.core0.RVcore_wr_data;
    wire [3:0]  c0_mem_wen    = dut.core0.RVcore_wr_en;
    wire        c0_mmio_en    = dut.core0.MMIO_EN;
    wire [31:0] c0_mmio_rdata = dut.core0.RVcore_rd_data;
    wire        c0_init_done  = dut.core0.u_mailbox.init_done;
    wire        c0_irq_rx     = dut.c0_irq_rx;

    //  Core 1 signals ----------------------------------------------
    wire [4:0]  c1_wr_addr    = dut.core1.DEBUG_regfile_wr_addr;
    wire [31:0] c1_wr_data    = dut.core1.DEBUG_regfile_wr_data;
    wire        c1_wr_en      = dut.core1.DEBUG_regfile_wr_en;
    wire [3:0]  c1_thread_wb  = dut.core1.DEBUG_thread_index_wb;
    wire [9:0]  c1_rom_addr   = dut.core1.rom_addr;
    wire [31:0] c1_rom_data   = dut.core1.rom_data;
    wire [13:0] c1_mem_addr   = dut.core1.RVcore_addr;
    wire [31:0] c1_mem_wdata  = dut.core1.RVcore_wr_data;
    wire [3:0]  c1_mem_wen    = dut.core1.RVcore_wr_en;
    wire        c1_mmio_en    = dut.core1.MMIO_EN;
    wire [31:0] c1_mmio_rdata = dut.core1.RVcore_rd_data;
    wire        c1_init_done  = dut.core1.u_mailbox.init_done;
    wire        c1_irq_rx     = dut.c1_irq_rx;

    //  Router FSM states (for waveform debugging) --------------------------
    wire [1:0]  router_c0c1   = dut.router.s_c0c1;
    wire [1:0]  router_c1c0   = dut.router.s_c1c0;

    
    // Cycle counter
    integer cycle_count;
    always_ff @(posedge clk) begin
        if (reset) cycle_count <= 0;
        else       cycle_count <= cycle_count + 1;
    end

    
    // Monitor: Core 0 instruction fetch (first 100 cycles)
    always @(posedge clk) begin
        if (!reset && cycle_count < 100) begin
            $display("[%0d] C0 FETCH: addr=%0d  instr=0x%08h",
                     cycle_count, c0_rom_addr, c0_rom_data);
        end
    end

    
    // Monitor: mailbox init done for each core
    always @(posedge clk) begin
        if (!reset && c0_init_done && !$past(c0_init_done)) begin
            $display("");
            $display("[Cycle %0d] CORE0 mailbox: freelist init done", cycle_count);
            $display("");
        end
        if (!reset && c1_init_done && !$past(c1_init_done)) begin
            $display("");
            $display("[Cycle %0d] CORE1 mailbox: freelist init done", cycle_count);
            $display("");
        end
    end

    
    // Monitor: router events (C0->C1 inject)
    always @(posedge clk) begin
        // When the router injects into Core 1s RX queue (c1_rx_in_valid + ready)
        if (!reset && dut.c1_rx_in_valid && dut.c1_rx_in_ready) begin
            $display("[Cycle %0d] ROUTER: C0->C1 delivered  {len=0x%02h, slot=%0d}",
                     cycle_count,
                     dut.c1_rx_in_data[15:8],
                     dut.c1_rx_in_data[7:0]);
        end
        // When the router injects into Core 0's RX queue (c0_rx_in_valid + ready)
        if (!reset && dut.c0_rx_in_valid && dut.c0_rx_in_ready) begin
            $display("[Cycle %0d] ROUTER: C1->C0 delivered  {len=0x%02h, slot=%0d}",
                     cycle_count,
                     dut.c0_rx_in_data[15:8],
                     dut.c0_rx_in_data[7:0]);
        end
    end

    
    // Monitor: IRQ_RX on each core
    always @(posedge clk) begin
        if (!reset && c0_irq_rx && !$past(c0_irq_rx))
            $display("[Cycle %0d] CORE0 IRQ_RX: message arrived in Core 0 RX queue",
                     cycle_count);
        if (!reset && c1_irq_rx && !$past(c1_irq_rx))
            $display("[Cycle %0d] CORE1 IRQ_RX: message arrived in Core 1 RX queue",
                     cycle_count);
    end

    
    // Monitor: MMIO writes (both cores)
    always @(posedge clk) begin
        if (!reset && (|c0_mem_wen) && c0_mem_addr[13:12] == 2'b10)
            $display("[Cycle %0d] C0 MMIO WRITE: offset=0x%02h  data=0x%08h",
                     cycle_count, {c0_mem_addr[5:0],2'b00}, c0_mem_wdata);
        if (!reset && (|c1_mem_wen) && c1_mem_addr[13:12] == 2'b10)
            $display("[Cycle %0d] C1 MMIO WRITE: offset=0x%02h  data=0x%08h",
                     cycle_count, {c1_mem_addr[5:0],2'b00}, c1_mem_wdata);
    end

    
    // Monitor: register file writes (both cores, nonzero registers)
    always @(posedge clk) begin
        if (!reset && c0_wr_en && c0_wr_addr != 0)
            $display("[Cycle %0d] C0 Thread %0d: x%0d <- 0x%08h",
                     cycle_count, c0_thread_wb, c0_wr_addr, c0_wr_data);
        if (!reset && c1_wr_en && c1_wr_addr != 0)
            $display("[Cycle %0d] C1 Thread %0d: x%0d <- 0x%08h",
                     cycle_count, c1_thread_wb, c1_wr_addr, c1_wr_data);
    end

    
    // Self chekc: both cores must write PASS to their own BRAM[0xFF]
    logic core0_passed, core1_passed;
    logic core0_failed, core1_failed;

    initial begin
        core0_passed = 0; core1_passed = 0;
        core0_failed = 0; core1_failed = 0;
    end

    always @(posedge clk) begin
        if (!reset && (|c0_mem_wen) && c0_mem_addr[13:12] == 2'b00
                   && c0_mem_addr[11:0] == PASS_WORD_ADDR) begin
            if (c0_mem_wdata == PASS_DATA) begin
                if (!core0_passed) $display("[Cycle %0d] CORE0: PASS", cycle_count);
                core0_passed = 1;
            end
            if (c0_mem_wdata == FAIL_DATA) begin
                $display("[Cycle %0d] CORE0: FAIL (wrote DEADBEEF)", cycle_count);
                core0_failed = 1;
            end
        end
        if (!reset && (|c1_mem_wen) && c1_mem_addr[13:12] == 2'b00
                   && c1_mem_addr[11:0] == PASS_WORD_ADDR) begin
            if (c1_mem_wdata == PASS_DATA) begin
                if (!core1_passed) $display("[Cycle %0d] CORE1: PASS", cycle_count);
                core1_passed = 1;
            end
            if (c1_mem_wdata == FAIL_DATA) begin
                $display("[Cycle %0d] CORE1: FAIL (wrote DEADBEEF)", cycle_count);
                core1_failed = 1;
            end
        end
    end

    // Declare test_done as a logic variable driven from always block
    logic test_done;
    initial test_done = 0;

    always @(posedge clk) begin
        if (!reset && !test_done) begin
            // Both cores passed
            if (core0_passed && core1_passed) begin
                $display("");
                $display("---------------------------------------------");
                $display("  CROSS CORE TEST PASSED");
                $display("  Core0 Thread -> Mailbox -> Core1 Thread");
                $display("  Both cores confirmed success.");
                $display("----------------------------------------------");
                $display("");
                test_done = 1;
            end
            // Any failure
            if (core0_failed || core1_failed) begin
                $display("");
                $display("--------------------------------------------");
                $display("  CROSS CORE TEST FAILED");
                $display("  Core0 fail=%0b  Core1 fail=%0b",
                         core0_failed, core1_failed);
                $display("--------------------------------------------");
                $display("");
                test_done = 1;
            end
        end
    end

    
    // Timeout
    
    always @(posedge clk) begin
        if (cycle_count >= TIMEOUT_CYCLES && !test_done) begin
            $display("");
            $display("-------------------------------------------------");
            $display("  TIMEOUT after %0d cycles", TIMEOUT_CYCLES);
            $display("  core0_passed=%0b  core1_passed=%0b",
                     core0_passed, core1_passed);
            $display("  C0 init=%0b  C1 init=%0b",
                     c0_init_done, c1_init_done);
            $display("  router C0->C1 state=%0d  C1->C0 state=%0d",
                     router_c0c1, router_c1c0);
            $display("---------------------------------------------------");
            $display("");
            test_done = 1;
        end
    end

    
    // Finish
    
    always @(posedge clk) begin
        if (test_done) begin
            repeat (64) @(posedge clk);
            $finish;
        end
    end

    
    // Waveform
    
    initial begin
        $dumpfile("briski_two_core_tb.vcd");
        $dumpvars(0, RISCV_two_core_tb);
    end

    
    // Reset sequence
    
    initial begin
        $display("");
        $display("---------------------------------------------");
        $display("  BRISKI 2Core 2Mailbox Testbench ");
        $display("  Core0 (sender) <-> Router <-> Core1 (receiver)");
        $display("---------------------------------------------");
        $display("");

        reset = 1;
        repeat (300) @(posedge clk);
        reset = 0;

        $display("[Cycle 0] Reset deasserted, both cores running");
        $display("  Core 0: sender  (test8_core0_sender.hex)");
        $display("  Core 1: receiver (test8_core1_receiver.hex)");
        $display("");
    end

endmodule
