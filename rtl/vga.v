
 // Psakhis video module with vram

`timescale 1ns / 1ps

module vga (
   
   input  clk_sys, 
   input  ce_pix,
   
   input  vga_reset,
   input  vga_frame_reset, //reset vga_frame counter   
   input  vga_soft_reset,  //not reset vga_frame counter
   input  vga_wait_vblank, 

   input [15:0] H,    // width of visible area
   input [7:0]  HFP,  // unused time before hsync 
   input [7:0]  HS,   // width of hsync
   input [7:0]  HBP,  // unused time after hsync
   input [15:0] V,    // height of visible area
   input [7:0]  VFP,  // unused time before vsync
   input [7:0]  VS,   // width of vsync
   input [7:0]  VBP,  // unused time after vsync
   input        interlaced,  
   input        FB_interlaced, 
     
   input  vram_active,
   input  vram_reset,              
   
   input       vram_wren1,
   input [7:0] r_vram_in1,
   input [7:0] g_vram_in1,
   input [7:0] b_vram_in1,

   input       vram_wren2,
   input [7:0] r_vram_in2,
   input [7:0] g_vram_in2,
   input [7:0] b_vram_in2,

   input       vram_wren3,
   input [7:0] r_vram_in3,
   input [7:0] g_vram_in3,
   input [7:0] b_vram_in3,

   input       vram_wren4,
   input [7:0] r_vram_in4,
   input [7:0] g_vram_in4,
   input [7:0] b_vram_in4,
     
   input [7:0] r_in,
   input [7:0] g_in,
   input [7:0] b_in,
        
   output        vram_ready,                    
   output [23:0] vram_pixels,              
   output [23:0] vram_queue,
   output        vram_end_frame,   
   output        vram_synced,              
                        
   // VGA output        
   output [31:0] vga_frame,
   output [15:0] vcount,
   output [23:0] vga_pixels,
   
   output hsync,
   output vsync,
   output [7:0] r,
   output [7:0] g,
   output [7:0] b,
   output vga_de,  
   output hblank,
   output vblank,
   
   output vga_f1
  
);
                                
parameter R_NO_VRAM = 8'hFF;
parameter G_NO_VRAM = 8'h00;
parameter B_NO_VRAM = 8'h00;

parameter VRAM_SIZE = 32'h17ED0; 
parameter MAX_BURST = 32'd342;

///////////////////////////////////////////////////////////////////////////////

reg[23:0] vga_pixels_frame = 24'd54180;

reg[15:0] h_cnt;             // horizontal pixel counter
reg[15:0] v_cnt;             // vertical pixel counter
reg[23:0] pixel;             // pixel rgb  
reg[23:0] pixel_counter = 0; // total pixel counter on that frame
reg[31:0] vga_vblanks   = 0; // pixel's frame
reg field = 1'b0;            // interlaced field (0 - odd / 1 - even)
reg _hs, _vs, hb, vb;        // video signals

wire[15:0] H_pulse_start;
wire[15:0] V_total;
wire[15:0] V_pulse_start;
wire[15:0] V_pulse_end;

assign H_pulse_start = (interlaced && field) ? (H+HFP) >> 1 : H+HFP;
assign V_total       = (interlaced && field) ? V+VBP+VFP+VS - 1'b1 : V+VBP+VFP+VS;
assign V_pulse_start = (interlaced && field) ? V+VFP + 1'b1 : V+VFP;
assign V_pulse_end   = (interlaced && field) ? V+VFP+VS + 1'b1 : V+VFP+VS;

assign r = pixel[23:16];
assign g = pixel[15:8];
assign b = pixel[7:0];

assign vcount    = v_cnt;
assign vga_frame = vga_vblanks;
assign vga_de    = ~(hb | vb);
assign hsync     = ~_hs;
assign vsync     = ~_vs;
assign vblank    = vb;
assign hblank    = hb;
assign vga_f1    = field;

/////////////////////////////////////////////////////////////////////////////

reg       FB_prev_interlaced = 1'b0;
reg       FB_field           = 1'b1;
reg       FB_first           = 1'b1;
reg[15:0] FB_H               = 16'd256;
reg[15:0] FB_V               = 16'd240;

/////////////////////////////////////////////////////////////////////////////

reg[23:0] vram_pixel_counter = 24'd0;  // pixels of current frame on all vrams

reg       vram_wait_vblank   = 1'b0;   // waiting vblank to read pixels from vram (soft reset)
reg       vram_out_sync      = 1'b0;   // signal to detect when pixel isn't get from vram
reg       vram_start         = 1'b0;   // start using vram
reg       vga_started        = 1'b0;   // start vblanks counter

assign    vram_ready     = fifo_rgb_queue[0] + fifo_rgb_queue[1] + fifo_rgb_queue[2] + fifo_rgb_queue[3] + fifo_rgb_queue[4] + fifo_rgb_queue[5] < VRAM_SIZE - MAX_BURST;                        // vram it's ready to write ddr burst pixels
assign    vram_end_frame = vram_pixel_counter >= vga_pixels_frame;                    // vram with all frame
assign    vram_pixels    = vram_pixel_counter;                                        // number of current pixels writed on vram for a frame
assign    vram_synced    = !vram_out_sync;                                            // from point of view vram, synced frame 
assign    vram_queue     = fifo_rgb_queue[0] + fifo_rgb_queue[1] + fifo_rgb_queue[2] + fifo_rgb_queue[3] + fifo_rgb_queue[4] + fifo_rgb_queue[5]; // pixels prepared to read
assign    vga_pixels     = vga_pixels_frame;                                          // pixels to get all frame

///////////////////////// FIFO VRAM ////////////////////////////////////////////
reg[7:0] fifo_rgb_r_in[6], fifo_rgb_g_in[6], fifo_rgb_b_in[6];
wire[7:0] fifo_rgb_r[6], fifo_rgb_g[6], fifo_rgb_b[6];
reg fifo_rgb_req[6], fifo_rgb_write[6];
wire fifo_rgb_empty[6], fifo_rgb_full[6];
wire[14:0] fifo_rgb_queue[6];

reg[2:0] fifo_rd = 3'd0, fifo_rd_next = 3'd1, fifo_wr1 = 3'd0, fifo_wr2 = 3'd1, fifo_wr3 = 3'd2, fifo_wr4 = 3'd3;
reg fifo_ahead = 1'b0;

fifo_vga fifo_r0(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[0]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[0]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[0]),
   .q(fifo_rgb_r[0]),
   .rdempty(fifo_rgb_empty[0]),
   .wrfull(fifo_rgb_full[0]),
   .wrusedw(fifo_rgb_queue[0])
);

fifo_vga fifo_g0(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[0]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[0]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[0]),
   .q(fifo_rgb_g[0]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b0(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[0]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[0]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[0]),
   .q(fifo_rgb_b[0]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_r1(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[1]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[1]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[1]),
   .q(fifo_rgb_r[1]),
   .rdempty(fifo_rgb_empty[1]),
   .wrfull(fifo_rgb_full[1]),
   .wrusedw(fifo_rgb_queue[1])
);

fifo_vga fifo_g1(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[1]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[1]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[1]),
   .q(fifo_rgb_g[1]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b1(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[1]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[1]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[1]),
   .q(fifo_rgb_b[1]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_r2(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[2]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[2]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[2]),
   .q(fifo_rgb_r[2]),
   .rdempty(fifo_rgb_empty[2]),
   .wrfull(fifo_rgb_full[2]),
   .wrusedw(fifo_rgb_queue[2])
);

fifo_vga fifo_g2(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[2]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[2]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[2]),
   .q(fifo_rgb_g[2]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b2(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[2]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[2]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[2]),
   .q(fifo_rgb_b[2]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_r3(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[3]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[3]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[3]),
   .q(fifo_rgb_r[3]),
   .rdempty(fifo_rgb_empty[3]),
   .wrfull(fifo_rgb_full[3]),
   .wrusedw(fifo_rgb_queue[3])
);

fifo_vga fifo_g3(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[3]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[3]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[3]),
   .q(fifo_rgb_g[3]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b3(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[3]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[3]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[3]),
   .q(fifo_rgb_b[3]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_r4(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[4]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[4]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[4]),
   .q(fifo_rgb_r[4]),
   .rdempty(fifo_rgb_empty[4]),
   .wrfull(fifo_rgb_full[4]),
   .wrusedw(fifo_rgb_queue[4])
);

fifo_vga fifo_g4(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[4]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[4]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[4]),
   .q(fifo_rgb_g[4]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b4(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[4]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[4]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[4]),
   .q(fifo_rgb_b[4]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_r5(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in[5]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[5]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[5]),
   .q(fifo_rgb_r[5]),
   .rdempty(fifo_rgb_empty[5]),
   .wrfull(fifo_rgb_full[5]),
   .wrusedw(fifo_rgb_queue[5])
);

fifo_vga fifo_g5(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in[5]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[5]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[5]),
   .q(fifo_rgb_g[5]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b5(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in[5]),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req[5]),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write[5]),
   .q(fifo_rgb_b[5]),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

task fifo_move_1;
  begin   
   fifo_wr1 <= fifo_wr1 == 5 ? 3'd0 : fifo_wr1 + 1'b1;      
   fifo_wr2 <= fifo_wr2 == 5 ? 3'd0 : fifo_wr2 + 1'b1; 
   fifo_wr3 <= fifo_wr3 == 5 ? 3'd0 : fifo_wr3 + 1'b1;         
   fifo_wr4 <= fifo_wr4 == 5 ? 3'd0 : fifo_wr4 + 1'b1;               
  end
endtask

task fifo_move_2;
  begin    
   fifo_wr1 <= fifo_wr1 == 5 ? 3'd1 : fifo_wr1 == 4 ? 3'd0 : fifo_wr1 + 3'd2;      
   fifo_wr2 <= fifo_wr2 == 5 ? 3'd1 : fifo_wr2 == 4 ? 3'd0 : fifo_wr2 + 3'd2; 
   fifo_wr3 <= fifo_wr3 == 5 ? 3'd1 : fifo_wr3 == 4 ? 3'd0 : fifo_wr3 + 3'd2;         
   fifo_wr4 <= fifo_wr4 == 5 ? 3'd1 : fifo_wr4 == 4 ? 3'd0 : fifo_wr4 + 3'd2;              
  end
endtask

task fifo_move_3;
  begin    
   fifo_wr1 <= fifo_wr1 == 5 ? 3'd2 : fifo_wr1 == 4 ? 3'd1 : fifo_wr1 == 3 ? 3'd0 : fifo_wr1 + 3'd3;      
   fifo_wr2 <= fifo_wr2 == 5 ? 3'd2 : fifo_wr2 == 4 ? 3'd1 : fifo_wr2 == 3 ? 3'd0 : fifo_wr2 + 3'd3; 
   fifo_wr3 <= fifo_wr3 == 5 ? 3'd2 : fifo_wr3 == 4 ? 3'd1 : fifo_wr3 == 3 ? 3'd0 : fifo_wr3 + 3'd3;         
   fifo_wr4 <= fifo_wr4 == 5 ? 3'd2 : fifo_wr4 == 4 ? 3'd1 : fifo_wr4 == 3 ? 3'd0 : fifo_wr4 + 3'd3;             
  end
endtask

task fifo_move_4;
  begin    
   fifo_wr1 <= fifo_wr1 == 5 ? 3'd3 : fifo_wr1 == 4 ? 3'd2 : fifo_wr1 == 3 ? 3'd1 : fifo_wr1 == 2 ? 3'd0 : fifo_wr1 + 3'd4;      
   fifo_wr2 <= fifo_wr2 == 5 ? 3'd3 : fifo_wr2 == 4 ? 3'd2 : fifo_wr2 == 3 ? 3'd1 : fifo_wr2 == 2 ? 3'd0 : fifo_wr2 + 3'd4; 
   fifo_wr3 <= fifo_wr3 == 5 ? 3'd3 : fifo_wr3 == 4 ? 3'd2 : fifo_wr3 == 3 ? 3'd1 : fifo_wr3 == 2 ? 3'd0 : fifo_wr3 + 3'd4;         
   fifo_wr4 <= fifo_wr4 == 5 ? 3'd3 : fifo_wr4 == 4 ? 3'd2 : fifo_wr4 == 3 ? 3'd1 : fifo_wr4 == 2 ? 3'd0 : fifo_wr4 + 3'd4;             
  end
endtask

task swap_field_at_end_line;
  input [2:0] pixels_to_write;
  begin
    FB_H <= FB_H > pixels_to_write ? FB_H - pixels_to_write : H - pixels_to_write + FB_H;         
    if (FB_H <= pixels_to_write) begin //flip_flop field
      if (vram_pixel_counter + pixels_to_write >= vga_pixels_frame) begin
        FB_field <= FB_first;  
        FB_first <= !FB_first;    
      end else begin 
        FB_field <= !FB_field; 
      end
    end
  end
endtask

// write pixels on fifo
always@(posedge clk_sys) begin                             
   		
   if (vga_reset || vram_reset) begin    
     vram_pixel_counter <= 24'd0; 
     fifo_wr1           <= 3'd0;                                                                                                                  
     fifo_wr2           <= 3'd1;                                                                                                                  
     fifo_wr3           <= 3'd2;                                                                                                                  
     fifo_wr4           <= 3'd3;                                                                                                                                                                                                                                  
   end               
      
   fifo_rgb_write[0] <= 1'b0;  	
   fifo_rgb_write[1] <= 1'b0;  	
   fifo_rgb_write[2] <= 1'b0;  	
   fifo_rgb_write[3] <= 1'b0;  	
   fifo_rgb_write[4] <= 1'b0;  	
   fifo_rgb_write[5] <= 1'b0;  	
                               
   if (vram_wren1) begin    	                        
     vram_pixel_counter         <= vram_end_frame ? 24'd1 : (vram_pixel_counter + 24'd1);      
     fifo_rgb_r_in[fifo_wr1]    <= r_vram_in1;
     fifo_rgb_g_in[fifo_wr1]    <= g_vram_in1;
     fifo_rgb_b_in[fifo_wr1]    <= b_vram_in1;	  
     fifo_rgb_write[fifo_wr1]   <= 1'b1;    
     fifo_move_1();        
   end
 		
   if (vram_wren2) begin
     vram_pixel_counter       <= vram_end_frame ? 24'd2 : (vram_pixel_counter + 24'd2);
     fifo_rgb_r_in[fifo_wr2]  <= r_vram_in2;
     fifo_rgb_g_in[fifo_wr2]  <= g_vram_in2;
     fifo_rgb_b_in[fifo_wr2]  <= b_vram_in2;	  
     fifo_rgb_write[fifo_wr2] <= 1'b1;
     fifo_move_2();    		
   end

   if (vram_wren3) begin
     vram_pixel_counter       <= vram_end_frame ? 24'd3 : (vram_pixel_counter + 24'd3);
     fifo_rgb_r_in[fifo_wr3]  <= r_vram_in3;
     fifo_rgb_g_in[fifo_wr3]  <= g_vram_in3;
     fifo_rgb_b_in[fifo_wr3]  <= b_vram_in3;	  
     fifo_rgb_write[fifo_wr3] <= 1'b1;  
     fifo_move_3();   		
   end  

   if (vram_wren4) begin
     vram_pixel_counter       <= vram_end_frame ? 24'd4 : (vram_pixel_counter + 24'd4);
     fifo_rgb_r_in[fifo_wr4]  <= r_vram_in4;
     fifo_rgb_g_in[fifo_wr4]  <= g_vram_in4;
     fifo_rgb_b_in[fifo_wr4]  <= b_vram_in4;	  
     fifo_rgb_write[fifo_wr4] <= 1'b1;  
     fifo_move_4();   		
   end  

   //frambuffer progressive vs interlaced modeline
   if (vga_reset || FB_prev_interlaced != interlaced || FB_V != V) begin
     FB_prev_interlaced       <= interlaced; 
     FB_H                     <= H; 
     FB_V                     <= V;     
     FB_first                 <= 1'b1;
     FB_field                 <= 1'b1; 
   end

   if (vram_reset) begin
     FB_H                     <= H;
   end
   
   if (interlaced && !FB_interlaced) begin      
     if (vram_wren1 && !vram_wren2) begin //only 1 pixel
       if (!FB_field) begin // cancel write
         fifo_rgb_write[fifo_wr1] <= 1'b0;
         fifo_wr1                 <= fifo_wr1;
         fifo_wr2                 <= fifo_wr2;
         fifo_wr3                 <= fifo_wr3;
         fifo_wr4                 <= fifo_wr4;
       end
       swap_field_at_end_line(1'b1);
     end
     if (vram_wren2 && !vram_wren3) begin //only 2 pixels        
       if (!FB_field) begin // cancel write
         fifo_rgb_write[fifo_wr1]   <= 1'b0;
         fifo_rgb_write[fifo_wr2]   <= 1'b0;
         fifo_wr1                   <= fifo_wr1;
         fifo_wr2                   <= fifo_wr2;
         fifo_wr3                   <= fifo_wr3;
         fifo_wr4                   <= fifo_wr4;
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1; 
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in2;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in2;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in2;	
           fifo_move_1(); 
         end 
       end else begin
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr2] <= 1'b0;          
           fifo_move_1();  
         end 
       end
       swap_field_at_end_line(3'd2);
     end
     if (vram_wren3 && !vram_wren4) begin //3 pixels  
       if (!FB_field) begin // cancel write
         fifo_rgb_write[fifo_wr1]   <= 1'b0;
         fifo_rgb_write[fifo_wr2]   <= 1'b0;
         fifo_rgb_write[fifo_wr3]   <= 1'b0;         
         fifo_wr1                   <= fifo_wr1;
         fifo_wr2                   <= fifo_wr2;
         fifo_wr3                   <= fifo_wr3;
         fifo_wr4                   <= fifo_wr4;
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1; 
           fifo_rgb_write[fifo_wr2] <= 1'b1; 
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in2;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in2;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in2;	
           fifo_rgb_r_in[fifo_wr2]  <= r_vram_in3;
           fifo_rgb_g_in[fifo_wr2]  <= g_vram_in3;
           fifo_rgb_b_in[fifo_wr2]  <= b_vram_in3;
           fifo_move_2();  
         end 
         if (FB_H == 2) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1;          
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in3;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in3;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in3;	
           fifo_move_1(); 
         end
       end else begin
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr2] <= 1'b0;          
           fifo_rgb_write[fifo_wr3] <= 1'b0;  
           fifo_move_1(); 
         end
         if (FB_H == 2) begin           
           fifo_rgb_write[fifo_wr3] <= 1'b0;
           fifo_move_2(); 
         end  
       end 
       swap_field_at_end_line(3'd3);    
     end
     if (vram_wren4) begin //4 pixels  
       if (!FB_field) begin // cancel write
         fifo_rgb_write[fifo_wr1]   <= 1'b0;
         fifo_rgb_write[fifo_wr2]   <= 1'b0;
         fifo_rgb_write[fifo_wr3]   <= 1'b0;         
         fifo_rgb_write[fifo_wr4]   <= 1'b0;         
         fifo_wr1                   <= fifo_wr1;
         fifo_wr2                   <= fifo_wr2;
         fifo_wr3                   <= fifo_wr3;
         fifo_wr4                   <= fifo_wr4;
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1; 
           fifo_rgb_write[fifo_wr2] <= 1'b1; 
           fifo_rgb_write[fifo_wr3] <= 1'b1; 
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in2;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in2;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in2;	
           fifo_rgb_r_in[fifo_wr2]  <= r_vram_in3;
           fifo_rgb_g_in[fifo_wr2]  <= g_vram_in3;
           fifo_rgb_b_in[fifo_wr2]  <= b_vram_in3;
           fifo_rgb_r_in[fifo_wr3]  <= r_vram_in4;
           fifo_rgb_g_in[fifo_wr3]  <= g_vram_in4;
           fifo_rgb_b_in[fifo_wr3]  <= b_vram_in4;
           fifo_move_3();  
         end 
         if (FB_H == 2) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1;          
           fifo_rgb_write[fifo_wr2] <= 1'b1;          
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in3;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in3;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in3;	
           fifo_rgb_r_in[fifo_wr2]  <= r_vram_in4;
           fifo_rgb_g_in[fifo_wr2]  <= g_vram_in4;
           fifo_rgb_b_in[fifo_wr2]  <= b_vram_in4;	
           fifo_move_2(); 
         end
         if (FB_H == 3) begin
           fifo_rgb_write[fifo_wr1] <= 1'b1;                     
           fifo_rgb_r_in[fifo_wr1]  <= r_vram_in4;
           fifo_rgb_g_in[fifo_wr1]  <= g_vram_in4;
           fifo_rgb_b_in[fifo_wr1]  <= b_vram_in4;	           
           fifo_move_1(); 
         end
       end else begin
         if (FB_H == 1) begin
           fifo_rgb_write[fifo_wr2] <= 1'b0;          
           fifo_rgb_write[fifo_wr3] <= 1'b0;  
           fifo_rgb_write[fifo_wr4] <= 1'b0;  
           fifo_move_1(); 
         end
         if (FB_H == 2) begin           
           fifo_rgb_write[fifo_wr3] <= 1'b0;
           fifo_rgb_write[fifo_wr4] <= 1'b0;
           fifo_move_2(); 
         end  
         if (FB_H == 3) begin                      
           fifo_rgb_write[fifo_wr4] <= 1'b0;
           fifo_move_3(); 
         end  
       end 
       swap_field_at_end_line(3'd4);    
     end
   end
       
        
end

//vga pixels to get full frame
always@(posedge clk_sys) begin  
 if (vga_reset || vram_reset) vga_pixels_frame  <= (H * V) >> FB_interlaced;
end

// both counters count from the begin of the visibla area
// horizontal pixel counter
always@(posedge clk_sys) begin 
 
 if (vga_reset || vga_frame_reset) begin        
        vga_vblanks <= 16'd0;
 end    
 
 if (vga_reset || vga_soft_reset) begin
   h_cnt <= 10'b0;
   _hs   <= 1'b1;
   hb    <= 1'b1;
 end 
 
 if (!interlaced || vga_reset) field <= 1'b0;
 
 if (ce_pix && !vga_reset && !vga_soft_reset) begin                             
        
   if (vga_started && vram_active && h_cnt == H+HFP && v_cnt <= interlaced) vga_vblanks <= vga_vblanks + 1'd1; //frame counter
   if (interlaced  && h_cnt == H+HFP && v_cnt <= interlaced) field <= !field;                                  // change field for interlaced          
  
   if (!vga_reset && !vga_soft_reset) begin
     // horizontal counter  
     if (h_cnt >= H+HFP+HS+HBP-1) h_cnt <= 10'b0;  
      else h_cnt <= h_cnt + 10'b1; 

     // generate negative hsync signal
     if (h_cnt >= H+HFP)    _hs <= 1'b0;   
     if (h_cnt >= H+HFP+HS) _hs <= 1'b1;      
     
     // horizontal blanking     
     if (h_cnt >= H) hb <= 1'b1; 
      else hb <= 1'b0;      
   end     
 end
 
end
        

// vertical pixel counter
always@(posedge clk_sys) begin
  
 if (vga_reset) begin
   v_cnt <= 10'b0;
   _vs   <= 1'b1;
   vb    <= 1'b1;       
 end
 
 //if (!interlaced || vga_reset) field <= 1'b0;
 
 if (vga_soft_reset) begin  
   v_cnt <= (interlaced && !field) ? V+10'd2 : V+10'd1;  
   _vs   <= 1'b1;
   vb    <= 1'b1;       
 end 

 if (ce_pix && !vga_reset && !vga_soft_reset) begin                             
                                                         
   // the vertical counter is processed at the begin of each hsync
   if (h_cnt == H+HFP) begin
     if (v_cnt >= V_total-1) begin                                  //V_total changes on interlaced field by 1             
            v_cnt <= (interlaced && !field) ? 1'b1 : 1'b0;          //vcount depends on field
          end else begin 
            v_cnt <= interlaced ? v_cnt + 10'd2 : v_cnt + 10'd1;    //interlaced alternate 2 lines according to field                         
          end
          
      // blanking signal     
     if (v_cnt >= V) vb <= 1'b1; 
      else vb <= 1'b0;
   end
   
   // negative vsync signal depends from hsync pulse, on interlaced is between 2 hsync edges
   if (h_cnt == H_pulse_start) begin       
     if (v_cnt >= V_pulse_start) _vs <= 1'b0;  //V_pulse_start changes on interlaced field by 1
     if (v_cnt >= V_pulse_end)   _vs <= 1'b1;  //V_pulse_end changes on interlaced field by 1 
   end    
 end    
 
end


// show pixel
always@(posedge clk_sys) begin                                                          
   
   if (vga_reset) begin
     vga_started <= 1'b0;	  
   end	
	
   if (vga_reset || vram_reset) begin         
     vram_wait_vblank  <= 1'b1;       
     vram_out_sync     <= 1'b0;           
     vram_start        <= 1'b0;             
     fifo_ahead        <= 1'b0;
     fifo_rd           <= 3'd0;
     fifo_rd_next	     <= 3'd1;
   end  
        
   if (vga_wait_vblank) vram_wait_vblank <= 1'b1;
	
   fifo_rgb_req[0] <= 1'b0; 
   fifo_rgb_req[1] <= 1'b0; 
   fifo_rgb_req[2] <= 1'b0; 
   fifo_rgb_req[3] <= 1'b0; 
   fifo_rgb_req[4] <= 1'b0; 
   fifo_rgb_req[5] <= 1'b0; 
        
   if (ce_pix) begin  
        
     // non vram output
     if (!vram_active || vga_soft_reset) begin    
       vram_wait_vblank  <= 1'b1;              
       if (vga_de) begin                 
         pixel_counter    <= pixel_counter + 1'd1;
         pixel            <= {r_in, g_in, b_in};                                                                        
       end else begin
         pixel <= 24'h00;   
         if (vb) begin 
           pixel_counter    <= 24'd0; 
           vram_wait_vblank <= 1'b0;                                           
         end    
       end
                  
     // vram output  
     end else begin                                                                                    
     
       fifo_rgb_req[fifo_rd] <= !fifo_ahead && !fifo_rgb_empty[fifo_rd] ? 1'b1 : 1'b0;
       fifo_ahead            <= !fifo_ahead && !fifo_rgb_empty[fifo_rd] ? 1'b1 : fifo_ahead;
		 
       //if (!vram_start && vram_pixel_counter > 24'd0) begin                                                                                                                                  
       if (!vram_start && vram_queue > 24'd0) begin                                                                                                                                  
         vram_start     <= 1'b1; 
         vga_started		  <= 1'b1; 		
         pixel_counter  <= 24'd0;
       end                             
     
       // visible area?              
       if (vga_de && !vram_wait_vblank && vram_start) begin                              
         pixel_counter                <= pixel_counter + 1'd1;  
         if (!fifo_ahead) begin		 
           pixel                      <= {R_NO_VRAM, G_NO_VRAM, B_NO_VRAM};
           vram_out_sync              <= 1'b1;
         end else begin
           pixel                      <= {fifo_rgb_r[fifo_rd], fifo_rgb_g[fifo_rd], fifo_rgb_b[fifo_rd]}; 
           fifo_rgb_req[fifo_rd_next] <= fifo_rgb_empty[fifo_rd_next] ? 1'b0 : 1'b1;
           fifo_ahead                 <= fifo_rgb_empty[fifo_rd_next] ? 1'b0 : 1'b1;
           fifo_rd_next               <= fifo_rd_next == 5 ? 3'd0 : fifo_rd_next + 1'b1;
           fifo_rd                    <= fifo_rd == 5 ? 3'd0 : fifo_rd + 1'b1;
         end		                                                                                                 
       end else begin
         pixel <= 24'h00;  //0v on blanking 		
         if (vb) begin                                             
           pixel_counter    <= 24'd0;                                                      
           vram_wait_vblank <= 1'b0;                                       
         end                             
       end  // no visible area               
     end //vram output       
          
   end // no ce_pix
         
end


endmodule



