
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

parameter VRAM_SIZE = 16'hFFFE; //HFFFF - 1

///////////////////////////////////////////////////////////////////////////////

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
reg       vram_init_rd = 1'b0;         // for reset, initialize defaults
reg       vram_init_wr = 1'b0;         // for reset, initialize defaults
reg[15:0] vram_addr_rd[2];             // pointer to vram pixel 
reg       vram_rd_select = 1'd0;       // current vram reader
reg[15:0] vram_addr_wr[2];             // pointer to vram writer
reg       vram_wr_select = 1'd0;       // current vram writer
reg       vram_write[2];               // write enable for vram
reg       vram_dirty[2];               // pointer to vram used and safe to clean   
reg       vram_dirty_select = 1'd0;    // vram to clean

reg       vram_wait_vblank = 1'b0;     // waiting vblank to read pixels from vram (soft reset)
reg       vram_out_sync = 1'b0;        // signal to detect when pixel isn't get from vram
reg       vram_start = 1'b0;           // start using vram


wire      vram_free[2];  
assign    vram_free[0]   = (vram_addr_wr[0] < VRAM_SIZE);                 // vram 0 isn't full
assign    vram_free[1]   = (vram_addr_wr[1] < VRAM_SIZE);                 // vram 1 isn't full
assign    vram_ready     = (vram_free[0] || vram_free[1]);                // vram it's ready to write a new pixel
assign    vram_end_frame = vram_pixel_counter >= ((H * V) >> interlaced); // vram with all frame
assign    vram_pixels    = vram_pixel_counter;                            // number of current pixels writed on vram for a frame
assign    vram_synced    = !vram_out_sync;                                // from point of view vram, synced frame

wire [23:0] vram_pixels_queue[2];
assign    vram_pixels_queue[0] = vram_addr_wr[0] >= vram_addr_rd[0] ? vram_addr_wr[0] - vram_addr_rd[0] + 24'd1 : 24'd0;
assign    vram_pixels_queue[1] = vram_addr_wr[1] >= vram_addr_rd[1] ? vram_addr_wr[1] - vram_addr_rd[1] + 24'd1 : 24'd0;  
assign    vram_queue           = vram_pixels_queue[0] + vram_pixels_queue[1]; //pixels prepared to read

wire[7:0] vram_rgb_r[2];
wire[7:0] vram_rgb_g[2];
wire[7:0] vram_rgb_b[2];

wire[7:0] vram_frame[2];

///////////////////////// VRAM ////////////////////////////////////////////
vram vram_r_ch0(        
        .data(r_vram_in), // 8 bit
        .wraddress(vram_addr_wr[0]), // 16 bit
        .wren(vram_write[0]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[0]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_r[0]) // 8 bit
);

vram vram_r_ch1(        
        .data(r_vram_in), // 8 bit
        .wraddress(vram_addr_wr[1]), // 16 bit
        .wren(vram_write[1]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[1]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_r[1]) // 8 bit
);

vram vram_g_ch0(        
        .data(g_vram_in), // 8 bit
        .wraddress(vram_addr_wr[0]), // 16 bit
        .wren(vram_write[0]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[0]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_g[0]) // 8 bit
);

vram vram_g_ch1(        
        .data(g_vram_in), // 8 bit
        .wraddress(vram_addr_wr[1]), // 16 bit
        .wren(vram_write[1]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[1]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_g[1]) // 8 bit
);

vram vram_b_ch0(        
        .data(b_vram_in), // 8 bit
        .wraddress(vram_addr_wr[0]), // 16 bit
        .wren(vram_write[0]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[0]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_b[0]) // 8 bit
);

vram vram_b_ch1(
        .data(b_vram_in), // 8 bit
        .wraddress(vram_addr_wr[1]), // 16 bit
        .wren(vram_write[1]),
        .wrclock(clk_sys), //
        .rdaddress(vram_addr_rd[1]),    
        .rdclock(clk_sys), //
        .q(vram_rgb_b[1]) // 8 bit
);
 
// vram write
always@(posedge clk_sys) begin                             
        
   if (!vram_init_wr || vram_reset) begin
     vram_addr_wr[0]     <= 16'd0;  
     vram_addr_wr[1]     <= 16'd0;      
     vram_wr_select      <= 1'd0;
     vram_pixel_counter  <= 24'd0;                                                                                                               
     vram_dirty_select   <= 1'd0;                             
     vram_init_wr        <= 1'b1;              
   end            
        
   vram_write[0] <= 1'b0;
   vram_write[1] <= 1'b0;                       
   
   // write vram and swap if fulled 
   if (vram_ready && vram_req) begin    
	
      vram_pixel_counter <= vram_end_frame ? 24'd1 : (vram_pixel_counter + 1'd1);                    
      
      if (!vram_free[vram_wr_select]) begin
        vram_addr_wr[~vram_wr_select] <= vram_addr_wr[~vram_wr_select] + 1'd1;              
        vram_write[~vram_wr_select]   <= 1'b1;               
        vram_wr_select <= ~vram_wr_select;
      end else begin
        vram_addr_wr[vram_wr_select]  <= vram_addr_wr[vram_wr_select] + 1'd1;
        vram_write[vram_wr_select]    <= 1'b1;               
      end    
		
   end          

   // clean alternating vram
   if (vram_dirty[vram_dirty_select]) begin
     vram_addr_wr[vram_dirty_select] <= 16'd0;
     vram_dirty_select <= ~vram_dirty_select;        
   end     
        
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
        
   if (vram_active && vram_start && h_cnt == H+HFP && v_cnt <= interlaced) vga_vblanks <= vga_vblanks + 1'd1; //frame counter
   if (interlaced  && h_cnt == H+HFP && v_cnt <= interlaced) field <= !field;                                 // change field for interlaced          
  
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
        
   // initialize array (in SystemVerilog can initialized as literal/aggregate, not in verilog)    
   if (!vram_init_rd || vram_reset) begin
     vram_addr_rd[0]   <= 16'd1;  
     vram_addr_rd[1]   <= 16'd1;                        
     vram_dirty[0]     <= 1'b0;
     vram_dirty[1]     <= 1'b0;      
     vram_rd_select    <= 1'd0;              
     vram_wait_vblank  <= 1'b1;       
     vram_out_sync     <= 1'b0;           
     vram_start        <= 1'b0;     
     vram_init_rd      <= 1'b1;     
   end  
        
   if (vga_wait_vblank) vram_wait_vblank <= 1'b1;
        
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
                                                                                                                            
     if (!vram_start && vram_pixel_counter > 24'd0) begin                                                                                                                                  
       vram_start       <= 1'b1;                                                               
       pixel_counter    <= 24'd0;
     end                             
     
     // visible area?              
     if (vga_de && !vram_wait_vblank && vram_start) begin  
                            
       pixel_counter <= pixel_counter + 1'd1;                  
       // get vram pixel and swap if needed for next read
       pixel <= vram_addr_rd[vram_rd_select] <= vram_addr_wr[vram_rd_select] ? {vram_rgb_r[vram_rd_select],vram_rgb_g[vram_rd_select],vram_rgb_b[vram_rd_select]} : {R_NO_VRAM,G_NO_VRAM,B_NO_VRAM};                           
       if (vram_addr_rd[vram_rd_select] > vram_addr_wr[vram_rd_select]) vram_out_sync <= 1'b1;
       if (vram_addr_rd[vram_rd_select] + 1'd1 > VRAM_SIZE) begin
         vram_dirty[vram_rd_select]   <= 1'b1;                                
         vram_dirty[~vram_rd_select]  <= 1'b0;
         vram_addr_rd[vram_rd_select] <= 16'd1;
         vram_rd_select               <= ~vram_rd_select;
       end else                          
         vram_addr_rd[vram_rd_select] <= vram_addr_rd[vram_rd_select] + 1'd1;                         
                                                                                            
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



