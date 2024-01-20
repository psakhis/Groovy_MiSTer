
 // Psakhis sound module

`timescale 1ns / 1ps

module sound (   
   input        clk_sys,
   input        clk_audio,      
   input [31:0] vga_frame,
   input [15:0] vga_vcount,        
   input [7:0]  vga_interlaced,
   input        sound_reset,
   input        sound_synced,
   input        sound_enabled,     
   input [1:0]  sound_rate,
   input [1:0]  sound_chan,
   input [1:0]  sound_buffer,   
   input        sound_write,       
   input [15:0] sound_l_in,
   input [15:0] sound_r_in,   
        
   output        sound_write_ready,                                          
   output [15:0] sound_l_out,
   output [15:0] sound_r_out       
);
                                

///////////////////////////////////////////////////////////////////////////////

reg sound_start = 1'b0;

reg[15:0] samples_skip = 16'd0;
reg[15:0] samples_lost = 16'd0;
reg[15:0] samples_to_start = 16'd0;

reg[15:0] sound_left;
reg[15:0] sound_right;

reg[15:0] audio_cnt = 16'd0;

wire[15:0] clocks_per_sample;
assign clocks_per_sample = (sound_rate == 2'd2) ? 16'd562 : (sound_rate == 2'd1) ? 16'd1124 : 16'd512;

wire[15:0] samples_buffer;
assign samples_buffer = (sound_buffer == 2'd0) ? 16'd1 : (sound_buffer == 2'd1) ? 16'd700 : (sound_buffer == 2'd2) ? 16'd1400 : 16'd2100;

assign sound_l_out = sound_left;
assign sound_r_out = sound_right;
assign sound_write_ready = !fifo_wrfull_l;


////////////////////////// FIFO ////////////////////////////////////////////
reg[15:0] fifo_sound_l_in, fifo_sound_r_in;
wire[15:0] fifo_sound_l, fifo_sound_r;
reg sound_l_rdreq, sound_r_rdreq, sound_l_wrreq, sound_r_wrreq;
wire fifo_rdempty_l, fifo_wrfull_l, fifo_rdempty_r, fifo_wrfull_r;
wire[12:0] fifo_samples_l, fifo_samples_r;

fifo_sound fifo_l(
   .aclr(sound_reset),    
   .data(fifo_sound_l_in),
   .rdclk(clk_audio),
   .rdreq(sound_l_rdreq),
   .wrclk(clk_sys),
   .wrreq(sound_l_wrreq),
   .q(fifo_sound_l),
   .rdempty(fifo_rdempty_l),
   .wrfull(fifo_wrfull_l),
   .wrusedw(fifo_samples_l)
);

fifo_sound fifo_r(
   .aclr(sound_reset),    
   .data(fifo_sound_r_in),
   .rdclk(clk_audio),
   .rdreq(sound_r_rdreq),
   .wrclk(clk_sys),
   .wrreq(sound_r_wrreq),
   .q(fifo_sound_r),
   .rdempty(fifo_rdempty_r),
   .wrfull(fifo_wrfull_r),
   .wrusedw(fifo_samples_r)
);

// write sample
always@(posedge clk_sys) begin                             
        
   if (sound_reset) begin
     sound_start      <= 1'b0;         
     samples_skip     <= 1'b0;
     samples_to_start <= 1'b0;
   end     
   
   if (!sound_start && vga_frame >= 32'd1 && vga_vcount <= vga_interlaced && samples_to_start >= samples_buffer) sound_start <= 1'b1;       
   
   sound_l_wrreq <= 1'b0;
   sound_r_wrreq <= 1'b0;
     
   if (sound_write && vga_frame >= 32'd1) begin    
     if (samples_skip < samples_lost) begin
       samples_skip <= samples_skip + 1'b1;  //avoid acum. delayed sound
     end else begin 
       fifo_sound_l_in  <= sound_l_in;
       fifo_sound_r_in  <= sound_r_in;
       sound_l_wrreq    <= (sound_chan > 1'b0) ? 1'b1 : 1'b0;
       sound_r_wrreq    <= (sound_chan > 1'b1) ? 1'b1 : 1'b0;
       samples_to_start <= (!sound_start) ? samples_to_start + 1'b1 : 1'b0;              
     end    
   end             
        
   if (samples_lost == 16'd0) samples_skip <= 16'd0;
        
end


// get sample
always@(posedge clk_audio) begin                                                        
   
   if (sound_reset) begin
     samples_lost <= 1'b0;                           
   end
        
   sound_l_rdreq <= 1'b0;
   sound_r_rdreq <= 1'b0;
        
   if (sound_start) begin                
     if (audio_cnt == clocks_per_sample - 1'b1) begin
       audio_cnt     <= 16'd0;
       sound_l_rdreq <= (fifo_rdempty_l || sound_chan == 1'b0) ? 1'b0 : 1'b1;
       sound_r_rdreq <= (fifo_rdempty_r || sound_chan <= 1'b1) ? 1'b0 : 1'b1;     
       samples_lost  <= (sound_enabled && fifo_rdempty_l && sound_chan != 1'b0 && !sound_synced) ? samples_lost + 1'b1 : 1'b0;                 
     end else begin
       audio_cnt     <= audio_cnt + 1'b1;
     end  
    
    if (audio_cnt == 16'd0) begin                                                                                     
      sound_left  <= (sound_chan == 1'b0) ? 1'b0 : fifo_sound_l;
      sound_right <= (sound_chan == 1'b0) ? 1'b0 : (sound_chan == 1'b1) ? fifo_sound_l : fifo_sound_r;                                                                                                                      
    end                
    
  end
        
end

endmodule

