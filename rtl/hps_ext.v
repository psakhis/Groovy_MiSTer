//
// hps_ext for PoC
//
// Copyright (c) 2020 Alexey Melnikov
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
///////////////////////////////////////////////////////////////////////

module hps_ext
(
	input             clk_sys,
	inout      [35:0] EXT_BUS,	
	input             hps_rise,
	input      [15:0] vga_vcount,
   output reg        cmd_init = 0	
 );

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = EXT_BUS[34];

localparam EXT_CMD_MIN = GET_VCOUNT;
localparam EXT_CMD_MAX = SET_INIT;

localparam GET_VCOUNT    = 'hf0;
localparam SET_INIT      = 'hf1;

reg [15:0] io_dout;
reg        dout_en = 0;
reg  [4:0] byte_cnt;

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg  [7:0] hps_rise_req = 0;
	reg        old_hps_rise = 0; 

	old_hps_rise <= hps_rise;
	if(old_hps_rise ^ hps_rise) hps_rise_req <= hps_rise_req + 1'd1;
	
	if(~io_enable) begin
		dout_en <= 0;
		io_dout <= 0;
		byte_cnt <= 0;
		cmd <= 0;
		//if(cmd == CMD_INIT) cmd_init <= ~cmd_init; 		
	end
	else if(io_strobe) begin

		io_dout <= 0;
		if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

		if(byte_cnt == 0) begin
			cmd <= io_din;
			dout_en <= (io_din >= EXT_CMD_MIN && io_din <= EXT_CMD_MAX);
			if(io_din == GET_VCOUNT) io_dout <= hps_rise_req; 		
			if(io_din == SET_INIT) io_dout <= hps_rise_req; 		
		end else begin

			case(cmd)

				GET_VCOUNT: case(byte_cnt)
				         1: io_dout <= vga_vcount;
				//			1: io_dout <= {14'h00,vblank,vram_end_frame};
				//			2: io_dout <= cd_in[31:16];
				//			3: io_dout <= cd_in[47:32];
				//			4: io_dout <= cd_in[63:48];
				//			5: io_dout <= cd_in[79:64];
				//			6: io_dout <= cd_in[95:80];
				//			7: io_dout <= cd_in[111:96];
						endcase
									
				SET_INIT: case(byte_cnt)
							1: cmd_init <= io_din[0];
			//				2: cd_out[31:16] <= io_din;
			//				3: cd_out[47:32] <= io_din;
			//				4: cd_out[63:48] <= io_din;
			//				5: cd_out[79:64] <= io_din;
			//				6: cd_out[95:80] <= io_din;
			//				7: cd_out[111:96] <= io_din;
						endcase 					
			endcase
		end
	end
end

endmodule
