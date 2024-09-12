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
    input      [7:0]  state, 
    input             hps_rise,     
    input      [1:0]  hps_verbose,  
    input             hps_blit,     
    input             hps_screensaver,      
    input      [1:0]  hps_kbd_inputs,      
    input      [1:0]  hps_joy_inputs,      
    input             hps_audio,
    input             hps_jumbo_frames,
    input             hps_server_type,
    input      [1:0]  hps_arm_clock,
    output reg [1:0]  sound_rate = 0,
    output reg [1:0]  sound_chan = 0,
    output reg [1:0]  rgb_mode = 0, 
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
    output reg [31:0] switchres_frame = 0,             
    input             reset_blit,
    output reg        cmd_blit = 0,
    output reg        cmd_logo = 0,
    output reg        cmd_audio = 0,
    input             reset_audio,
    output reg [15:0] audio_samples = 0,
    input             reset_blit_lz4,
    output reg        cmd_blit_lz4 = 0,
    output reg [31:0] lz4_size = 0,
    output reg [1:0]  lz4_ABCD = 0,
    output reg [1:0]  lz4_field = 0,
    input      [31:0] lz4_uncompressed_bytes,   
    output reg        cmd_blit_vsync = 0
/* DEBUG 
    output reg [24:0] blit_frame = 0,
    output reg [24:0] blit_pixels = 0,
    output reg [24:0] blit_bytes = 0,
    output reg [15:0] blit_num = 0,
    output reg        blit_field = 0,
    input      [31:0]  PoC_subframe_wr_bytes,
    input             lz4_run,
    input             PoC_lz4_resume,
    input             PoC_test1,
    input             PoC_test2,
    input             cmd_fskip,
    input             lz4_stop,
    input     [1:0]   PoC_lz4_ABCD,
    input     [31:0]  lz4_compressed_bytes,
    input     [31:0]  lz4_gravats,
    input     [31:0]  lz4_llegits,
    input     [31:0]  PoC_subframe_lz4_bytes,
    input     [15:0]  PoC_subframe_blit_lz4 */

    
 );

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = EXT_BUS[34];

localparam EXT_CMD_MIN = GET_GROOVY_STATUS;
localparam EXT_CMD_MAX = SET_BLIT_FIELD_LZ4;
//localparam EXT_CMD_MAX = SET_BLIT_BYTES;

localparam GET_GROOVY_STATUS  = 'hf0;
localparam GET_GROOVY_HPS     = 'hf1;
localparam SET_INIT           = 'hf2;
localparam SET_SWITCHRES      = 'hf3;
localparam SET_BLIT           = 'hf4;
localparam SET_LOGO           = 'hf5;
localparam SET_AUDIO          = 'hf6;
localparam SET_BLIT_LZ4       = 'hf7;
localparam SET_BLIT_FIELD_LZ4 = 'hf8;

//new blit sppi
/*
localparam SET_BLIT_FRAME     = 'hf9;
localparam SET_BLIT_PIXELS    = 'hfa;
localparam SET_BLIT_BYTES     = 'hfb;
*/

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


reg[31:0]  hps_lz4_uncompressed_bytes;



reg[15:0]  m_temp;

// DEBUG 
/*
reg[7:0]   hps_state;
reg[31:0]  hps_PoC_subframe_wr_bytes;
reg        hps_PoC_test1;
reg        hps_PoC_test2;
reg        hps_PoC_lz4_resume;
reg        hps_lz4_run;
reg        hps_cmd_fskip;
reg        hps_lz4_stop;
reg[1:0]   hps_PoC_lz4_ABCD;
reg[31:0]  hps_lz4_compressed_bytes;
reg[31:0]  hps_lz4_gravats;
reg[31:0]  hps_lz4_llegits;
reg[31:0]  hps_PoC_subframe_lz4_bytes;
reg[15:0]  hps_PoC_subframe_blit_lz4;
*/                           

always@(posedge clk_sys) begin
        reg [15:0] cmd;
        reg  [7:0] hps_rise_req = 0;
        reg        old_hps_rise = 0; 

        old_hps_rise <= hps_rise;
        if(old_hps_rise ^ hps_rise) hps_rise_req <= hps_rise_req + 1'd1;
        
        if (reset_switchres)  cmd_switchres  <= 1'b0;     
        if (reset_blit)       cmd_blit       <= 1'b0;       
        if (reset_audio)      cmd_audio      <= 1'b0;                    
        if (reset_blit_lz4)   cmd_blit_lz4   <= 1'b0;                                                                          
        
        if(~io_enable) begin
                dout_en        <= 0;
                io_dout        <= 0;
                byte_cnt       <= 0;
                cmd            <= 0; 
                cmd_blit_vsync <= 0;                
        end
        else if(io_strobe) begin

                io_dout <= 0;
                if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

                if(byte_cnt == 0) begin
                        cmd <= io_din;
                        dout_en <= (io_din >= EXT_CMD_MIN && io_din <= EXT_CMD_MAX);
                        if(io_din == GET_GROOVY_STATUS)  io_dout <= hps_rise_req;                
                        if(io_din == GET_GROOVY_HPS)     io_dout <= hps_rise_req;                
                        if(io_din == SET_INIT)           io_dout <= hps_rise_req;                
                        if(io_din == SET_SWITCHRES)      io_dout <= hps_rise_req;                                        
                        if(io_din == SET_BLIT)           io_dout <= hps_rise_req;                                        
                        if(io_din == SET_LOGO)           io_dout <= hps_rise_req;                                        
                        if(io_din == SET_AUDIO)          io_dout <= hps_rise_req;                                        
                        if(io_din == SET_BLIT_LZ4)       io_dout <= hps_rise_req;                          
                        if(io_din == SET_BLIT_FIELD_LZ4) io_dout <= hps_rise_req;                          
                        //if(io_din == SET_BLIT_FRAME)     io_dout <= hps_rise_req;                          
                        //if(io_din == SET_BLIT_PIXELS)    io_dout <= hps_rise_req;                          
                        //if(io_din == SET_BLIT_BYTES)     io_dout <= hps_rise_req;                          
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
                                              hps_lz4_uncompressed_bytes <= lz4_uncompressed_bytes;

// DEBUG 
/*
                                              hps_state <= state;
                                              hps_PoC_subframe_wr_bytes <= PoC_subframe_wr_bytes;
                                              hps_PoC_test1 <= PoC_test1;
                                              hps_PoC_test2 <= PoC_test2;
                                              hps_PoC_lz4_resume <= PoC_lz4_resume;
                                              hps_lz4_run <= lz4_run;
                                              hps_cmd_fskip <= cmd_fskip;
                                              hps_lz4_stop <= lz4_stop;
                                              hps_PoC_lz4_ABCD <= PoC_lz4_ABCD;
                                              hps_lz4_compressed_bytes <= lz4_compressed_bytes;
                                              hps_lz4_gravats <= lz4_gravats;
                                              hps_lz4_llegits <= lz4_llegits;
                                              hps_PoC_subframe_lz4_bytes <= PoC_subframe_lz4_bytes;
                                              hps_PoC_subframe_blit_lz4 <= PoC_subframe_blit_lz4;
*/

                                           end
                                           2: io_dout <= hps_vga_frame[31:16];                                                     
                                           3: io_dout <= hps_vga_vcount; 
                                           4: io_dout <= {hps_vram_queue[7:0], (state == 8'd0) ? 1'b0 : 1'b1, hps_audio, hps_vga_f1, hps_vga_vblank, hps_vga_frameskip, hps_vram_synced, hps_vram_end_frame, hps_vram_ready};    
                                           5: io_dout <= hps_vram_queue[23:8];                                                                                       
                                           6: io_dout <= hps_vram_pixels[15:0];
                                           7: io_dout <= {8'd0, hps_vram_pixels[23:16]};                                           
                                           8: io_dout <= hps_lz4_uncompressed_bytes[15:0];                                     
                                           9: io_dout <= hps_lz4_uncompressed_bytes[31:16]; 
// DEBUG 
/*
                                           10: io_dout <= hps_state;
                                           11: io_dout <= hps_PoC_subframe_wr_bytes[15:0];                                     
                                           12: io_dout <= hps_PoC_subframe_wr_bytes[31:16]; 
                                           13: io_dout <= {8'd0, hps_cmd_fskip, hps_PoC_lz4_ABCD, hps_lz4_stop, hps_PoC_test2, hps_PoC_test1, hps_PoC_lz4_resume, hps_lz4_run};
                                           14: io_dout <= hps_lz4_compressed_bytes[15:0];                                   
                                           15: io_dout <= hps_lz4_compressed_bytes[31:16];                      
                                           16: io_dout <= hps_lz4_gravats[15:0];                                   
                                           17: io_dout <= hps_lz4_gravats[31:16];  
                                           18: io_dout <= hps_lz4_llegits[15:0];                                   
                                           19: io_dout <= hps_lz4_llegits[31:16]; 
                                           20: io_dout <= hps_PoC_subframe_lz4_bytes[15:0];                                    
                                           21: io_dout <= hps_PoC_subframe_lz4_bytes[31:16]; 
                                           22: io_dout <= hps_PoC_subframe_blit_lz4;      
*/                                                                                                      
                                        endcase
                                                
                               GET_GROOVY_HPS: case(byte_cnt)
                                                 1: io_dout <= {4'd0, hps_arm_clock, hps_server_type, hps_jumbo_frames, hps_joy_inputs, hps_kbd_inputs, hps_screensaver, hps_blit, hps_verbose};                                                                                                 
                                               endcase                                 
                                                
                               SET_INIT: case(byte_cnt)
                                           1: 
                                           begin     
                                             m_temp          <= io_din;                                          
                                             cmd_switchres   <= 0;      
                                             cmd_logo        <= 0;
                                             cmd_audio       <= 0;
                                             cmd_blit        <= 0;
                                             cmd_blit_lz4    <= 0;
                                             lz4_size        <= 0;
                                             lz4_ABCD        <= 0;
                                             lz4_field       <= 0;                                                                                                                                  
                                             sound_rate      <= 0;
                                             sound_chan      <= 0;
                                             rgb_mode        <= 0;
                                             switchres_frame <= 32'd0;
                                             //blit_frame  <= 24'd0;
                                             //blit_pixels <= 24'd0;
                                           end  
                                           2:
                                           begin
                                             sound_rate <= io_din[1:0];
                                             sound_chan <= io_din[3:2];   
                                             rgb_mode   <= io_din[5:4]; 
                                             cmd_init   <= m_temp[0];                                            
                                           end                                                                                                                  
                                         endcase 
                                                
                                SET_SWITCHRES: case(byte_cnt)
                                            1: switchres_frame[15:0]  <= io_din;                                          
                                            2: 
                                            begin 
                                              switchres_frame[31:16] <= io_din;  
                                              cmd_switchres          <= 1'b1;                  
                                            end
                                          endcase 
                                                
                                SET_BLIT: case(byte_cnt)
                                            1: 
                                            begin
                                               cmd_blit        <= io_din[0];   
                                               cmd_blit_vsync  <= 1'b1;                                             
                                            end   
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
                                           
                                SET_BLIT_LZ4: case(byte_cnt)
                                           1: lz4_ABCD       <= io_din[1:0];
                                           2: lz4_size[15:0] <= io_din;                                          
                                           3:
                                           begin
                                              lz4_size[31:16] <= io_din;
                                              lz4_field       <= 2'd2;                                             
                                              cmd_blit_lz4    <= 1'b1;
                                              cmd_blit_vsync  <= 1'b1;
                                           end                                                                                                                  
                                         endcase                 
                                         
                                SET_BLIT_FIELD_LZ4: case(byte_cnt)
                                           1: lz4_ABCD        <= io_din[1:0];
                                           2: lz4_size[15:0]  <= io_din;                                          
                                           3: lz4_size[31:16] <= io_din;                                            
                                           4:
                                           begin
                                              lz4_field       <= io_din[1:0]; 
                                              cmd_blit_lz4    <= 1'b1;
                                              cmd_blit_vsync  <= 1'b1;
                                           end                                                                                                                  
                                         endcase 
/*      
                                SET_BLIT_FRAME: case(byte_cnt)
                                           1: m_temp      <= io_din; 
                                           2: 
                                           begin
                                             blit_frame  <= {io_din[7:0], m_temp};
                                             blit_field  <= io_din[8];
                                             blit_pixels <= 24'd0;
                                             blit_num    <= 16'd0;
                                           end                                                                                                                                                             
                                         endcase
                                         
                                SET_BLIT_PIXELS: case(byte_cnt)
                                           1: m_temp      <= io_din; 
                                           2: 
                                           begin
                                             blit_pixels <= {io_din[7:0], m_temp};                                          
                                             blit_num    <= blit_num + 1'b1;
                                           end  
                                         endcase                                         
*/ 
                       endcase
                end
        end
end

endmodule
