// ============================================================================
// Module      : quantize
// Description : Saturating quantizer — 21-bit accumulator → 16-bit output
// Technology  : IHP SG13G2 130nm
//
// Each of the ARRAY_SIZE lanes is independently clipped to the signed INT16
// range [-32768, 32767]. Values within range pass through their lower 16 bits;
// out-of-range values saturate to the corresponding extreme. Purely
// combinational (no clock).
// ============================================================================

module quantize#(
	parameter ARRAY_SIZE = 8,
	parameter SRAM_DATA_WIDTH = 32,
	parameter DATA_WIDTH = 8,
	parameter OUTPUT_DATA_WIDTH = 16
)
(
	input signed [ARRAY_SIZE*(DATA_WIDTH+DATA_WIDTH+5)-1:0] ori_data,
	output reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data
);

localparam max_val = 32767,min_val = -32768;
localparam ORI_WIDTH = DATA_WIDTH+DATA_WIDTH+5;

reg signed [ORI_WIDTH-1:0] ori_shifted_data;

integer i;

// Clip each lane from the 21-bit accumulator width down to signed 16-bit.
always@* begin
	for(i=0; i<ARRAY_SIZE; i=i+1) begin	
		ori_shifted_data = ori_data[i*ORI_WIDTH +: ORI_WIDTH];
		if(ori_shifted_data >= max_val) quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = max_val;
		else if(ori_shifted_data <= min_val) quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = min_val;
		else quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = ori_shifted_data[OUTPUT_DATA_WIDTH-1:0];
	end
end

endmodule

