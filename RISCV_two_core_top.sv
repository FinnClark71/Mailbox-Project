// RISCV_two_core_top.sv
// Connects 2 independent BRISKI cores with a small inter_core_router.
// Each core has its own mailbox controller and instruction BRAM.
// The router automatically forwards TX descriptors between cores.

// Memory map (same for both cores):
//   0x0000-0x0FFF  BRAM (local instruction + data memory, 1024 words)
//   0x1000-0x1FFF  URAM (not connected in this config)
//   0x8000-0x803F  MMIO (mailbox registers, byte addresses)


`include "riscv_pkg.sv"

module RISCV_two_core_top #(
    // Core 0 runs the sender program
    parameter string CORE0_HEX = "C:/briski_files/test8_core0_sender.hex",
    // Core 1 runs the receiver program
    parameter string CORE1_HEX = "C:/briski_files/test8_core1_receiver.hex"
)(
    input  logic clk,
    input  logic reset,
    output logic o_c0_irq_rx,
    output logic o_c1_irq_rx,
    output logic o_c0_txq_ready,
    output logic o_c1_txq_ready
);

    //  Core 0 mailbox network ports ----------------------------------------
    logic        c0_txq_deq,   c0_txq_deq_valid, c0_txq_deq_ready;
    logic [19:0] c0_txq_deq_data;
    logic        c0_rx_in_valid, c0_rx_in_ready;
    logic [15:0] c0_rx_in_data;
    logic        c0_irq_rx;

    //  Core 1 mailbox network ports -----------------------------------
    logic        c1_txq_deq,   c1_txq_deq_valid, c1_txq_deq_ready;
    logic [19:0] c1_txq_deq_data;
    logic        c1_rx_in_valid, c1_rx_in_ready;
    logic [15:0] c1_rx_in_data;
    logic        c1_irq_rx;

    //  Core 0 (sender) ---------------------------------------------
    RISCV_core_top #(
        .BRAM_DATA_INSTR_FILE(CORE0_HEX),
        .IDcluster(0), .IDrow(0), .IDminirow(0), .IDposx(0)
    ) core0 (
        .clk              (clk),
        .reset            (reset),
        .o_URAM_en        (),
        .o_URAM_addr      (),
        .o_URAM_wr_data   (),
        .o_URAM_wr_en     (),
        .i_txq_deq        (c0_txq_deq),
        .o_txq_deq_data   (c0_txq_deq_data),
        .o_txq_deq_valid  (c0_txq_deq_valid),
        .o_txq_deq_ready  (c0_txq_deq_ready),
        .i_rx_in_valid    (c0_rx_in_valid),
        .i_rx_in_data     (c0_rx_in_data),
        .o_rx_in_ready    (c0_rx_in_ready),
        .i_tx_done_valid  (1'b0),
        .i_tx_done_slot   (8'b0),
        .o_irq_rx         (c0_irq_rx)
    );

    //  Core 1 (receiver) ----------------------------------------------------
    RISCV_core_top #(
        .BRAM_DATA_INSTR_FILE(CORE1_HEX),
        .IDcluster(0), .IDrow(0), .IDminirow(0), .IDposx(1)
    ) core1 (
        .clk              (clk),
        .reset            (reset),
        .o_URAM_en        (),
        .o_URAM_addr      (),
        .o_URAM_wr_data   (),
        .o_URAM_wr_en     (),
        .i_txq_deq        (c1_txq_deq),
        .o_txq_deq_data   (c1_txq_deq_data),
        .o_txq_deq_valid  (c1_txq_deq_valid),
        .o_txq_deq_ready  (c1_txq_deq_ready),
        .i_rx_in_valid    (c1_rx_in_valid),
        .i_rx_in_data     (c1_rx_in_data),
        .o_rx_in_ready    (c1_rx_in_ready),
        .i_tx_done_valid  (1'b0),
        .i_tx_done_slot   (8'b0),
        .o_irq_rx         (c1_irq_rx)
    );

    //  Inter-core router ---------------------------------------------------------
    // Routes Core 0 TX -> Core 1 RX and Core 1 TX -> Core 0 RX automatically.
    inter_core_router router (
        .clk              (clk),
        .rst              (reset),
        // Core 0 -> Core 1
        .c0_txq_deq       (c0_txq_deq),
        .c0_txq_deq_data  (c0_txq_deq_data),
        .c0_txq_deq_valid (c0_txq_deq_valid),
        .c0_txq_deq_ready (c0_txq_deq_ready),
        .c1_rx_in_valid   (c1_rx_in_valid),
        .c1_rx_in_data    (c1_rx_in_data),
        .c1_rx_in_ready   (c1_rx_in_ready),
        // Core 1 -> Core 0
        .c1_txq_deq       (c1_txq_deq),
        .c1_txq_deq_data  (c1_txq_deq_data),
        .c1_txq_deq_valid (c1_txq_deq_valid),
        .c1_txq_deq_ready (c1_txq_deq_ready),
        .c0_rx_in_valid   (c0_rx_in_valid),
        .c0_rx_in_data    (c0_rx_in_data),
        .c0_rx_in_ready   (c0_rx_in_ready)
    );
    
    assign o_c0_irq_rx    = c0_irq_rx;
    assign o_c1_irq_rx    = c1_irq_rx;
    assign o_c0_txq_ready = c0_txq_deq_ready;
    assign o_c1_txq_ready = c1_txq_deq_ready;

endmodule
