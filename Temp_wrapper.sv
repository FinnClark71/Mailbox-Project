module Temp_wrapper (
    input  logic clk,    // 12 MHz board oscillator
    input  logic resetn, // BTN0 (active low on Arty S7)
    output logic [3:0] led
);
    logic reset;
    assign reset = ~resetn;  // BRISKI uses active-high reset

    // Tie off unused manycore ports
    logic o_URAM_en, o_core_req, o_core_locked;
    logic [11:0] o_URAM_addr;
    logic [31:0] o_URAM_wr_data;
    logic        o_URAM_wr_en;

    RISCV_core_top #(
        .BRAM_DATA_INSTR_FILE("none")  // or point to your .hex
    ) u_core (
        .clk           (clk),
        .reset         (reset),
        .o_URAM_en     (o_URAM_en),
        .o_URAM_addr   (o_URAM_addr),
        .o_URAM_wr_data(o_URAM_wr_data),
        .o_URAM_wr_en  (o_URAM_wr_en),
        .i_uram_emptied(1'b1),   // unused — tie high
        .o_core_req    (o_core_req),
        .o_core_locked (o_core_locked),
        .i_core_grant  (1'b1)    // single core — always granted
    );

    // Blink an LED to prove it's running (optional but useful)
    logic [23:0] ctr;
    always_ff @(posedge clk) begin
        if (reset) ctr <= 0;
        else ctr <= ctr + 1;
    end
    assign led = ctr[23:20];

endmodule