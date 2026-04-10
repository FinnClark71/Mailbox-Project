// Free List FIFO
//  Holds IDs of free message slots
//  circular FIFO
//  Separate push / pop
//  Full and empty flags


module freelist #(
    parameter WIDTH = 8,                 // width of each ID 
    parameter DEPTH = 16,                // number of free-list entries
    localparam ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic clk,
    input  logic rst,

    // Allocate a slot, POP
    input  logic pop,
    output logic [WIDTH-1:0] pop_data,
    output logic pop_valid,

    // Free a slot, PUSH
    input  logic push,
    input  logic [WIDTH-1:0] push_data,

    // Status Flags
    output logic full,
    output logic empty
);

    // FIFO storage
    logic [WIDTH-1:0] mem [0:DEPTH-1];
	
	logic [WIDTH-1:0] pop_data_q;
	logic pop_valid_q;

    // Read/write pointers and count
    logic [ADDR_WIDTH-1:0] rd_ptr, wr_ptr;
    logic [ADDR_WIDTH:0] count;          
	
	
	assign pop_data  = pop_data_q;
	assign pop_valid = pop_valid_q;
	
	/*
    assign full  = (count == DEPTH);
    assign empty = (count == 0);
	*/
	localparam int COUNT_W = $clog2(DEPTH+1);

	assign full  = (count == COUNT_W'(DEPTH));
	assign empty = (count == COUNT_W'(0));

	
	logic do_push, do_pop;
	
	assign do_push = push && !full;
	assign do_pop = pop && !empty;


    always_ff @(posedge clk) begin
		if (rst) begin
			rd_ptr      <= 0;
			wr_ptr      <= 0;
			count       <= 0;
			pop_valid_q <= 0;
			pop_data_q  <= '0;   //fix that prevents scratchpad unknown states
		end else begin
			/*
			// Default: no pop output this cycle
			pop_valid_q <= 0;

			// PUSH
			if (push && !full) begin
				mem[wr_ptr] <= push_data;
				wr_ptr <= wr_ptr + 1;
				count <= count + 1;
			end

			// POP
			if (pop && !empty) begin
				pop_data_q <= mem[rd_ptr]; // capture data THIS cycle
				pop_valid_q <= 1;

				rd_ptr <= rd_ptr + 1;
				count <= count - 1;
			end
			*/
			
            // Default: no pop output this cycle
            pop_valid_q <= 0;

            unique case ({do_push, do_pop})
                2'b10: begin
                    // PUSH only
                    mem[wr_ptr] <= push_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    count       <= count + 1'b1;
                end

                2'b01: begin
                    // POP only
                    pop_data_q  <= mem[rd_ptr];
                    pop_valid_q <= 1'b1;

                    rd_ptr      <= rd_ptr + 1'b1;
                    count       <= count - 1'b1;
                end

                2'b11: begin
                    // PUSH + POP same cycle (safe)
                    mem[wr_ptr] <= push_data;
                    wr_ptr      <= wr_ptr + 1'b1;

                    pop_data_q  <= mem[rd_ptr];
                    pop_valid_q <= 1'b1;
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


/*
// Free List FIFO
// Holds IDs of free message slots
// circular FIFO, separate push/pop
// Full and empty flags

module freelist #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16,
    localparam int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic clk,
    input  logic rst,

    // Allocate a slot, POP
    input  logic pop,
    output logic [WIDTH-1:0] pop_data,
    output logic pop_valid,

    // Free a slot, PUSH
    input  logic push,
    input  logic [WIDTH-1:0] push_data,

    // Status Flags
    output logic full,
    output logic empty
);

    // FIFO storage
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [WIDTH-1:0] pop_data_q;
    logic             pop_valid_q;

    // Read/write pointers and count
    logic [ADDR_WIDTH-1:0] rd_ptr, wr_ptr;
    logic [ADDR_WIDTH:0]   count;  // 0..DEPTH

   
    localparam int unsigned DEPTH_U = DEPTH;
    localparam logic [ADDR_WIDTH:0] DEPTH_COUNT = DEPTH_U[ADDR_WIDTH:0];

    assign pop_data  = pop_data_q;
    assign pop_valid = pop_valid_q;

    assign full  = (count == DEPTH_COUNT);
    assign empty = (count == '0);

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr      <= '0;
            wr_ptr      <= '0;
            count       <= '0;
            pop_valid_q <= 1'b0;
            pop_data_q  <= '0;
        end else begin
            pop_valid_q <= 1'b0;

            // Decide actions based on current flags
            logic do_push;
            logic do_pop;
            do_push = push && !full;
            do_pop  = pop  && !empty;
			
			
            // PUSH writes at wr_ptr
            if (do_push) begin
                mem[wr_ptr] <= push_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            // POP reads at rd_ptr
            if (do_pop) begin
                pop_data_q  <= mem[rd_ptr];
                pop_valid_q <= 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Correct count update even when both happen
            unique case ({do_push, do_pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count; // 00 or 11 (net no change)
            endcase
        end
    end

endmodule

*/
