// RX Queue (Synchronous FIFO)
//  Stores message descriptors for a receiver (thread/core)
//  push_enq: mailbox pushes a descriptor when a message arrives
//  pop_deq: core pops a descriptor when it wants to receive
//  Synchronous outputs: pop_valid/data asserted in-cycle after pop request


module rx_queue #(
    parameter int SLOT_W = 8,
    parameter int LEN_W  = 8,
    parameter int DEPTH  = 16,
    localparam int DATA_W = SLOT_W + LEN_W,
    localparam int ADDR_W = $clog2(DEPTH)
	

)(
    input  logic                 clk,
    input  logic                 rst,

    // queue (message arrival)
    input  logic                 enq,
    input  logic [DATA_W-1:0]    enq_data,
    output logic                 enq_ready,   // 1 when not full

    // Dequeue (receiver consumes)
    input  logic                 deq,
    output logic [DATA_W-1:0]    deq_data,
    output logic                 deq_valid,   // 1 for one cycle when output is valid
    output logic                 deq_ready,   // 1 when not empty

    // Status
    output logic                 full,
    output logic                 empty
);

    //logic [DATA_W-1:0] mem [0:DEPTH-1];
	logic [DEPTH-1:0][DATA_W-1:0] mem;
    logic [ADDR_W-1:0] rd_ptr, wr_ptr;
    logic [ADDR_W:0]   count;

    // Registered dequeue outputs (sync clean)
    logic [DATA_W-1:0] deq_data_q;
    logic              deq_valid_q;

    assign deq_data  = deq_data_q;
    assign deq_valid = deq_valid_q;

	assign full  = (count == (ADDR_W+1)'(DEPTH));
	assign empty = (count == '0);



    assign enq_ready = !full;
    assign deq_ready = !empty;
	
	logic do_enq, do_deq; //new
    assign do_enq = enq && !full;
    assign do_deq = deq && !empty;


    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr       <= '0;
            wr_ptr       <= '0;
            count        <= '0;
            deq_valid_q  <= 1'b0;
            deq_data_q   <= '0;
        end else begin
			/*
            // default: no dequeue output unless deq
            deq_valid_q <= 1'b0;

            // Queue
            if (enq && !full) begin
                mem[wr_ptr] <= enq_data;
                wr_ptr <= wr_ptr + 1'b1;
                count  <= count + 1'b1;
            end

            // Dequeue
            if (deq && !empty) begin
                deq_data_q  <= mem[rd_ptr];
                deq_valid_q <= 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
                count  <= count - 1'b1;
            end
			*/
			// default: no dequeue output unless we actually dequeue
            deq_valid_q <= 1'b0;

            unique case ({do_enq, do_deq})
                2'b10: begin
                    // ENQ only
                    mem[wr_ptr] <= enq_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    count       <= count + 1'b1;
                end

                2'b01: begin
                    // DEQ only
                    deq_data_q  <= mem[rd_ptr];
                    deq_valid_q <= 1'b1;
                    rd_ptr      <= rd_ptr + 1'b1;
                    count       <= count - 1'b1;
                end

                2'b11: begin
                    // ENQ + DEQ same cycle (safe)
                    mem[wr_ptr] <= enq_data;
                    wr_ptr      <= wr_ptr + 1'b1;

                    deq_data_q  <= mem[rd_ptr];
                    deq_valid_q <= 1'b1;
                    rd_ptr      <= rd_ptr + 1'b1;

                    // count unchanged
                    count       <= count;
                end

                default: begin
                    // no-op
                    count <= count;
                end
            endcase
			
        end
    end

endmodule
