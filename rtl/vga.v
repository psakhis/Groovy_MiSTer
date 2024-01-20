
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
   input [7:0]  interlaced,  
   
   input  vram_req,
   input  vram_active,
   input  vram_reset,              
   
   input [7:0] r_vram_in,
   input [7:0] g_vram_in,
   input [7:0] b_vram_in,
        
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

parameter VRAM_SIZE = 18'h1FFB8;

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

reg[23:0] vram_pixel_counter = 24'd0;  // pixels of current frame on all vrams

reg       vram_wait_vblank   = 1'b0;   // waiting vblank to read pixels from vram (soft reset)
reg       vram_out_sync      = 1'b0;   // signal to detect when pixel isn't get from vram
reg       vram_start         = 1'b0;   // start using vram
reg       vga_started        = 1'b0;   // start vblanks counter

assign    vram_ready     = !fifo_rgb_full && fifo_rgb_queue < VRAM_SIZE;  // vram it's ready to write a new pixel
assign    vram_end_frame = vram_pixel_counter >= vga_pixels_frame;        // vram with all frame
assign    vram_pixels    = vram_pixel_counter;                            // number of current pixels writed on vram for a frame
assign    vram_synced    = !vram_out_sync;                                // from point of view vram, synced frame 
assign    vram_queue     = fifo_rgb_queue;                                // pixels prepared to read
assign    vga_pixels     = vga_pixels_frame;                              // pixels to get all frame

///////////////////////// FIFO VRAM ////////////////////////////////////////////
reg[7:0] fifo_rgb_r_in, fifo_rgb_g_in, fifo_rgb_b_in;
wire[7:0] fifo_rgb_r, fifo_rgb_g, fifo_rgb_b;
reg fifo_rgb_req, fifo_rgb_write;
wire fifo_rgb_empty, fifo_rgb_full;
wire[17:0] fifo_rgb_queue;

reg fifo_ahead = 1'b0;

fifo_vga fifo_r(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_r_in),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write),
   .q(fifo_rgb_r),
   .rdempty(fifo_rgb_empty),
   .wrfull(fifo_rgb_full),
   .wrusedw(fifo_rgb_queue)
);

fifo_vga fifo_g(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_g_in),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write),
   .q(fifo_rgb_g),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);

fifo_vga fifo_b(
   .aclr(vram_reset | vga_reset),    
   .data(fifo_rgb_b_in),
   .rdclk(clk_sys),
   .rdreq(fifo_rgb_req),
   .wrclk(clk_sys),
   .wrreq(fifo_rgb_write),
   .q(fifo_rgb_b),
   .rdempty(),
   .wrfull(),
   .wrusedw()
);


// write pixel of fifo
always@(posedge clk_sys) begin                             
   		
   if (vga_reset || vram_reset) begin    
     vram_pixel_counter  <= 24'd0;                                                                                                                               
   end            
   
   fifo_rgb_write <= 1'b0;  	
                               
   if (vram_req) begin    	
     vram_pixel_counter <= vram_end_frame ? 24'd1 : (vram_pixel_counter + 1'd1);                    
     fifo_rgb_r_in      <= r_vram_in;
     fifo_rgb_g_in      <= g_vram_in;
     fifo_rgb_b_in      <= b_vram_in;	  
     fifo_rgb_write     <= 1'b1;       		
   end            
        
end

//vga pixels to get full frame
always@(posedge clk_sys) begin 
 if (vga_reset || vram_reset) vga_pixels_frame  <= (H * V) >> interlaced;
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
   end  
        
   if (vga_wait_vblank) vram_wait_vblank <= 1'b1;
	
	fifo_rgb_req  <= 1'b0; 
        
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
     
       fifo_rgb_req  <= !fifo_ahead && !fifo_rgb_empty ? 1'b1 : 1'b0;
	    fifo_ahead    <= !fifo_ahead && !fifo_rgb_empty ? 1'b1 : fifo_ahead;
		 
       if (!vram_start && vram_pixel_counter > 24'd0) begin                                                                                                                                  
         vram_start       <= 1'b1; 
         vga_started		  <= 1'b1; 		
         pixel_counter    <= 24'd0;
       end                             
     
       // visible area?              
       if (vga_de && !vram_wait_vblank && vram_start) begin                              
         pixel_counter <= pixel_counter + 1'd1;  
         if (!fifo_ahead) begin		 
           pixel         <= {R_NO_VRAM, G_NO_VRAM, B_NO_VRAM};
           vram_out_sync <= 1'b1;
         end else begin
           pixel         <= {fifo_rgb_r, fifo_rgb_g, fifo_rgb_b}; 
           fifo_rgb_req  <= fifo_rgb_empty ? 1'b0 : 1'b1;
			  fifo_ahead    <= fifo_rgb_empty ? 1'b0 : 1'b1;
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



