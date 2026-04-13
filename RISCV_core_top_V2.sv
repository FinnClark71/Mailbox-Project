`include "riscv_pkg.sv"
//import riscv_pkg::*;
module RISCV_core_top #(
    //main parameters
    parameter        NUM_PIPE_STAGES               = `NUM_PIPE_STAGES,
    parameter        NUM_THREADS                   = `NUM_THREADS,
    // RF parameter 
    parameter bool   ENABLE_BRAM_REGFILE           = `ENABLE_BRAM_REGFILE,
    // ALU parameter 
    parameter bool   ENABLE_ALU_DSP                = `ENABLE_ALU_DSP,
    parameter bool   ENABLE_UNIFIED_BARREL_SHIFTER = `ENABLE_UNIFIED_BARREL_SHIFTER,
    //parameter string BRAM_DATA_INSTR_FILE = `HEX_PROG,
    parameter string BRAM_DATA_INSTR_FILE          = "C:/briski_files/test5_mailbox.hex",
    // Generic parameters
    parameter int    IDcluster                     = 0,
    parameter int    IDrow                         = 0,
    parameter int    IDminirow                     = 0,
    parameter int    IDposx                        = 0
) (
    input  logic        clk,
    input  logic        reset,
    // URAM interface
    output logic        o_URAM_en,
    output logic [11:0] o_URAM_addr,
    output logic [31:0] o_URAM_wr_data,
    output logic        o_URAM_wr_en,
    // Mailbox network interface (replaces old row-sync arbiter/barrier signals)
    input  logic        i_txq_deq,
    output logic [19:0] o_txq_deq_data,
    output logic        o_txq_deq_valid,
    output logic        o_txq_deq_ready,
    input  logic        i_rx_in_valid,
    input  logic [15:0] i_rx_in_data,
    output logic        o_rx_in_ready,
    input  logic        i_tx_done_valid,
    input  logic [7:0]  i_tx_done_slot,
    output logic        o_irq_rx
);
    // Attribute to keep hierarchy
    (* keep_hierarchy = "true" *)

    // Instruction mem signals
    logic [31:0] rom_data;
    logic [ 9:0] rom_addr;

    // Mem signals
    logic [13:0] RVcore_addr;
    logic [31:0] RVcore_wr_data;
    logic [ 3:0] RVcore_wr_en;  // One bit per byte in word
    logic [31:0] RVcore_rd_data;

    logic [ 9:0] BRAM_addr;  // 10 bit to address 1024 32-bit locations in the entire BRAM
    logic [31:0] BRAM_wr_data;
    logic [ 3:0] BRAM_wr_en;  // One bit per byte in word
    logic [31:0] BRAM_rd_data;

    //  MMIO (mailbox) ----------------------------------------------------------------------- 
    // RVcore_addr is a WORD address. The mailbox uses BYTE offsets.
    // Conversion: byte_offset = word_offset * 4 = {word[5:0], 2'b00}
    // Programmer uses byte base 0x8000 (LUI x1,8); core converts to
    // word addr 0x2000 (addr[13:12]=2'b10 → MMIO region).
    // addr width widened from 4-bit (16 regs) to 8-bit to cover all mailbox registers
    logic [ 7:0] MMIO_addr;
    logic [31:0] MMIO_wr_data;
    logic        MMIO_wr_en;
    logic [31:0] MMIO_rd_data;
    // Registered one cycle to match BRAM synchronous read latency.
    // The mux_sel from memory_map_decoder is also registered (1-cycle),
    // so both arrive at the mux in the same cycle. Without this register
    // the combinational bus_rdata would be gone by the time mux_sel arrives.
    logic [31:0] MMIO_rd_data_reg;

    // Memory enable control signals
    logic BRAM_EN, URAM_EN, MMIO_EN;

    // Mux read back:
    logic [1:0] readmem_mux_sel;

    logic [                    4:0] DEBUG_regfile_wr_addr;
    logic [                   31:0] DEBUG_regfile_wr_data;
    logic                           DEBUG_regfile_wr_en;
    logic [$clog2(NUM_THREADS)-1:0] DEBUG_thread_index_wb;
    logic [$clog2(NUM_THREADS)-1:0] DEBUG_thread_index_wrmem;

    // Signal assignments-------------------------------------------------------------

    //BRAM interface
    assign BRAM_addr    = RVcore_addr[9:0];
    assign BRAM_wr_data = RVcore_wr_data;
    assign BRAM_wr_en   = RVcore_wr_en;

    //URAM interface - grant gating removed; arbitration now handled externally by the network
    assign o_URAM_addr    = RVcore_addr[11:0];
    assign o_URAM_wr_data = RVcore_wr_data;
    assign o_URAM_wr_en   = (&RVcore_wr_en) & URAM_EN;  //only write word is supported (1bit we, and-reduce original we)
    assign o_URAM_en      = URAM_EN;

    //MMIO interface
    assign MMIO_addr    = {RVcore_addr[5:0], 2'b00};  // word->byte offset conversion
    assign MMIO_wr_data = RVcore_wr_data;
    assign MMIO_wr_en   = (&RVcore_wr_en) & MMIO_EN;  //uses only write word but stores a chunk of the word

    // Register MMIO read data by one cycle to match BRAM synchronous read latency
    always_ff @(posedge clk)
        MMIO_rd_data_reg <= MMIO_rd_data;

    //=====================================================================================--
    //multiplexing the read data
    //=====================================================================================--
    mux3to1 mem_read_data_mux_inst (
        .i_sel   (readmem_mux_sel),
        .i_in0   (BRAM_rd_data),
        .i_in1   (32'b0),
        .i_in2   (MMIO_rd_data_reg),  // now registered to align with mux_sel latency
        .o_muxout(RVcore_rd_data)
    );

    //=====================================================================================--
    // memory map decoder that activate either BRAM (local mem), URAM (shared mem)
    // or MMIO mem (used for synchronization between cores)
    //=====================================================================================--
    memory_map_decoder memory_map_decoder_inst (
        .clk                (clk),
        .reset              (reset),
        .i_address_lines    (RVcore_addr[13:12]),
        .o_dmem_enable      (BRAM_EN),
        .o_shared_mem_enable(URAM_EN),
        .o_MMIO_enable      (MMIO_EN),
        .o_readmem_mux_sel  (readmem_mux_sel)
    );


    //================================================================================================================--
    // the RISC-V core
    //================================================================================================================--
    RISCV_core #(
        .IDcluster(IDcluster), .IDrow(IDrow),
        .IDminirow(IDminirow), .IDposx(IDposx)
    ) RISCV_core_inst (
        .clk                      (clk),
        .reset                    (reset),
        .i_ROM_instruction        (rom_data),
        .o_ROM_addr               (rom_addr),
        .o_dmem_addr              (RVcore_addr),
        .o_dmem_write_data        (RVcore_wr_data),
        .o_dmem_write_enable      (RVcore_wr_en),
        .i_dmem_read_data         (RVcore_rd_data),
        //DEBUG outputs
        .debug_regfile_wr_addr    (DEBUG_regfile_wr_addr),
        .debug_regfile_wr_data    (DEBUG_regfile_wr_data),
        .debug_regfile_wr_en      (DEBUG_regfile_wr_en),
        .debug_thread_index_wb    (DEBUG_thread_index_wb),
        .debug_thread_index_wrmem (DEBUG_thread_index_wrmem),
        .debug_instr_at_wb        ()
    );

    //================================================================================================================--
    //instr_and_data_mem : entity work.BRAM  generic map (SIZE => 1024, ADDR_WIDTH => 10, COL_WIDTH => 8, NB_COL => 4)
    //===============================================================================================================--
    BRAM #(
        .SIZE(SIZE), .ADDR_WIDTH(ADDR_WIDTH),
        .COL_WIDTH(COL_WIDTH), .NB_COL(NB_COL),
        //.INIT_FILE(HEX_PROG)
        .INIT_FILE(BRAM_DATA_INSTR_FILE)
    ) instr_and_data_mem (
        //--------------------------
        //port a (data part)
        //--------------------------
        .clka(clk), .ena(BRAM_EN), .wea(BRAM_wr_en),
        .addra(BRAM_addr), .dia(BRAM_wr_data), .doa(BRAM_rd_data),
        //------------------------
        //port b (instruction ROM)
        //------------------------
        .clkb(clk), .enb(1'b1), .web(4'b0),
        .addrb(rom_addr), .dib('0), .dob(rom_data)
    );

    //=====================================================================================--
    // Mailbox controller - replaces memory_mapped_interface
    // Provides inter-core messaging via TX/RX queues instead of simple barrier/arbiter sync.
    // MMIO byte addresses (use LUI x1,8 then SW/LW with these offsets):
    //   0x8000 STATUS   [R]  bit0=tx_ready, bit1=rx_has_msg, bit2=init_done
    //   0x8004 TX_DEST  [RW] destination id
    //   0x8008 TX_LEN   [RW] length metadata
    //   0x800C TX_SEND  [W]  write 1 to send; [R] last slot
    //   0x8010 RX_POP   [W]  write 1 to pop;  [R] last {len,slot}
    //   0x8014 REL_SLOT [W]  write slot to release
    //   0x8018 SP_WADDR / 0x801C SP_WDATA / 0x8020 SP_WE
    //   0x8024 SP_RADDR / 0x8028 SP_RE / 0x802C SP_RDATA / 0x8030 SP_RVALID
    //=====================================================================================--
    mailbox_controller #(
        .DATA_WIDTH(32), .ADDR_WIDTH(8),
        .DEST_W(4), .LEN_W(8), .SLOT_W(8),
        .TXQ_DEPTH(16), .RXQ_DEPTH(16), .COUNT_W(4)
    ) u_mailbox (
        .clk(clk), .rst(reset),
        .bus_valid    (MMIO_EN),
        .bus_we       (MMIO_wr_en),
        .bus_addr     (MMIO_addr),
        .bus_wdata    (MMIO_wr_data),
        .bus_rdata    (MMIO_rd_data),
        .bus_ready    (),
        .irq_rx       (o_irq_rx),
        .txq_deq      (i_txq_deq),
        .txq_deq_data (o_txq_deq_data),
        .txq_deq_valid(o_txq_deq_valid),
        .txq_deq_ready(o_txq_deq_ready),
        .rx_in_valid  (i_rx_in_valid),
        .rx_in_data   (i_rx_in_data),
        .rx_in_ready  (o_rx_in_ready),
        .tx_done_valid(i_tx_done_valid),
        .tx_done_slot (i_tx_done_slot),
        .net_sp_we    (1'b0), .net_sp_waddr('0), .net_sp_wdata('0),
        .net_sp_re    (1'b0), .net_sp_raddr('0),
        .net_sp_rdata(), .net_sp_rvalid()
    );

endmodule
