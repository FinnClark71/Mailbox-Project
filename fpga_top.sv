`timescale 1ns/1ps

module fpga_top (
    input  logic        clk12,
    input  logic        btn_reset_n,
    output logic [3:0]  led
);

    //logic rst;
    //assign rst = ~btn_reset_n; // active-high internal reset
    
    logic [1:0] rst_sync;
    always_ff @(posedge clk12) begin
        rst_sync <= {rst_sync[0], ~btn_reset_n}; // invert: button active low -> rst active high
    end
    logic rst;
    assign rst = rst_sync[1];

    
    // Tie-offs
    logic                   bus_valid, bus_we;
    logic [7:0]             bus_addr;
    logic [31:0]            bus_wdata, bus_rdata;
    logic                   bus_ready, irq_rx;

    logic                   txq_deq;
    logic [19:0]            txq_deq_data;
    logic                   txq_deq_valid, txq_deq_ready;

    logic                   rx_in_valid;
    logic [15:0]            rx_in_data;
    logic                   rx_in_ready;

    logic                   tx_done_valid;
    logic [7:0]             tx_done_slot;

    logic                   net_sp_we, net_sp_re;
    logic [7:0]             net_sp_waddr, net_sp_raddr;
    logic [31:0]            net_sp_wdata, net_sp_rdata;
    logic                   net_sp_rvalid;

    assign bus_valid     = 1'b0;
    assign bus_we        = 1'b0;
    assign bus_addr      = 8'h00;
    assign bus_wdata     = 32'h0;

    assign txq_deq       = 1'b0;
    assign rx_in_valid   = 1'b0;
    assign rx_in_data    = 16'h0;
    assign tx_done_valid = 1'b0;
    assign tx_done_slot  = 8'h0;

    assign net_sp_we     = 1'b0;
    assign net_sp_waddr  = 8'h0;
    assign net_sp_wdata  = 32'h0;
    assign net_sp_re     = 1'b0;
    assign net_sp_raddr  = 8'h0;
    
    
    mailbox_controller u_mb (
        .clk(clk12),
        .rst(rst),

        .bus_valid(bus_valid),
        .bus_we(bus_we),
        .bus_addr(bus_addr),
        .bus_wdata(bus_wdata),
        .bus_rdata(bus_rdata),
        .bus_ready(bus_ready),

        .irq_rx(irq_rx),

        .txq_deq(txq_deq),
        .txq_deq_data(txq_deq_data),
        .txq_deq_valid(txq_deq_valid),
        .txq_deq_ready(txq_deq_ready),

        .rx_in_valid(rx_in_valid),
        .rx_in_data(rx_in_data),
        .rx_in_ready(rx_in_ready),

        .tx_done_valid(tx_done_valid),
        .tx_done_slot(tx_done_slot),

        .net_sp_we(net_sp_we),
        .net_sp_waddr(net_sp_waddr),
        .net_sp_wdata(net_sp_wdata),
        .net_sp_re(net_sp_re),
        .net_sp_raddr(net_sp_raddr),
        .net_sp_rdata(net_sp_rdata),
        .net_sp_rvalid(net_sp_rvalid)
    );

    // Basic “alive” visibility
    always_comb begin
        led[0] = irq_rx;
        led[1] = txq_deq_valid;
        led[2] = net_sp_rvalid;
        led[3] = bus_ready;
    end

endmodule