`include "riscv_pkg.sv"

module core_dummy_wrapper #(
    parameter string HEX_PROG = "test_mailbox.mem"
)(
    output logic DONE_GPIO_LED_0,
    output logic RESET_DEBUG_LED,
    input  logic clk12,
    input  logic btn_reset_n
);

    //------------------------------------------
    // Clock / reset signals
    //------------------------------------------

    logic clkout0;
    logic async_reset;
    logic sync_reset;
    
    logic [23:0] reset_flash_counter;
    logic reset_flash_active;
    //------------------------------------------
    // BRISKI interface
    //------------------------------------------

    logic [31:0] rom_data;
    logic [9:0]  rom_addr;

    logic [13:0] RVcore_addr;
    logic [31:0] RVcore_wr_data;
    logic [3:0]  RVcore_wr_en;
    logic [31:0] RVcore_rd_data;

    //------------------------------------------
    // Normal BRAM
    //------------------------------------------

    logic [9:0]  BRAM_addr;
    logic [31:0] BRAM_wr_data;
    logic [3:0]  BRAM_wr_en;
    logic [31:0] BRAM_rd_data;

    //------------------------------------------
    // Mailbox bus
    //------------------------------------------

    logic        mb_bus_valid;
    logic        mb_bus_we;
    logic [7:0]  mb_bus_addr;
    logic [31:0] mb_bus_wdata;
    logic [31:0] mb_bus_rdata;
    logic        mb_bus_ready;

    //------------------------------------------
    // Mailbox control / network-side stub signals
    //------------------------------------------

    logic        irq_rx;

    logic        txq_deq;
    logic [19:0] txq_deq_data;
    logic        txq_deq_valid;
    logic        txq_deq_ready;

    logic        rx_in_valid;
    logic [15:0] rx_in_data;
    logic        rx_in_ready;

    logic        tx_done_valid;
    logic [7:0]  tx_done_slot;

    logic        net_sp_we;
    logic [7:0]  net_sp_waddr;
    logic [31:0] net_sp_wdata;
    logic        net_sp_re;
    logic [7:0]  net_sp_raddr;
    logic [31:0] net_sp_rdata;
    logic        net_sp_rvalid;
    

    //------------------------------------------
    // Address decode
    //------------------------------------------
    
    logic led_sel;

    assign led_sel = (RVcore_addr == 14'h03FF);
    
    // Mailbox occupies word addresses 0x3F0..0x3FF
    localparam logic [13:0] MB_BASE = 14'h03F0;

    logic mb_sel;

    assign mb_sel       = (RVcore_addr[13:4] == MB_BASE[13:4]);
    assign mb_bus_valid = mb_sel;
    assign mb_bus_we    = mb_sel && (RVcore_wr_en != 4'b0000);
    assign mb_bus_addr  = {RVcore_addr[3:0], 2'b00};  // word address -> byte offset
    assign mb_bus_wdata = RVcore_wr_data;

    //------------------------------------------
    // Normal BRAM access
    //------------------------------------------

    assign BRAM_addr    = RVcore_addr[9:0];
    assign BRAM_wr_data = RVcore_wr_data;
    //assign BRAM_wr_en   = mb_sel ? 4'b0000 : RVcore_wr_en;
    assign BRAM_wr_en  = (mb_sel || led_sel) ? 4'b0000 : RVcore_wr_en;

    //------------------------------------------
    // Read mux
    //------------------------------------------

    assign RVcore_rd_data = mb_sel ? mb_bus_rdata : BRAM_rd_data;

    //------------------------------------------
    // Clock / reset
    //------------------------------------------

    assign clkout0     = clk12;
    assign async_reset = btn_reset_n;

    async_reset_synchronizer sync_reset_gen_inst (
        .clk        (clkout0),
        .async_reset(async_reset),
        .sync_reset (sync_reset)
    );
    
    
    always_ff @(posedge clk12) begin
        if (btn_reset_n) begin
            reset_flash_counter <= 24'd2000000;
        end else if (reset_flash_counter != 0) begin
            reset_flash_counter <= reset_flash_counter - 1;
        end
    end
    
    assign reset_flash_active = (reset_flash_counter != 0);
    
    assign RESET_DEBUG_LED = reset_flash_active;
    
    //------------------------------------------
    // RISC-V core
    //------------------------------------------

    RISCV_core #(
        .IDcluster(0),
        .IDrow(0),
        .IDminirow(0),
        .IDposx(0)
    ) RISCV_core_inst (
        .clk                (clkout0),
        .reset              (sync_reset),
        .i_ROM_instruction  (rom_data),
        .o_ROM_addr         (rom_addr),

        .o_dmem_addr        (RVcore_addr),
        .o_dmem_write_data  (RVcore_wr_data),
        .o_dmem_write_enable(RVcore_wr_en),
        .i_dmem_read_data   (RVcore_rd_data),

        .debug_regfile_wr_addr(),
        .debug_regfile_wr_data(),
        .debug_regfile_wr_en(),
        .debug_thread_index_wb(),
        .debug_thread_index_wrmem(),
        .debug_instr_at_wb()
    );

    //------------------------------------------
    // BRAM
    //------------------------------------------

    BRAM #(
        .SIZE      (SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COL_WIDTH (COL_WIDTH),
        .NB_COL    (NB_COL),
        .INIT_FILE (HEX_PROG)
    ) instr_and_data_mem (
        .clka (clkout0),
        .ena  (1'b1),
        .wea  (BRAM_wr_en),
        .addra(BRAM_addr),
        .dia  (BRAM_wr_data),
        .doa  (BRAM_rd_data),

        .clkb (clkout0),
        .enb  (1'b1),
        .web  (4'b0000),
        .addrb(rom_addr),
        .dib  (32'b0),
        .dob  (rom_data)
    );

    //------------------------------------------
    // Network-side stubs (disabled for now)
    //------------------------------------------
    
    logic [3:0] loop_dest;
    logic [7:0] loop_len;
    logic [7:0] loop_slot;
    
    assign {loop_dest, loop_len, loop_slot} = txq_deq_data;

    assign txq_deq     = txq_deq_valid && rx_in_ready;
    assign rx_in_valid = txq_deq_valid && rx_in_ready;
    assign rx_in_data  = {loop_len, loop_slot};
    assign tx_done_valid = 1'b0;
    assign tx_done_slot  = 8'b0;

    assign net_sp_we     = 1'b0;
    assign net_sp_waddr  = 8'b0;
    assign net_sp_wdata  = 32'b0;
    assign net_sp_re     = 1'b0;
    assign net_sp_raddr  = 8'b0;

    //------------------------------------------
    // Mailbox instance
    //------------------------------------------

    mailbox_controller u_mb (
        .clk         (clkout0),
        .rst         (sync_reset),

        .bus_valid   (mb_bus_valid),
        .bus_we      (mb_bus_we),
        .bus_addr    (mb_bus_addr),
        .bus_wdata   (mb_bus_wdata),
        .bus_rdata   (mb_bus_rdata),
        .bus_ready   (mb_bus_ready),

        .irq_rx      (irq_rx),

        .txq_deq     (txq_deq),
        .txq_deq_data(txq_deq_data),
        .txq_deq_valid(txq_deq_valid),
        .txq_deq_ready(txq_deq_ready),

        .rx_in_valid (rx_in_valid),
        .rx_in_data  (rx_in_data),
        .rx_in_ready (rx_in_ready),

        .tx_done_valid(tx_done_valid),
        .tx_done_slot (tx_done_slot),

        .net_sp_raddr(net_sp_raddr),
        .net_sp_re   (net_sp_re),
        .net_sp_waddr(net_sp_waddr),
        .net_sp_wdata(net_sp_wdata),
        .net_sp_we   (net_sp_we),
        .net_sp_rdata(net_sp_rdata),
        .net_sp_rvalid(net_sp_rvalid)
    );

    //------------------------------------------
    // LED debug
    //------------------------------------------
    
    logic led_reg;
    assign DONE_GPIO_LED_0 = led_reg;
    always_ff @(posedge clkout0) begin
        if (sync_reset)
            led_reg <= 1'b0;
        else if (led_sel && (RVcore_wr_en != 4'b0000))
            led_reg <= RVcore_wr_data[0];
    end

endmodule