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
	input      [1:0]  hps_verbose,	
	input      [2:0]  hps_blit,	
	input             vga_frameskip,	
	input      [15:0] vga_vcount,	
	input      [31:0] vga_frame,	
	input             vga_vblank,	
	input      [23:0] vram_pixels,
	input             vram_synced,
	input             vram_end_frame,
	input             vram_ready,
   output reg        cmd_init = 0,
	input             reset_switchres,
   output reg        cmd_switchres = 0,		
	input             reset_blit,
   output reg        cmd_blit = 0		
 );

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = EXT_BUS[34];

localparam EXT_CMD_MIN = GET_GROOVY_STATUS;
localparam EXT_CMD_MAX = SET_BLIT;

localparam GET_GROOVY_STATUS = 'hf0;
localparam GET_GROOVY_HPS    = 'hf1;
localparam SET_INIT          = 'hf2;
localparam SET_SWITCHRES     = 'hf3;
localparam SET_BLIT          = 'hf4;

reg [15:0] io_dout;
reg        dout_en = 0;
reg  [4:0] byte_cnt;

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg  [7:0] hps_rise_req = 0;
	reg        old_hps_rise = 0; 

	old_hps_rise <= hps_rise;
	if(old_hps_rise ^ hps_rise) hps_rise_req <= hps_rise_req + 1'd1;
	
	if (reset_switchres) cmd_switchres <= 1'b0;	
	if (reset_blit) cmd_blit <= 1'b0;	
	
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
			if(io_din == GET_GROOVY_STATUS) io_dout <= hps_rise_req; 		
			if(io_din == GET_GROOVY_HPS)    io_dout <= hps_rise_req; 		
			if(io_din == SET_INIT)          io_dout <= hps_rise_req; 		
			if(io_din == SET_SWITCHRES)     io_dout <= hps_rise_req; 					
			if(io_din == SET_BLIT)          io_dout <= hps_rise_req; 					
		end else begin
	      
			case(cmd)

				GET_GROOVY_STATUS: case(byte_cnt)				         
							1: io_dout <= vga_frame[15:0];
							2: io_dout <= vga_frame[31:16];							
							3: io_dout <= vga_vcount; 
							4: io_dout <= vram_pixels[15:0];
							5: io_dout <= {3'd0, vga_vblank, vga_frameskip, vram_synced, vram_end_frame, vram_ready, vram_pixels[23:16]};							
						endcase
						
				GET_GROOVY_HPS: case(byte_cnt)
				         1: io_dout <= {3'd0, hps_blit, hps_verbose};													
						endcase					
						
				SET_INIT: case(byte_cnt)
							1: cmd_init <= io_din[0];			
						endcase 
						
				SET_SWITCHRES: case(byte_cnt)
							1: cmd_switchres <= io_din[0];			
						endcase 
						
				SET_BLIT: case(byte_cnt)
							1: cmd_blit <= io_din[0];			
						endcase		
									
			endcase
		end
	end
end

endmodule
