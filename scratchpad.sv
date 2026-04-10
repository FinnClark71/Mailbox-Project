// Dual-Port Scratchpad RAM
//  One read port
//  One write port
//  Synchronous read (data valid 1 cycle after read)



module scratchpad #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,                 // depth = 2^ADDR_WIDTH
    localparam DEPTH = (1 << ADDR_WIDTH)
)(
    input  logic                   clk,
    input  logic                   rst,

    //Write port
    input  logic                   we,
    input  logic [ADDR_WIDTH-1:0]  waddr,
    input  logic [DATA_WIDTH-1:0]  wdata,

    // Read port
    input  logic                   re,
    input  logic [ADDR_WIDTH-1:0]  raddr,
    output logic [DATA_WIDTH-1:0]  rdata,
    output logic                   rvalid
);

    // Internal memory
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Output pipeline register
    logic [DATA_WIDTH-1:0] rdata_q;
    logic                  rvalid_q;

    assign rdata  = rdata_q;
    assign rvalid = rvalid_q;

    // Write and Read Logic
    always_ff @(posedge clk) begin
        if (rst) begin
            rvalid_q <= 0;
            rdata_q  <= '0;   // fix the clear on reset
        end else begin

            // Write
            if (we)
                mem[waddr] <= wdata;

            // Read
            if (re) begin
                rdata_q <= mem[raddr];
                rvalid_q <= 1;
            end else begin
                rvalid_q <= 0;
            end

        end
    end

endmodule
 
