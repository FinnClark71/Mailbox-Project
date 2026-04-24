// RISCV_two_core_tb.sv - Testbench (Test 9: Bidirectional Shift-Multiply Ping-Pong)
// Tests bidirectional communication across cores and mailboxes

// Architecture:
//   RISCV_two_core_top
//     - core0  (sender:   test9_core0.hex)
//     - core1  (receiver: test9_core1.hex)
//     - router (inter_core_router: forwards TX->RX between cores, both directions)

// What each core does:
//   Core 0 computes 17x13 via shift-add = 221 = 0xDD
//           applies 0xDD XOR 0xAA = 0x77
//           sends TX_LEN=0x77 to Core 1

//   Core 1 receives 0x77, verifies it,
//           computes reply: (0x77 << 1) & 0xFF = 0xEE
//                           0xEE XOR 0x55 = 0xBB
//           sends TX_LEN=0xBB back to Core 0

//   Core 0 receives 0xBB, verifies it, then writes pass

// This proves:
//   - Both router directions (C0->C1 and C1->C0) carry correct data
//   - Both cores' RX and TX paths work independently
//   - Core 0's pass is causally blocked on Core 1's correct computation
//   - Multi instruction ALU chains (SLL, ADD, XOR) produce correct results

// Pass condition: both cores write 0x00000001 to their own BRAM word 0xFF.
//   Core 1 passes first (fires PASS after sending reply).
//   Core 0 passes only after verifying the reply content.
//---------------------------------------------------------------------------------------

`timescale 1ns / 1ps

module RISCV_two_core_tb;

    
    // Parameters
    parameter CLK_PERIOD     = 10;
    parameter TIMEOUT_CYCLES = 300000;  // increased from 200000 to be safe due to longer test

    parameter [11:0] PASS_WORD_ADDR = 12'h0FF;
    parameter [31:0] PASS_DATA      = 32'h0000_0001;
    parameter [31:0] FAIL_DATA      = 32'hDEAD_BEEF;

    
    // declarations
    logic clk, reset;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    
    // DUT
    // New ports exposed on top: IRQ and txq_ready outputs (previously internal only)
    RISCV_two_core_top dut (
        .clk   (clk),
        .reset (reset),
        .o_c0_irq_rx    (),
        .o_c1_irq_rx    (),
        .o_c0_txq_ready (),
        .o_c1_txq_ready ()
    );

    

    //  Core 0 signals ------------------------------------------------
    wire [4:0]  c0_wr_addr   = dut.core0.DEBUG_regfile_wr_addr;
    wire [31:0] c0_wr_data   = dut.core0.DEBUG_regfile_wr_data;
    wire        c0_wr_en     = dut.core0.DEBUG_regfile_wr_en;
    wire [3:0]  c0_thread_wb = dut.core0.DEBUG_thread_index_wb;
    wire [13:0] c0_mem_addr  = dut.core0.RVcore_addr;
    wire [31:0] c0_mem_wdata = dut.core0.RVcore_wr_data;
    wire [3:0]  c0_mem_wen   = dut.core0.RVcore_wr_en;
    wire        c0_init_done = dut.core0.u_mailbox.init_done;
    wire        c0_irq_rx    = dut.c0_irq_rx;

    //  Core 1 signals ----------------------------------------------
    wire [4:0]  c1_wr_addr   = dut.core1.DEBUG_regfile_wr_addr;
    wire [31:0] c1_wr_data   = dut.core1.DEBUG_regfile_wr_data;
    wire        c1_wr_en     = dut.core1.DEBUG_regfile_wr_en;
    wire [3:0]  c1_thread_wb = dut.core1.DEBUG_thread_index_wb;
    wire [13:0] c1_mem_addr  = dut.core1.RVcore_addr;
    wire [31:0] c1_mem_wdata = dut.core1.RVcore_wr_data;
    wire [3:0]  c1_mem_wen   = dut.core1.RVcore_wr_en;
    wire        c1_init_done = dut.core1.u_mailbox.init_done;
    wire        c1_irq_rx    = dut.c1_irq_rx;

    //  Router FSM states --------------------------
    wire [1:0] router_c0c1 = dut.router.s_c0c1;
    wire [1:0] router_c1c0 = dut.router.s_c1c0;

    
    // Cycle counter
    integer cycle_count;
    always_ff @(posedge clk)
        if (reset) cycle_count <= 0;
        else       cycle_count <= cycle_count + 1;

    
    // Monitors:
    //--------------------------------------------------------------------------------

    // mailbox init done for each core
    always @(posedge clk) begin
        if (!reset && c0_init_done && !$past(c0_init_done)) begin
            $display(""); $display("[Cycle %0d] CORE0 mailbox: freelist init done", cycle_count); $display("");
        end
        if (!reset && c1_init_done && !$past(c1_init_done)) begin
            $display(""); $display("[Cycle %0d] CORE1 mailbox: freelist init done", cycle_count); $display("");
        end
    end

    
    // router events - now monitors both directions (C0->C1 and C1->C0)
    always @(posedge clk) begin
        // When the router injects into Core 1's RX queue (c1_rx_in_valid + ready)
        if (!reset && dut.c1_rx_in_valid && dut.c1_rx_in_ready)
            $display("[Cycle %0d] ROUTER C0->C1: {len=0x%02h, slot=%0d}",
                     cycle_count, dut.c1_rx_in_data[15:8], dut.c1_rx_in_data[7:0]);
        // When the router injects into Core 0's RX queue (c0_rx_in_valid + ready)
        if (!reset && dut.c0_rx_in_valid && dut.c0_rx_in_ready)
            $display("[Cycle %0d] ROUTER C1->C0: {len=0x%02h, slot=%0d}",
                     cycle_count, dut.c0_rx_in_data[15:8], dut.c0_rx_in_data[7:0]);
    end

    
    // IRQ_RX on each core
    always @(posedge clk) begin
        if (!reset && c0_irq_rx && !$past(c0_irq_rx))
            $display("[Cycle %0d] CORE0 IRQ_RX: reply from Core 1 arrived", cycle_count);
        if (!reset && c1_irq_rx && !$past(c1_irq_rx))
            $display("[Cycle %0d] CORE1 IRQ_RX: message from Core 0 arrived", cycle_count);
    end

    
    // MMIO writes (both cores) - decoded with semantic labels for this test
    always @(posedge clk) begin
        if (!reset && (|c0_mem_wen) && c0_mem_addr[13:12] == 2'b10) begin
            automatic logic [7:0] boff = {c0_mem_addr[5:0], 2'b00};
            case (boff)
                8'h04: $display("[Cycle %0d] C0  TX_DEST  = %0d",        cycle_count, c0_mem_wdata);
                8'h08: $display("[Cycle %0d] C0  TX_LEN   = 0x%02h (17x13 XOR 0xAA)", cycle_count, c0_mem_wdata[7:0]);
                8'h0C: $display("[Cycle %0d] C0  TX_SEND  -> mailbox FSM fires", cycle_count);
                8'h10: $display("[Cycle %0d] C0  RX_POP   -> reading reply descriptor", cycle_count);
                8'h14: $display("[Cycle %0d] C0  REL_SLOT = %0d",        cycle_count, c0_mem_wdata);
                default: $display("[Cycle %0d] C0  MMIO WRITE offset=0x%02h data=0x%08h", cycle_count, boff, c0_mem_wdata);
            endcase
        end
        if (!reset && (|c1_mem_wen) && c1_mem_addr[13:12] == 2'b10) begin
            automatic logic [7:0] boff = {c1_mem_addr[5:0], 2'b00};
            case (boff)
                8'h04: $display("[Cycle %0d] C1  TX_DEST  = %0d",        cycle_count, c1_mem_wdata);
                8'h08: $display("[Cycle %0d] C1  TX_LEN   = 0x%02h (computed reply)", cycle_count, c1_mem_wdata[7:0]);
                8'h0C: $display("[Cycle %0d] C1  TX_SEND  -> reply dispatched to Core 0", cycle_count);
                8'h10: $display("[Cycle %0d] C1  RX_POP   -> reading received descriptor", cycle_count);
                8'h14: $display("[Cycle %0d] C1  REL_SLOT = %0d",        cycle_count, c1_mem_wdata);
                default: $display("[Cycle %0d] C1  MMIO WRITE offset=0x%02h data=0x%08h", cycle_count, boff, c1_mem_wdata);
            endcase
        end
    end

    
    // reg file writes - filtered to the key registers for this test's ALU chains
    // C0: x4 = accumulator for 17x13, x6 = reply len verify
    // C1: x3 = received len from C0, x6 = computed reply value
    always @(posedge clk) begin
        if (!reset && c0_wr_en && c0_wr_addr == 4 && c0_thread_wb == 0)
            $display("[Cycle %0d] C0  x4 (accumulator) <- 0x%08h", cycle_count, c0_wr_data);
        if (!reset && c0_wr_en && c0_wr_addr == 6 && c0_thread_wb == 0)
            $display("[Cycle %0d] C0  x6 (reply len)   <- 0x%08h", cycle_count, c0_wr_data);
        if (!reset && c1_wr_en && c1_wr_addr == 3 && c1_thread_wb == 0)
            $display("[Cycle %0d] C1  x3 (received len) <- 0x%08h", cycle_count, c1_wr_data);
        if (!reset && c1_wr_en && c1_wr_addr == 6 && c1_thread_wb == 0)
            $display("[Cycle %0d] C1  x6 (computed reply) <- 0x%08h", cycle_count, c1_wr_data);
    end

    
    // pass detection
    logic core0_passed, core1_passed;
    logic core0_failed, core1_failed;

    initial begin
        core0_passed = 0; core1_passed = 0;
        core0_failed = 0; core1_failed = 0;
    end

    always @(posedge clk) begin
        if (!reset && (|c0_mem_wen) && c0_mem_addr[13:12]==2'b00
                   && c0_mem_addr[11:0]==PASS_WORD_ADDR) begin
            if (c0_mem_wdata == PASS_DATA) begin
                if (!core0_passed)
                    $display("[Cycle %0d] core0 pass - reply 0xBB verified correctly", cycle_count);
                core0_passed = 1;
            end
            if (c0_mem_wdata == FAIL_DATA) begin
                $display("[Cycle %0d] core0 fail - reply len mismatch (got 0x%02h, expected 0xBB)",
                         cycle_count, dut.core0.RVcore_rd_data[15:8]);
                core0_failed = 1;
            end
        end
        if (!reset && (|c1_mem_wen) && c1_mem_addr[13:12]==2'b00
                   && c1_mem_addr[11:0]==PASS_WORD_ADDR) begin
            if (c1_mem_wdata == PASS_DATA) begin
                if (!core1_passed)
                    $display("[Cycle %0d] core1 pass - received 0x77, replied 0xBB correctly", cycle_count);
                core1_passed = 1;
            end
            if (c1_mem_wdata == FAIL_DATA) begin
                $display("[Cycle %0d] core1 fail - received len mismatch (expected 0x77)",
                         cycle_count);
                core1_failed = 1;
            end
        end
    end

    logic test_done;
    initial test_done = 0;

    always @(posedge clk) begin
        if (!reset && !test_done) begin
            // Both cores passed
            if (core0_passed && core1_passed) begin
                $display("");
                $display("---------------------------------------------");
                $display("  Test 9 passed");
                $display("  C0 computed 17x13=0xDD, XOR 0xAA -> sent 0x77");
                $display("  C1 received 0x77, replied (0x77<<1)^0x55 = 0xBB");
                $display("  C0 received 0xBB, both cores confirmed success");
                $display("  Both router directions exercised with verified content");
                $display("----------------------------------------------");
                $display("");
                test_done = 1;
            end
            // Any failure
            if (core0_failed || core1_failed) begin
                $display("");
                $display("--------------------------------------------");
                $display("  Test 9 failed");
                $display("  Core0 fail=%0b  Core1 fail=%0b", core0_failed, core1_failed);
                $display("  C0 failed = rx len mismatch from Core 1");
                $display("  C1 failed = tx len from Core 0 corrupted in transit");
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
            $display("  timeout after %0d cycles", TIMEOUT_CYCLES);
            $display("  core0_passed=%0b  core1_passed=%0b", core0_passed, core1_passed);
            $display("  C0 init=%0b  C1 init=%0b", c0_init_done, c1_init_done);
            $display("  C0 irq_rx=%0b  C1 irq_rx=%0b", c0_irq_rx, c1_irq_rx);
            $display("  router C0->C1 state=%0d  C1->C0 state=%0d",
                     router_c0c1, router_c1c0);
            $display("  Likely stuck: %s",
                     (!c1_irq_rx) ? "C0->C1 router not delivered" :
                     (!core1_passed) ? "C1 ALU verify or reply failed" :
                     (!c0_irq_rx) ? "C1->C0 router not delivered" :
                     "C0 ALU verify of reply failed");
            $display("---------------------------------------------------");
            $display("");
            test_done = 1;
        end
    end

    
    // Finish sim
    always @(posedge clk)
        if (test_done) begin repeat (64) @(posedge clk); $finish; end

    
    // Waveform dump
    initial begin
        $dumpfile("briski_test9.vcd");
        $dumpvars(0, RISCV_two_core_tb);
    end

    
    // Reset
    initial begin
        $display("");
        $display("---------------------------------------------");
        $display("  BRISKI 2Core 2Mailbox Testbench - Test 9");
        $display("  Bidirectional ALU Shift-Multiply Ping-Pong");
        $display("---------------------------------------------");
        $display("  Core 0: computes 17x13 via SLL+ADD, XORs 0xAA -> 0x77");
        $display("          sends 0x77, waits for reply, verifies reply=0xBB");
        $display("  Core 1: receives 0x77, verifies it, computes 0xBB reply");
        $display("          sends 0xBB back, writes PASS");
        $display("  Both router directions exercised. C0 PASS blocked on C1.");
        $display("---------------------------------------------");
        $display("");

        reset = 1;
        repeat (300) @(posedge clk);
        reset = 0;

        $display("[Cycle 0] Reset de-asserted - both cores running");
        $display("  Core 0: sender/verifier (test9_core0.hex)");
        $display("  Core 1: receiver/replier (test9_core1.hex)");
        $display("");
    end

endmodule
