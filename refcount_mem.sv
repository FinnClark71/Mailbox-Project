module refcount_mem #(
    parameter int SLOT_W = 8,
    parameter int COUNT_W = 4,      // up to 15 refs
    parameter int NUM_SLOTS = 256
)(
    input  logic                 clk,
    input  logic                 rst,

    // Increment refcount for a slot
    input  logic                 inc,
    input  logic [SLOT_W-1:0]    inc_slot,

    // Decrement refcount for a slot
    input  logic                 dec,
    input  logic [SLOT_W-1:0]    dec_slot,

    // Output: slot just became free (count hit zero)
    output logic                 free_valid,
    output logic [SLOT_W-1:0]    free_slot
);

    logic [COUNT_W-1:0] mem [0:NUM_SLOTS-1];

    integer i;

    always_ff @(posedge clk) begin
		if (rst) begin
			for (i = 0; i < NUM_SLOTS; i = i + 1)
				mem[i] = '0;        //blocking assignment

			free_valid <= 1'b0;
			free_slot  <= '0;
		
		end else begin
            free_valid <= 1'b0;

            // Handle simultaneous inc/dec cleanly
            if (inc && dec && (inc_slot == dec_slot)) begin
                // Net effect = 0 change. Also prevents false "free" pulses.
                // (If you want to flag underflow errors later, this is the place.)
                free_valid <= 1'b0;
            end else begin
                if (inc) begin
                    mem[inc_slot] <= mem[inc_slot] + 1'b1;
                end

                if (dec) begin
                    if (mem[dec_slot] == 0) begin
                        // Underflow protection: keep at 0, no free pulse
                        mem[dec_slot] <= '0;
                        free_valid    <= 1'b0;
                    end else if (mem[dec_slot] == 1) begin
                        mem[dec_slot] <= '0;
                        free_valid    <= 1'b1;
                        free_slot     <= dec_slot;
                    end else begin
                        mem[dec_slot] <= mem[dec_slot] - 1'b1;
                    end
                end
            end
        end

			
		/*
		end else begin
			free_valid <= 1'b0;

			if (inc) begin
				mem[inc_slot] <= mem[inc_slot] + 1'b1;
			end

			if (dec) begin
				if (mem[dec_slot] == 1) begin
					mem[dec_slot] <= '0;
					free_valid <= 1'b1;
					free_slot  <= dec_slot;
				end else begin
					mem[dec_slot] <= mem[dec_slot] - 1'b1;
				end
			end
		end
		*/
	end


endmodule
