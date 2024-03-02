
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
   
   input        sound_wren1,
   input [15:0] sound_in1,
   input        sound_wren2,
   input [15:0] sound_in2,  
   input        sound_wren3, 
   input [15:0] sound_in3,
   input        sound_wren4,
   input [15:0] sound_in4,           

   output        sound_write_ready,                                          
   output [15:0] sound_l_out,
   output [15:0] sound_r_out       
);
                                

parameter VRAM_SIZE = 32'h4000; 
parameter MAX_BURST = 32'd512;
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
assign sound_write_ready = fifo_samples[0] + fifo_samples[1] + fifo_samples[2] + fifo_samples[3] < VRAM_SIZE - MAX_BURST; 


////////////////////////// FIFO ////////////////////////////////////////////
reg[15:0] fifo_sound_in[4];
wire[15:0] fifo_sound_q[4];
reg sound_rdreq[4], sound_wrreq[4];
wire fifo_rdempty[4], fifo_wrfull[4];
wire[12:0] fifo_samples[4];

reg[1:0] fifo_rd = 2'd0, fifo_rd_next = 2'd1, fifo_wr1 = 2'd0, fifo_wr2 = 2'd1, fifo_wr3 = 2'd2, fifo_wr4 = 2'd3;


fifo_sound fifo_0(
   .aclr(sound_reset),    
   .data(fifo_sound_in[0]),
   .rdclk(clk_audio),
   .rdreq(sound_rdreq[0]),
   .wrclk(clk_sys),
   .wrreq(sound_wrreq[0]),
   .q(fifo_sound_q[0]),
   .rdempty(fifo_rdempty[0]),
   .wrfull(fifo_wrfull[0]),
   .wrusedw(fifo_samples[0])
);

fifo_sound fifo_1(
   .aclr(sound_reset),    
   .data(fifo_sound_in[1]),
   .rdclk(clk_audio),
   .rdreq(sound_rdreq[1]),
   .wrclk(clk_sys),
   .wrreq(sound_wrreq[1]),
   .q(fifo_sound_q[1]),
   .rdempty(fifo_rdempty[1]),
   .wrfull(fifo_wrfull[1]),
   .wrusedw(fifo_samples[1])
);

fifo_sound fifo_2(
   .aclr(sound_reset),    
   .data(fifo_sound_in[2]),
   .rdclk(clk_audio),
   .rdreq(sound_rdreq[2]),
   .wrclk(clk_sys),
   .wrreq(sound_wrreq[2]),
   .q(fifo_sound_q[2]),
   .rdempty(fifo_rdempty[2]),
   .wrfull(fifo_wrfull[2]),
   .wrusedw(fifo_samples[2])
);

fifo_sound fifo_3(
   .aclr(sound_reset),    
   .data(fifo_sound_in[3]),
   .rdclk(clk_audio),
   .rdreq(sound_rdreq[3]),
   .wrclk(clk_sys),
   .wrreq(sound_wrreq[3]),
   .q(fifo_sound_q[3]),
   .rdempty(fifo_rdempty[3]),
   .wrfull(fifo_wrfull[3]),
   .wrusedw(fifo_samples[3])
);

// write sample
always@(posedge clk_sys) begin                             
        
   if (sound_reset) begin
     sound_start      <= 1'b0;         
     samples_skip     <= 1'b0;
     samples_to_start <= 1'b0;
     fifo_wr1         <= 2'd0;                                                                                                                  
     fifo_wr2         <= 2'd1;                                                                                                                  
     fifo_wr3         <= 2'd2;   
     fifo_wr4         <= 2'd3;   
   end     
   
   if (!sound_start && vga_frame >= 32'd1 && vga_vcount <= vga_interlaced && samples_to_start >= samples_buffer) sound_start <= 1'b1;       
   
   sound_wrreq[0] <= 1'b0;
   sound_wrreq[1] <= 1'b0;
   sound_wrreq[2] <= 1'b0;
   sound_wrreq[3] <= 1'b0;
     
   if (sound_wren1 && vga_frame >= 32'd1) begin    
     if (samples_skip < samples_lost) begin
       samples_skip <= samples_skip + 1'b1;  //avoid acum. delayed sound
     end else begin        
       fifo_sound_in[fifo_wr1] <= sound_in1;
       sound_wrreq[fifo_wr1]   <= 1'b1;          
       if (sound_wren2) begin
         fifo_sound_in[fifo_wr2] <= sound_in2;
         sound_wrreq[fifo_wr2]   <= 1'b1;            
         if (sound_wren3) begin
           fifo_sound_in[fifo_wr3] <= sound_in3; 
           sound_wrreq[fifo_wr3]   <= 1'b1;            
           if (sound_wren4) begin
             fifo_sound_in[fifo_wr4] <= sound_in4;
             sound_wrreq[fifo_wr4]   <= 1'b1; 
             samples_to_start <= !sound_start ? sound_chan > 1'b1 ? samples_to_start + 16'd2 : samples_to_start + 16'd4 : 1'b0;  
           end else begin
             fifo_wr1 <= fifo_wr1 + 2'd3;      
             fifo_wr2 <= fifo_wr2 + 2'd3; 
             fifo_wr3 <= fifo_wr3 + 2'd3;
             fifo_wr4 <= fifo_wr4 + 2'd3;
             samples_to_start <= !sound_start ? sound_chan > 1'b1 ? samples_to_start + 16'd1 : samples_to_start + 16'd3 : 1'b0;    
           end
         end else begin
           fifo_wr1 <= fifo_wr1 + 2'd2;      
           fifo_wr2 <= fifo_wr2 + 2'd2; 
           fifo_wr3 <= fifo_wr3 + 2'd2;
           fifo_wr4 <= fifo_wr4 + 2'd2;
           samples_to_start <= !sound_start ? sound_chan > 1'b1 ? samples_to_start + 16'd1 : samples_to_start + 16'd2 : 1'b0;
         end
       end else begin
         fifo_wr1 <= fifo_wr1 + 1'b1;      
         fifo_wr2 <= fifo_wr2 + 1'b1; 
         fifo_wr3 <= fifo_wr3 + 1'b1;
         fifo_wr4 <= fifo_wr4 + 1'b1;
         samples_to_start <= !sound_start ? sound_chan > 1'b1 ? samples_to_start + 16'd1 : samples_to_start + 16'd1 : 1'b0; 
       end                         
     end    
   end             
        
   if (samples_lost == 16'd0) samples_skip <= 16'd0;
        
end


// get sample
always@(posedge clk_audio) begin                                                        
   
   if (sound_reset) begin
     samples_lost <= 1'b0;
     fifo_rd      <= 2'd0;
     fifo_rd_next <= 2'd1;                           
   end
        
   sound_rdreq[0] <= 1'b0;
   sound_rdreq[1] <= 1'b0;
   sound_rdreq[2] <= 1'b0;
   sound_rdreq[3] <= 1'b0;
        
   if (sound_start) begin                
     if (audio_cnt == clocks_per_sample - 1'b1) begin
       audio_cnt     <= 16'd0;
       sound_rdreq[fifo_rd]      <= (fifo_rdempty[fifo_rd]      || sound_chan == 1'b0) ? 1'b0 : 1'b1;
       sound_rdreq[fifo_rd_next] <= (fifo_rdempty[fifo_rd_next] || sound_chan <= 1'b1) ? 1'b0 : 1'b1;     
       samples_lost  <= (sound_enabled && fifo_rdempty[fifo_rd] && sound_chan != 1'b0 && !sound_synced) ? samples_lost + 1'b1 : 1'b0;                 
     end else begin
       audio_cnt     <= audio_cnt + 1'b1;
     end  
    
    if (audio_cnt == 16'd0) begin                                                                                           
      if (sound_chan == 1'b0) begin
        sound_left   <= 1'b0; 
        sound_right  <= 1'b0; 
      end else begin        
        sound_left   <= fifo_sound_q[fifo_rd];
        sound_right  <= sound_chan == 1'b1 ? fifo_sound_q[fifo_rd] : fifo_sound_q[fifo_rd_next];              
        fifo_rd      <= sound_chan == 1'b1 ? fifo_rd + 1'b1 : fifo_rd + 2'd2;
        fifo_rd_next <= sound_chan == 1'b1 ? fifo_rd_next + 1'b1 : fifo_rd_next + 2'd2;  
      end                                                                                     
    end                
    
  end
        
end

endmodule

