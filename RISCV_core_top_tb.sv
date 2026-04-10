// BRISKI Core Standalone Simulation Testbench -- v3



// Getting the .hex file to load:
//   change BRAM_DATA_INSTR_FILE in top file to name of hex test e.g. test1


`timescale 1ns / 1ps

module RISCV_core_top_tb;

   
    // Parameters
    parameter CLK_PERIOD     = 10;  // 100 MHz

    // With 16 threads x 16 pipeline stages, instructions take long time
    // to retire, 50000 cycles gives each thread ~3000 instruction slots.
    parameter TIMEOUT_CYCLES = 100000;

    // Pass/fail :
    // Test programs store to BRAM word address 0xFF (byte addr 0x3FC)
    //   0x00000001 = PASS
    //   0xDEADBEEF = FAIL
    parameter [13:0] PASS_ADDR = 14'h00FF;
    parameter [31:0] PASS_DATA = 32'h0000_0001;
    parameter [31:0] FAIL_DATA = 32'hDEAD_BEEF;

  
    // Clock and Reset
  
    logic clk;
    logic reset;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;


    // DUT signals
    logic        o_URAM_en;
    logic [11:0] o_URAM_addr;
    logic [31:0] o_URAM_wr_data;
    logic        o_URAM_wr_en;
    logic        i_uram_emptied;
    logic        o_core_req;
    logic        o_core_locked;
    logic        i_core_grant;

    //  tie offs
    assign i_core_grant   = 1'b1;   // Always granted (no arbiter)
    assign i_uram_emptied = 1'b0;   // No external URAM event

    // DUT Instantiation
    RISCV_core_top dut (
        .clk            (clk),
        .reset          (reset),
        .o_URAM_en      (o_URAM_en),
        .o_URAM_addr    (o_URAM_addr),
        .o_URAM_wr_data (o_URAM_wr_data),
        .o_URAM_wr_en   (o_URAM_wr_en),
        .i_uram_emptied (i_uram_emptied),
        .o_core_req     (o_core_req),
        .o_core_locked  (o_core_locked),
        .i_core_grant   (i_core_grant)
    );


    // Internal debug signals 
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
                $display("------------------------------------------------");
                $display(" BRAM appears EMPTY (all zero fetches)");
                $display("------------------------------------------------");
                $display("");
            end else begin
                $display("");
                $display("  -- BRAM loaded OK ");
                $display("");
            end
        end
    end


    // Monitor: instruction fetches (first 10 cycles, for startup diagnosis)
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


    // Monitor: data memory writes (BRAM region only)
    always @(posedge clk) begin
        if (!reset && (|dbg_dmem_wr_en) && dbg_dmem_addr[13:12] == 2'b00) begin
            $display("[Cycle %0d] MEM WRITE: addr=0x%04h data=0x%08h we=0b%04b",
                     cycle_count, dbg_dmem_addr, dbg_dmem_wr_data, dbg_dmem_wr_en);
        end
    end


    // Self checking: detect pass/fail signature
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
                $display("------------------------------------------");
                $display("  TEST PASSED at cycle %0d", cycle_count);
                $display("------------------------------------------");
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
            $display("  TIMEOUT after %0d cycles - no pass/fail detected", TIMEOUT_CYCLES);
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


    // Waveform dump (for GTKWave)
    initial begin
        $dumpfile("briski_tb.vcd");
        $dumpvars(0, RISCV_core_top_tb);
    end

    // Reset sequence
    initial begin
        $display("");
        $display("--------------------------------------------");
        $display("  BRISKI Core Testbench v3");
        $display("--------------------------------------------");
        $display("");

        reset = 1;
        // Hold reset long enough for 16-thread/16-stage config
        repeat (300) @(posedge clk);
        reset = 0;
        $display("[Cycle 0] Reset de-asserted - core is running");
        $display("");
    end

endmodule
