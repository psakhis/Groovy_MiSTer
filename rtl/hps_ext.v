//
// hps_ext for PoC
//
// Copyright (c) 2023 Psakhis based on hps_ext of Alexey Melnikov
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
    input      [8:0]  state, 
    input             hps_rise,     
    input      [1:0]  hps_verbose,  
    input             hps_blit,     
    input             hps_screensaver,      
    input             hps_audio,
    output reg [1:0]  sound_rate = 0,
    output reg [1:0]  sound_chan = 0,
    input             vga_frameskip,        
    input      [15:0] vga_vcount,   
    input      [31:0] vga_frame,    
    input             vga_vblank,   
    input             vga_f1,
    input      [23:0] vram_pixels,
    input      [23:0] vram_queue,
    input             vram_synced,
    input             vram_end_frame,
    input             vram_ready,
    output reg        cmd_init = 0,	
    input             reset_switchres,
    output reg        cmd_switchres = 0,         
    input             reset_blit,
    output reg        cmd_blit = 0,
    output reg        cmd_logo = 0,
    output reg        cmd_audio = 0,
    input             reset_audio,
    output reg [15:0] audio_samples = 0,
	   input             reset_blit_lz4,
	   output reg        cmd_blit_lz4 = 0,
	   output reg [31:0] lz4_size = 0,
    output reg        lz4_AB = 0
/* DEBUG
    input      [23:0] PoC_frame_lz4,    
    input      [23:0] PoC_subframe_lz4_bytes,	  
    input      [15:0] PoC_subframe_blit_lz4,	  
    input      [31:0] lz4_uncompressed_bytes,
    input      [31:0] lz4_gravats,
    input      [31:0] lz4_llegits,
    input      [3:0]  lz4_state,
    input             lz4_done,
    input             lz4_paused,
    input             lz4_run,
    input      [7:0]  lz4_burst,
 */
    
 );

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = EXT_BUS[34];

localparam EXT_CMD_MIN = GET_GROOVY_STATUS;
localparam EXT_CMD_MAX = SET_BLIT_LZ4_B;

localparam GET_GROOVY_STATUS = 'hf0;
localparam GET_GROOVY_HPS    = 'hf1;
localparam SET_INIT          = 'hf2;
localparam SET_SWITCHRES     = 'hf3;
localparam SET_BLIT          = 'hf4;
localparam SET_LOGO          = 'hf5;
localparam SET_AUDIO         = 'hf6;
localparam SET_BLIT_LZ4_A    = 'hf7;
localparam SET_BLIT_LZ4_B    = 'hf8;

reg [15:0] io_dout;
reg        dout_en = 0;
reg  [4:0] byte_cnt;

//snapshot
reg [31:0] hps_vga_frame;
reg [15:0] hps_vga_vcount;
reg        hps_vga_vblank;
reg        hps_vga_f1;
reg        hps_vga_frameskip;
reg [23:0] hps_vram_pixels;
reg [23:0] hps_vram_queue;
reg        hps_vram_synced;
reg        hps_vram_end_frame;
reg        hps_vram_ready;      


always@(posedge clk_sys) begin
        reg [15:0] cmd;
        reg  [7:0] hps_rise_req = 0;
        reg        old_hps_rise = 0; 

        old_hps_rise <= hps_rise;
        if(old_hps_rise ^ hps_rise) hps_rise_req <= hps_rise_req + 1'd1;
        
        if (reset_switchres) cmd_switchres <= 1'b0;     
        if (reset_blit)      cmd_blit      <= 1'b0;       
        if (reset_audio)     cmd_audio     <= 1'b0;		  			     
		      if (reset_blit_lz4)  cmd_blit_lz4  <= 1'b0;		  			      
        
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
                        if(io_din == SET_LOGO)          io_dout <= hps_rise_req;                                        
                        if(io_din == SET_AUDIO)         io_dout <= hps_rise_req;                                        
								                if(io_din == SET_BLIT_LZ4_A)    io_dout <= hps_rise_req;  
                        if(io_din == SET_BLIT_LZ4_B)    io_dout <= hps_rise_req;                                                                              
                end else begin
              
                        case(cmd)
 
                               GET_GROOVY_STATUS: case(byte_cnt)                                        
                                           1: 
                                           begin                                                      
                                              io_dout            <= vga_frame[15:0];
                                              hps_vga_frame      <= vga_frame;
                                              hps_vga_vcount     <= vga_vcount;
                                              hps_vga_vblank     <= vga_vblank;
                                              hps_vga_f1         <= vga_f1;
                                              hps_vga_frameskip  <= vga_frameskip;
                                              hps_vram_pixels    <= vram_pixels;
                                              hps_vram_queue     <= vram_queue;
                                              hps_vram_synced    <= vram_synced;
                                              hps_vram_end_frame <= vram_end_frame;
                                              hps_vram_ready     <= vram_ready;
                                           end
                                           2: io_dout <= hps_vga_frame[31:16];                                                     
                                           3: io_dout <= hps_vga_vcount; 
                                           4: io_dout <= hps_vram_pixels[15:0];                                            
                                           5: io_dout <= {(state == 8'd0) ? 1'b0 : 1'b1, hps_audio, hps_vga_f1, hps_vga_vblank, hps_vga_frameskip, hps_vram_synced, hps_vram_end_frame, hps_vram_ready, hps_vram_pixels[23:16]};    
                                           6: io_dout <= hps_vram_queue[15:0];
                                           7: io_dout <= {8'd0, hps_vram_queue[23:16]};                                
/* DEBUG                                 	                                          
                                           8: io_dout <= PoC_frame_lz4[15:0];
                                           9: io_dout <= {8'd0, PoC_frame_lz4[23:16]};   												 
                                          10: io_dout <= PoC_subframe_lz4_bytes[15:0];
                                          11: io_dout <= {8'd0, PoC_subframe_lz4_bytes[23:16]}; 
                                          12: io_dout <= PoC_subframe_blit_lz4;
														                            13: io_dout <= lz4_uncompressed_bytes[15:0];												 
													                             14: io_dout <= lz4_uncompressed_bytes[31:16];
                                          15: io_dout <= lz4_gravats[15:0];												 
													                             16: io_dout <= lz4_gravats[31:16];
                                          17: io_dout <= lz4_llegits[15:0];												 
													                             18: io_dout <= lz4_llegits[31:16];
                                          19: io_dout <= {lz4_burst, 1'd0, lz4_run, lz4_paused, lz4_done, lz4_state};
*/
                                        endcase
                                                
                               GET_GROOVY_HPS: case(byte_cnt)
                                                 1: io_dout <= {12'd0, hps_screensaver, hps_blit, hps_verbose};                                                                                                 
                                               endcase                                 
                                                
                               SET_INIT: case(byte_cnt)
                                           1: 
                                           begin                                                      
                                             cmd_init    <= io_din[0];														  
                                             sound_rate  <= 0;
                                             sound_chan  <= 0;
                                           end  
                                           2:
                                           begin
                                             sound_rate  <= io_din[9:8];
                                             sound_chan  <= io_din[1:0];                                                    
                                           end                                                                                                                  
                                         endcase 
                                                
                                SET_SWITCHRES: case(byte_cnt)
                                                 1: cmd_switchres <= io_din[0];                  
                                               endcase 
                                                
                                SET_BLIT: case(byte_cnt)
                                            1: cmd_blit <= io_din[0];                       
                                          endcase         
                                
                                SET_LOGO: case(byte_cnt)
                                            1: cmd_logo <= io_din[0];                       
                                          endcase                 
                                
                                SET_AUDIO: case(byte_cnt)
                                             1: 
                                             begin 
                                               cmd_audio     <= 1'b1;
                                               audio_samples <= io_din;                      
                                             end  
                                           endcase 
														 
										                      SET_BLIT_LZ4_A: case(byte_cnt)
                                           1: lz4_size[15:0] <= io_din;                                          
                                           2:
                                           begin
                                              lz4_size[31:16] <= io_din;
                                              lz4_AB          <= 1'b0;
                                              cmd_blit_lz4    <= 1'b1;
                                           end                                                                                                                  
                                         endcase 		
                                
                                SET_BLIT_LZ4_B: case(byte_cnt)
                                           1: lz4_size[15:0] <= io_din;                                          
                                           2:
                                           begin
                                              lz4_size[31:16] <= io_din;
                                              lz4_AB          <= 1'b1;
                                              cmd_blit_lz4    <= 1'b1;
                                           end                                                                                                                  
                                         endcase 		 
                                                                        
                       endcase
                end
        end
end

endmodule
