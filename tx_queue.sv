
// tx Queue (Synchronous FIFO)
//  Stores outgoing message descriptors for transmit logic
//  Clean synchronous outputs: deq_valid/data asserted on cycle after deq

module tx_queue #(
    parameter int DEST_W = 4,     // supports up to 16 threads
    parameter int SLOT_W = 8,
    parameter int LEN_W  = 8,
    parameter int DEPTH  = 16,
    localparam int DATA_W = DEST_W + SLOT_W + LEN_W,
    localparam int ADDR_W = $clog2(DEPTH)
)(
    input  logic               clk,
    input  logic               rst,

    // Enqueue (core/mailbox pushes an outgoing message)
    input  logic               enq,
    input  logic [DATA_W-1:0]  enq_data,
    output logic               enq_ready,

    // Dequeue (transmit unit pops next outgoing message)
    input  logic               deq,
    output logic [DATA_W-1:0]  deq_data,
    output logic               deq_valid,
    output logic               deq_ready,

    output logic               full,
    output logic               empty
);

    //logic [DATA_W-1:0] mem [0:DEPTH-1];
	logic [DEPTH-1:0][DATA_W-1:0] mem;
    logic [ADDR_W-1:0] rd_ptr, wr_ptr;
    logic [ADDR_W:0]   count;

    logic [DATA_W-1:0] deq_data_q;
    logic              deq_valid_q;

    assign deq_data  = deq_data_q;
    assign deq_valid = deq_valid_q;

    assign full  = (count == (ADDR_W+1)'(DEPTH));
    assign empty = (count == '0);

    assign enq_ready = !full;
    assign deq_ready = !empty;
	
	logic do_enq, do_deq;
    assign do_enq = enq && !full;
    assign do_deq = deq && !empty;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr      <= '0;
            wr_ptr      <= '0;
            count       <= '0;
            deq_valid_q <= 1'b0;
            deq_data_q  <= '0;
			
		/*
        end else begin
            deq_valid_q <= 1'b0;

            if (enq && !full) begin
                mem[wr_ptr] <= enq_data;
                wr_ptr <= wr_ptr + 1'b1;
                count  <= count + 1'b1;
            end

            if (deq && !empty) begin
                deq_data_q  <= mem[rd_ptr];
                deq_valid_q <= 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
                count  <= count - 1'b1;
            end
        end
		*/
		end else begin
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
