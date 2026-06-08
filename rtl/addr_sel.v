// ============================================================================
// Module      : addr_sel
// Description : SRAM read-address generator for weight and data banks
// Technology  : IHP SG13G2 130nm
//
// Translates the controller's linear `addr_serial_num` (0–127) into the four
// read addresses required per cycle: two weight ports (w0/w1) and two data
// ports (d0/d1). Ports w1/d1 are skewed by 4 entries to feed the lower half
// (rows/cols 4–7) of the array. Addresses are registered to map cleanly onto
// the SRAM input flip-flops; out-of-range cycles park the address at 127.
// ============================================================================

module addr_sel
(
	input clk,
	input [6:0] addr_serial_num,			// max 126; addr 127 is parked/idle

	// weight read addresses
	output reg [9:0] sram_raddr_w0,			// columns 0–3
	output reg [9:0] sram_raddr_w1,			// columns 4–7

	// data read addresses
	output reg [9:0] sram_raddr_d0,			// rows 0–3
	output reg [9:0] sram_raddr_d1			// rows 4–7
);

wire [9:0] sram_raddr_w0_nx;			//queue 0~3
wire [9:0] sram_raddr_w1_nx;			//queue 4~7

//sel for d0~d7
wire [9:0] sram_raddr_d0_nx;
wire [9:0] sram_raddr_d1_nx;

always@(posedge clk) begin				//fit in output flip-flop
	sram_raddr_w0 <= sram_raddr_w0_nx;
	sram_raddr_w1 <= sram_raddr_w1_nx;

	sram_raddr_d0 <= sram_raddr_d0_nx;
	sram_raddr_d1 <= sram_raddr_d1_nx;
end

assign sram_raddr_w0_nx = (addr_serial_num<=98)? { {3{1'd0}} , addr_serial_num} : 127;
assign sram_raddr_w1_nx = (addr_serial_num>=4 && addr_serial_num<=102)? { {3{1'd0}} , addr_serial_num-7'd4} : 127;

assign sram_raddr_d0_nx = (addr_serial_num<=98)? { {3{1'd0}} , addr_serial_num} : 127;
assign sram_raddr_d1_nx = (addr_serial_num>=4 && addr_serial_num<=102)? { {3{1'd0}} , addr_serial_num-7'd4} : 127;


endmodule
