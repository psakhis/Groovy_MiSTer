//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
   //Master input clock
   input         CLK_50M,

   //Async reset from top-level module.
   //Can be used as initial reset.
   input         RESET,

   //Must be passed to hps_io module
   inout  [48:0] HPS_BUS,

   //Base video clock. Usually equals to CLK_SYS.
   output        CLK_VIDEO,

   //Multiple resolutions are supported using different CE_PIXEL rates.
   //Must be based on CLK_VIDEO
   output        CE_PIXEL,

   //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
   //if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
   output [12:0] VIDEO_ARX,
   output [12:0] VIDEO_ARY,

   output  [7:0] VGA_R,
   output  [7:0] VGA_G,
   output  [7:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,
   output        VGA_DE,    // = ~(VBlank | HBlank)
   output        VGA_F1,
   output [1:0]  VGA_SL,
   output        VGA_SCALER, // Force VGA scaler
   output        VGA_DISABLE, // analog out is off

   input  [11:0] HDMI_WIDTH,
   input  [11:0] HDMI_HEIGHT,
   output        HDMI_FREEZE,
   output        HDMI_BLACKOUT,

`ifdef MISTER_FB
   // Use framebuffer in DDRAM
   // FB_FORMAT:
   //    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
   //    [3]   : 0=16bits 565 1=16bits 1555
   //    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
   //
   // FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
   output        FB_EN,
   output  [4:0] FB_FORMAT,
   output [11:0] FB_WIDTH,
   output [11:0] FB_HEIGHT,
   output [31:0] FB_BASE,
   output [13:0] FB_STRIDE,
   input         FB_VBL,
   input         FB_LL,
   output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
   // Palette control for 8bit modes.
   // Ignored for other video modes.
   output        FB_PAL_CLK,
   output  [7:0] FB_PAL_ADDR,
   output [23:0] FB_PAL_DOUT,
   input  [23:0] FB_PAL_DIN,
   output        FB_PAL_WR,
`endif
`endif

   output        LED_USER,  // 1 - ON, 0 - OFF.

   // b[1]: 0 - LED status is system status OR'd with b[0]
   //       1 - LED status is controled solely by b[0]
   // hint: supply 2'b00 to let the system control the LED.
   output  [1:0] LED_POWER,
   output  [1:0] LED_DISK,

   // I/O board button press simulation (active high)
   // b[1]: user button
   // b[0]: osd button
   output  [1:0] BUTTONS,

   input         CLK_AUDIO, // 24.576 MHz
   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,
   output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
   output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

   //ADC
   inout   [3:0] ADC_BUS,

   //SD-SPI
   output        SD_SCK,
   output        SD_MOSI,
   input         SD_MISO,
   output        SD_CS,
   input         SD_CD,

   //High latency DDR3 RAM interface
   //Use for non-critical time purposes
   output        DDRAM_CLK,
   input         DDRAM_BUSY,
   output  [7:0] DDRAM_BURSTCNT,
   output [28:0] DDRAM_ADDR,
   input  [63:0] DDRAM_DOUT,
   input         DDRAM_DOUT_READY,
   output        DDRAM_RD,
   output [63:0] DDRAM_DIN,
   output  [7:0] DDRAM_BE,
   output        DDRAM_WE,

   //SDRAM interface with lower latency
   output        SDRAM_CLK,
   output        SDRAM_CKE,
   output [12:0] SDRAM_A,
   output  [1:0] SDRAM_BA,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nCS,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
   //Secondary SDRAM
   //Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
   input         SDRAM2_EN,
   output        SDRAM2_CLK,
   output [12:0] SDRAM2_A,
   output  [1:0] SDRAM2_BA,
   inout  [15:0] SDRAM2_DQ,
   output        SDRAM2_nCS,
   output        SDRAM2_nCAS,
   output        SDRAM2_nRAS,
   output        SDRAM2_nWE,
`endif

   input         UART_CTS,
   output        UART_RTS,
   input         UART_RXD,
   output        UART_TXD,
   output        UART_DTR,
   input         UART_DSR,

   // Open-drain User port.
   // 0 - D+/RX
   // 1 - D-/TX
   // 2..6 - USR2..USR6
   // Set USER_OUT to 1 to read from USER_IN.
   input   [6:0] USER_IN,
   output  [6:0] USER_OUT,

   input         OSD_STATUS,
   
   output        PWM_EN          //wait to see on framework someday
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
//assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = PoC_interlaced && !PoC_FB_interlaced ? 1'b0 : scandoubler_fx;
//assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_S = hps_audio ? 1'b1 : 1'b0;
assign AUDIO_L = hps_audio ? sound_l_out : 1'b0;
assign AUDIO_R = hps_audio ? sound_r_out : 1'b0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

assign PWM_EN = hps_pwm;
//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[2:1];
wire [1:0] scandoubler_fx = status[4:3];
wire [1:0] scale = status[6:5];

//assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
//assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
   "Groovy;;",
   "-;",   
   "FC1,GMC,Load Gmc;",
   "-;",  
   "P1,Video Settings;",
   "P1O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
   "P1O[4:3],Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",  
   "P1O[6:5],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
   "-;",           
   "P1O[10],Orientation,Horz,Vert;",
   "P1-;",
   "d1P1O[11],240p Crop,Off,On;",
   "d2P1O[16:12],Crop Offset,0,1,2,3,4,5,6,7,8,-8,-7,-6,-5,-4,-3,-2,-1;",     
   "P1-;",  
   "P1O[21:17],Analog video H-Pos,0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12,-13,-14,-15,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1;",  
   "P1O[26:22],Analog video V-Pos,0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12,-13,-14,-15,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1;",  
   "P1-;",
   "P1O[32],Volatile framebuffer,Off,On;", 
   "P1O[37],PWM,Off,On;",
   "P2,Audio Settings;",
   "P2O[34],Audio,Off,On;",
   "P2O[36:35],Desired buffer (ms),0,16,32,64;",   
   "-;",
   "P3,Server Settings (restart);",
   "P3O[28:27],Verbose,Off,1,2,3;",
   "P3O[29],Blit at,ASAP,End Line;",       
   "P3O[42],Jumbo frames (Max MTU),Off,On;",
   //"P3O[43],Server type,UDP,XDP;",
   "P3O[45:44],ARM clock,Stock,+200Mhz,+400Mhz;",
   "P3-;",
   "P3O[33],Screensaver,On,Off;",   
   "P3-;",
   "P3O[39:38],Send PS2,Off,Keyboard,Keyboard & Mouse;",
   "P3O[41:40],Send Joysticks,Off,Digital,Analog;",
   "-;",
   "J1,Button 1,Button 2,Button 3,Button 4,Button 5,Button 6,Button 7,Button 8, Button 9, Button 10;",        
   "J2,Button 1,Button 2,Button 3,Button 4,Button 5,Button 6,Button 7,Button 8, Button 9, Button 10;",  
   //"-;",
   //"-;",
   //"T[0],Reset;",
   //"R[0],Reset and close OSD;",  
   //"v,0;", // [optional] config version 0-99. 
      // If CONF_STR options are changed in incompatible way, then change version number too,
      // so all options will get default values on first start.    
   "V,v",`BUILD_DATE
};

//
// HPS is the module that communicates between the linux and fpga
//
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated = 0;
wire        no_rotate = ~status[10];

wire        allow_crop_240p = ~forced_scandoubler && scale == 0;
wire        crop_240p = allow_crop_240p & status[11];
wire [4:0]  crop_offset = status[16:12] < 9 ? {status[16:12]} : ( status[16:12] + 5'd15 );

wire [1:0]  hps_verbose = status[28:27];
wire        hps_blit = status[29];
wire        hps_volatile_fb = status[32];
wire        hps_screensaver = status[33];
wire        hps_frameskip = !hps_volatile_fb;
wire        hps_audio = status[34];
wire [1:0]  hps_audio_buffer = status[36:35];
wire        hps_pwm = status[37];
wire [1:0]  hps_kbd_inputs = status[39:38];
wire [1:0]  hps_joy_inputs = status[41:40];
wire        hps_jumbo_frames = status[42];
//wire        hps_server_type = status[43];
reg         hps_server_type = 1'b0;
wire [1:0]  hps_arm_clock = status[45:44];

wire [46:0] status;
wire [31:0] joy0;
wire [31:0] joy1;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
   .clk_sys(clk_sys),
   .HPS_BUS(HPS_BUS),
   .EXT_BUS(EXT_BUS),
   .gamma_bus(gamma_bus),
   .direct_video(direct_video),
 
   .forced_scandoubler(forced_scandoubler),
   .new_vmode(new_vmode),
   .video_rotated(video_rotated),
 
   .buttons(buttons),
   .status(status),
   .status_menumask({crop_240p, allow_crop_240p, direct_video}),
        
   .joystick_0(joy0),
   .joystick_1(joy1)
     
);

////////////////////////////  HPS I/O  EXT ///////////////////////////////////

wire [35:0] EXT_BUS;
reg  reset_switchres = 0, vga_frameskip = 0, vga_frameskip_prev = 0, reset_blit = 0, auto_blit = 0, reset_audio = 0, cmd_fskip = 0, reset_blit_lz4 = 0, auto_blit_lz4 = 0; 
wire cmd_init, cmd_switchres, cmd_blit, cmd_logo, cmd_audio, cmd_blit_lz4; 
wire [15:0] audio_samples;
wire [1:0] sound_rate, sound_chan, rgb_mode, lz4_field, lz4_ABCD;
wire [31:0] lz4_size, switchres_frame;

/*
wire [23:0] blit_frame, blit_pixels, blit_bytes;
wire [15:0] blit_num;
wire blit_field;
*/

hps_ext hps_ext
(
        .clk_sys(clk_sys),
        .EXT_BUS(EXT_BUS),
        .state(state),
        .hps_rise(1'b1),        
        .hps_verbose(hps_verbose),
        .hps_blit(hps_blit),
        .hps_screensaver(hps_screensaver),
        .hps_kbd_inputs(hps_kbd_inputs),
        .hps_joy_inputs(hps_joy_inputs),
        .hps_audio(hps_audio),  
        .hps_jumbo_frames(hps_jumbo_frames),
        .hps_server_type(hps_server_type),
        .hps_arm_clock(hps_arm_clock),
        .sound_rate(sound_rate),
        .sound_chan(sound_chan),
        .rgb_mode(rgb_mode),     
        .vga_frameskip(vga_frameskip | (vga_frameskip_prev & vblank_core)),      
        .vga_vcount(vga_vcount), 
        .vga_frame(vga_frame),
        .vga_vblank(vblank_core),
        .vga_f1(VGA_F1),                  
        .vram_pixels(vram_pixels),  
        .vram_queue(vram_queue),                 
        .vram_synced(vram_synced),     
        .vram_end_frame(vram_end_frame),             
        .vram_ready(vram_req_ready),
        .cmd_init(cmd_init),      
        .reset_switchres(reset_switchres),
        .cmd_switchres(cmd_switchres),
        .switchres_frame(switchres_frame),
        .reset_blit(reset_blit),
        .cmd_blit(cmd_blit),
        .cmd_logo(cmd_logo),
        .cmd_audio(cmd_audio),
        .reset_audio(reset_audio),
        .audio_samples(audio_samples),
        .reset_blit_lz4(reset_blit_lz4),
        .cmd_blit_lz4(cmd_blit_lz4),
        .lz4_size(lz4_size),
        .lz4_ABCD(lz4_ABCD),
        .lz4_field(lz4_field),
        .lz4_uncompressed_bytes(lz4_uncompressed_bytes)
/* debug 
         .blit_frame(blit_frame),
        .blit_pixels(blit_pixels),
        .blit_bytes(blit_bytes),
        .blit_num(blit_num),
        .blit_field(blit_field),
        .PoC_subframe_wr_bytes(PoC_subframe_wr_bytes),                    
        .lz4_run(lz4_run),     
        .PoC_lz4_resume(PoC_lz4_resume_blit),               
        .PoC_test1(PoC_test1),            
        .PoC_test2(PoC_test2),                
        .cmd_fskip(cmd_fskip),                                       
        .lz4_stop(lz4_stop),
        .PoC_lz4_ABCD(PoC_lz4_ABCD),        
        .lz4_compressed_bytes(lz4_compressed_bytes),        
        .lz4_gravats(lz4_writed_bytes),     
        .lz4_llegits(lz4_readed_bytes),                                          
        .PoC_subframe_lz4_bytes(PoC_subframe_lz4_ddr_bytes),               
        .PoC_subframe_blit_lz4(PoC_subframe_blit_lz4) */                      
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, pll_locked;

pll pll
(
  .refclk(CLK_50M),
  .rst(0),
  .outclk_0(clk_sys),  
  .locked(pll_locked),
  .reconfig_to_pll(reconfig_to_pll),
  .reconfig_from_pll(reconfig_from_pll)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
    .mgmt_clk(CLK_50M),
    .mgmt_reset(0),
    .mgmt_waitrequest(cfg_waitrequest),
    .mgmt_read(0),
    .mgmt_readdata(),
    .mgmt_write(cfg_write),
    .mgmt_address(cfg_address),
    .mgmt_writedata(cfg_data),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);


localparam PLL_PARAM_F_COUNT = 7;

wire [31:0] PLL_ARM_F[PLL_PARAM_F_COUNT * 2] = '{
    'h0, 'h0, // set waitrequest mode
    'h4, {16'b00, PoC_pll_F_M0, PoC_pll_F_M1}, // M COUNTER 2'b10 + 8bit (High) + 8bit (Low)    
    'h3, {16'b01, 16'b00}, // N COUNTER 8bit (High) + 8bit (Low) (always 256/256)
    'h5, {16'b00, PoC_pll_F_C0, PoC_pll_F_C1}, // C COUNTER 8bit (High) + 8bit (Low)   
    'h7, PoC_pll_F_K, // K FRACTIONAL
    'h8, 'h6, // BANDWIDTH SETTING (auto)        
    'h2, 'h0  // start reconfigure
};


//reg reconfig_pause = 0;
reg req_modeline = 0;
reg new_modeline = 0;
reg new_vmode = 0; // notify to OSD

always @(posedge CLK_50M) begin
    reg [3:0] param_idx = 0;
    reg [7:0] reconfig = 0;

    cfg_write <= 0;

    if (pll_locked & ~cfg_waitrequest) begin
      //pll_init_locked <= 1;
      if (&reconfig) begin // do reconfig              
        cfg_address <= PLL_ARM_F[param_idx * 2 + 0][5:0];
        cfg_data    <= PLL_ARM_F[param_idx * 2 + 1];                                            
        cfg_write <= 1;
        param_idx <= param_idx + 4'd1;
        if (param_idx == PLL_PARAM_F_COUNT - 1) reconfig <= 8'd0;
      end else if (req_modeline != new_modeline) begin // new timing requested
        new_modeline <= req_modeline;
        reconfig <= 8'd1;
        //reconfig_pause <= 1;
        param_idx <= 0;
      end else if (|reconfig) begin // pausing before reconfigure
        reconfig <= reconfig + 8'd1;
      end// else begin
      //    reconfig_pause <= 0; // unpause once pll is locked again
      // end
    end
end

//reg pll_init_locked = 0;
//wire reset = RESET | buttons[1] | ~pll_init_locked;
//wire reset = RESET | status[0] | buttons[1];

/////////////////////// PIXEL CLOCK/////////////////////////////////////

wire ce_pix;

reg [7:0] ce_pix_arm;
assign ce_pix_arm = cmd_scandoubler && PoC_pll_S ? (PoC_ce_pix >> 1) - 1'd1 : PoC_ce_pix - 1'd1; 

reg [3:0] cencnt = 4'd0;

always @(posedge clk_sys) begin     
         cencnt <= cencnt==ce_pix_arm ? 4'd0 : (cencnt+4'd1);    
end

always @(posedge clk_sys) begin
    ce_pix <= cencnt == 4'd0;  
end

reg cmd_scandoubler = 1'b0; 
always @(posedge clk_sys) begin
    cmd_scandoubler <= (forced_scandoubler || scandoubler_fx != 2'b00) && PoC_interlaced && !PoC_FB_interlaced ? 1'b1 : 1'b0;   
end



////////////////////////////  MEMORY  ///////////////////////////////////
//
//

////////////////////////////  DDRAM  ///////////////////////////////////
parameter DDR_SW_HEADER   = 28'd8; 
parameter DDR_LZ_HEADER   = 28'd32; 
parameter DDR_FB_OFFSET   = 28'hff; 
parameter DDR_AB_OFFSET   = 28'h32a0ff; 
parameter DDR_FD_OFFSET   = 28'h1950ff; 
parameter DDR_LZ_OFFSET_A = 28'h3320ff; 
parameter DDR_LZ_OFFSET_B = 28'h4c70ff; 
parameter DDR_LZ_OFFSET_C = 28'h65c0ff; 
parameter DDR_LZ_OFFSET_D = 28'h7f10ff; 

assign DDRAM_CLK = clk_sys;

wire [63:0]  ddr_data;
reg          ddr_data_req=1'b0;
reg  [27:0]  ddr_addr={18'b0,10'b0111111000}; //0x6000000 for read 0x30000000 (chunk 8 bytes, last 3 bits)      
wire         ddr_data_ready;
wire         ddr_busy;
reg          ddr_data_write=1'b0;
reg[7:0]     ddr_burst = 8'd1;
reg[255:0]   ddr_data_tmp = 256'd0;
reg[1:0]     ddr_data_idx = 2'd0;

reg  [63:0]  ddr_data_to_write={8'h00,8'h00,8'h00,8'h00,8'h00,8'h73,8'h65,8'h72};


ddram ddram
(
        .*,   
        .mem_addr(ddr_addr[27:1]),
        .mem_dout(ddr_data),               
        .mem_din(ddr_data_to_write),                    
        .mem_rd(ddr_data_req),       
        .mem_burst(ddr_burst),             
        .mem_wr(ddr_data_write),                  
        .mem_busy(ddr_busy),
        .mem_dready(ddr_data_ready)                
      
);

///////////////////////////////////////////////////////////////////////////
//
//                       TASKS
//
///////////////////////////////////////////////////////////////////////////

task decode_pixel;
  input       drive_lz4;
  input[63:0] word64; 
  input[23:0] total_pixels; 
  begin  
   case (rgb_mode)
   2'd2: // RGB565
   begin
    if (total_pixels - PoC_subframe_px_vram > 3) begin 
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;       
      vram_wren3 <= 1'b1;
      vram_wren4 <= 1'b1;
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd4;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd4;                                              
    end else     
    if (total_pixels - PoC_subframe_px_vram > 2) begin 
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;       
      vram_wren3 <= 1'b1;     
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd3;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd3;                                              
    end else     
    if (total_pixels - PoC_subframe_px_vram > 1) begin 
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;                
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd2;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd2;                                              
    end else                 
    if (total_pixels - PoC_subframe_px_vram > 0) begin          
      vram_wren1 <= 1'b1;                       
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd1;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd1;                 
    end
    b_vram_in1 <= {word64[00 +: 05], word64[00 +: 03]};
    b_vram_in2 <= {word64[16 +: 05], word64[16 +: 03]};
    b_vram_in3 <= {word64[32 +: 05], word64[32 +: 03]};
    b_vram_in4 <= {word64[48 +: 05], word64[48 +: 03]};
    g_vram_in1 <= {word64[05 +: 06], word64[05 +: 02]};
    g_vram_in2 <= {word64[21 +: 06], word64[21 +: 02]};
    g_vram_in3 <= {word64[37 +: 06], word64[37 +: 02]};
    g_vram_in4 <= {word64[53 +: 06], word64[53 +: 02]};
    r_vram_in1 <= {word64[11 +: 05], word64[11 +: 03]};
    r_vram_in2 <= {word64[27 +: 05], word64[27 +: 03]};
    r_vram_in3 <= {word64[43 +: 05], word64[43 +: 03]};
    r_vram_in4 <= {word64[59 +: 05], word64[59 +: 03]};
   end       
   2'd1: // RGBA888
   begin
    if (total_pixels - PoC_subframe_px_vram > 1) begin 
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;      
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd2;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd2;                                              
    end else                 
    if (total_pixels - PoC_subframe_px_vram > 0) begin          
      vram_wren1 <= 1'b1;                       
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd1;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd1;                 
    end
    {r_vram_in1, g_vram_in1, b_vram_in1} <= word64[00 +:24];
    {r_vram_in2, g_vram_in2, b_vram_in2} <= word64[32 +:24];                          
   end
   default: //RGB888
   begin    
    PoC_frame_rgb_offset <= PoC_frame_rgb_offset == 2 ? 2'd0 : PoC_frame_rgb_offset + 1'b1; 
    // how many pixels to save          
    if (total_pixels - PoC_subframe_px_vram > 2 && PoC_frame_rgb_offset != 0) begin 
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;
      vram_wren3 <= 1'b1;
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd3;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd3;                                              
    end else              
    if (total_pixels - PoC_subframe_px_vram > 1) begin
      vram_wren1 <= 1'b1;
      vram_wren2 <= 1'b1;   
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd2;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd2;                                                                      
    end else 
    if (total_pixels - PoC_subframe_px_vram > 0) begin          
      vram_wren1 <= 1'b1;                       
      if (drive_lz4) PoC_subframe_px_lz4 <= PoC_subframe_px_lz4 + 24'd1;
      PoC_subframe_px_vram               <= PoC_subframe_px_vram + 24'd1;                 
    end                 
    // calculate ddr pixels : offsets 64 + 64 + 64 = 48 + 72 + 64     
    case (PoC_frame_rgb_offset)  
      2'd0: 
      begin
        {r_vram_in1, g_vram_in1, b_vram_in1} <= word64[00 +:24];
        {r_vram_in2, g_vram_in2, b_vram_in2} <= word64[24 +:24];  
        ddr_data_tmp[00 +: 16]               <= word64[48 +:16];                  
      end
      2'd1: 
      begin
        {r_vram_in1, g_vram_in1, b_vram_in1} <= {word64[00 +:08], ddr_data_tmp[00 +: 16]};
        {r_vram_in2, g_vram_in2, b_vram_in2} <= word64[08 +:24];  
        {r_vram_in3, g_vram_in3, b_vram_in3} <= word64[32 +:24];  
        ddr_data_tmp[00 +: 08]               <= word64[56 +:08];                                          
      end
      2'd2: 
      begin
        {r_vram_in1, g_vram_in1, b_vram_in1} <= {word64[00 +:16], ddr_data_tmp[00 +: 08]};
        {r_vram_in2, g_vram_in2, b_vram_in2} <= word64[16 +:24];  
        {r_vram_in3, g_vram_in3, b_vram_in3} <= word64[40 +:24];                                                   
      end   
    endcase      
   end
  endcase
 end
endtask


///////////////////////////////////////////////////////////////////////////
//
//                        MAIN FLOW
//
///////////////////////////////////////////////////////////////////////////
// States
parameter S_Idle                  = 8'd00; 
parameter S_Dispatcher            = 8'd01; 
parameter S_Defaults              = 8'd90; 
parameter S_Reset                 = 8'd91; 

// Raw Blit 
parameter S_Blit_Header_Raw       = 8'd20; 
parameter S_Blit_Raw              = 8'd21; 
parameter S_Blit_Prepare_Raw      = 8'd22; 
parameter S_Blit_Copy_Raw         = 8'd23; 
parameter S_Blit_End_Raw          = 8'd24; 

//parameter S_Blit_Pixels_Raw       = 8'd25; 

// FrameSkip (non Volatile)
parameter S_Blit_Auto_Skip        = 8'd26; 
parameter S_Blit_Auto_First       = 8'd27; 
parameter S_Blit_Auto_Line        = 8'd28; 
parameter S_Blit_Auto_End         = 8'd29; 

// Switchres
parameter S_Switchres_Header      = 8'd30; 
parameter S_Switchres_PLL         = 8'd31; 
parameter S_Switchres_Mode        = 8'd32; 
parameter S_Switchres_Scandoubler = 8'd33;

// LZ4 Blit
parameter S_Blit_Header_Lz4       = 8'd50; 
parameter S_Blit_Lz4              = 8'd51; 
parameter S_Blit_Prepare_Lz4      = 8'd52;
parameter S_Blit_Copy_Lz4         = 8'd53;
parameter S_Blit_Copy_End_Lz4     = 8'd54;
parameter S_Blit_Inflate_Lz4      = 8'd55;
parameter S_Blit_End_Lz4          = 8'd56;

// Audio
parameter S_Audio_Prepare         = 8'd60; 
parameter S_Audio_Copy            = 8'd61; 
parameter S_Audio_End             = 8'd62; 

/////////////////////////// REGS ////////////////////////////////////////////
  
reg [7:0] state     = S_Idle;  

// Header from arm
reg [31:0] PoC_frame_ddr       = 32'd0;
reg [15:0] PoC_subframe_bl_ddr = 16'd0;
reg [23:0] PoC_subframe_px_ddr = 24'd0;

// Modeline from arm (default 256x240 sms)
reg [15:0] PoC_H          = 16'd256;
reg [7:0]  PoC_HFP        = 8'd10;
reg [7:0]  PoC_HS         = 8'd24;
reg [7:0]  PoC_HBP        = 8'd41;
reg [15:0] PoC_V          = 16'd240;
reg [7:0]  PoC_VFP        = 8'd2;
reg [7:0]  PoC_VS         = 8'd3;
reg [7:0]  PoC_VBP        = 8'd16;

// PLL (default 60hz for sms)
reg [7:0]  PoC_pll_F_M0   = 8'd4;
reg [7:0]  PoC_pll_F_M1   = 8'd4;
reg [7:0]  PoC_pll_F_C0   = 8'd3;
reg [7:0]  PoC_pll_F_C1   = 8'd2;
reg [31:0] PoC_pll_F_K    = 32'd1182682725;
reg [7:0]  PoC_ce_pix     = 8'd16;

reg        PoC_pll_S      = 1'b0; //scandoubler 480i

// Interlaced
reg        PoC_interlaced = 1'b0;
reg        PoC_FB_interlaced = 1'b0;

// Current frame on vram
reg [31:0] PoC_frame_vram = 32'd0;

// Pixels writed on current frame for subframe updates 
reg [23:0] PoC_subframe_px_vram = 24'd0;
reg [15:0] PoC_subframe_bl_vram = 16'd0;

reg [23:0] PoC_px_frameskip    = 24'd0;
reg [7:0]  PoC_state_frameskip = 8'd0;

reg [23:0] PoC_frame_switchres = 24'd0;
reg [1:0]  PoC_frame_rgb_offset = 2'd0;

reg [27:0] PoC_subframe_ddr_bytes  = 28'd0;
reg [27:0] PoC_subframe_vram_bytes = 28'd0;

// Audio stuff
reg [15:0] PoC_audio_samples = 16'd0;
reg [15:0] PoC_audio_count = 16'd0;
reg [23:0] PoC_audio_ddr_bytes = 24'd0;
reg [23:0] PoC_audio_count_bytes = 24'd0;

// LZ4 stuff
reg [1:0]  PoC_lz4_ABCD = 2'd0;
reg [1:0]  PoC_lz4_field = 2'd0;
reg [23:0] PoC_frame_lz4 = 24'd0;
reg [15:0] PoC_subframe_blit_lz4 = 16'd0;
reg [23:0] PoC_frame_lz4_ddr = 24'd0;
reg [23:0] PoC_subframe_lz4_ddr_bytes = 24'd0;
reg [15:0] PoC_subframe_blit_lz4_ddr = 16'd0;
reg [27:0] PoC_subframe_wr_bytes = 28'd0;

reg        PoC_frame_lz4_FB = 1'b0;
reg        PoC_lz4_resume_blit = 1'b0;
reg        PoC_lz4_resume_audio = 1'b0;
reg [23:0] PoC_subframe_px_lz4 = 24'd0;


// DEBUG 
/*
reg  PoC_test1 = 1'b0;
reg  PoC_test2 = 1'b0;
*/

// Main flow
always @(posedge clk_sys) begin                                                                                                                                                                                                                                                                 
   
  cmd_fskip <= 1'b0;     
  if (!cmd_switchres && vga_frameskip && vblank_core && vga_vcount > PoC_interlaced) begin 
    vga_frameskip       <= 1'b0; 
    vga_frameskip_prev  <= 1'b1;    
  end      
  
  // verify if vram has pixels needed for next line to activate non volatile framebuffer (cmd_fskip)   
  if ((hps_frameskip || cmd_logo) && PoC_frame_vram != 0) begin      
      if (vga_vcount <= PoC_interlaced && vram_queue == 24'd0) begin // raster at the end of frame and vram is empty
        cmd_fskip             <= 1'b1;          
        PoC_state_frameskip   <= S_Blit_Auto_First;     
      end else
      if (!vblank_core) begin
        if (vga_vcount + 1 + PoC_interlaced >= PoC_V && PoC_H > vram_queue && vram_queue + 20 < vram_pixels && vga_pixels > vram_pixels && vram_pixels > (PoC_H << 2)) begin // last line interlaced
            cmd_fskip           <= 1'b1;     
            PoC_state_frameskip <= S_Blit_Auto_End;
        end else
        if (vga_vcount + 1 + PoC_interlaced < PoC_V && PoC_H > vram_queue && vram_queue + 20 < vram_pixels && ((PoC_H * (vga_vcount + 10'd1 + PoC_interlaced)) >> PoC_FB_interlaced) > vram_pixels) begin // next line
            cmd_fskip           <= 1'b1;                 
            PoC_state_frameskip <= S_Blit_Auto_Line;
        end 
      end 
    end 
       

   // case -> only evaluates first match (break implicit), if not then default        
   case (state)
   
         S_Idle: // start?                         
         begin                                           
           {r_in, g_in, b_in}         <= {8'h00,8'h00,8'h00};                                            
           vga_reset                  <= 1'b0;
           vga_frame_reset            <= 1'b1;
           vga_soft_reset             <= 1'b0;
           vga_wait_vblank            <= 1'b0;
           vga_frameskip              <= 1'b0;
           vga_frameskip_prev         <= 1'b0;
           vram_reset                 <= 1'b1;               
           vram_active                <= 1'b0;                                                                                                                                             
           vram_wren1                 <= 1'b0;                         
           vram_wren2                 <= 1'b0;                         
           vram_wren3                 <= 1'b0;
           vram_wren4                 <= 1'b0;
           vram_drive_raw             <= 1'b0; 
           vram_drive_lz4             <= 1'b0;            
             
           ddr_data_write             <= 1'b0;                                                                                                 
           ddr_data_req               <= 1'b0;                                         
           ddr_burst                  <= 8'd1;                      
           ddr_addr                   <= 28'd0;   

           sound_reset                <= 1'b0;
           sound_wren1                <= 1'b0;
           sound_wren2                <= 1'b0;
           sound_wren3                <= 1'b0;
           sound_wren4                <= 1'b0;
           
           PoC_FB_interlaced          <= 1'b0;
           PoC_interlaced             <= 1'b0;
           
           PoC_frame_switchres        <= 24'd0;   
           PoC_subframe_bl_vram       <= 16'd0;                                                 
           PoC_subframe_px_vram       <= 24'd0;                                                 
           PoC_subframe_vram_bytes    <= 28'd0;                                                 
           PoC_frame_vram             <= 32'd0;            
           PoC_frame_ddr              <= 32'd0;           
           PoC_subframe_px_ddr        <= 24'd0;
           PoC_subframe_ddr_bytes     <= 28'd0;                                                    
           PoC_subframe_bl_ddr        <= 16'd0; 
           PoC_frame_rgb_offset       <= 2'd0;
           auto_blit                  <= 1'b0;

           lz4_run                    <= 1'b0;
           lz4_reset                  <= 1'b0;
           lz4_compressed_bytes       <= 32'd0;
           PoC_frame_lz4              <= 24'd0;        
           PoC_subframe_blit_lz4      <= 16'd0;
           PoC_frame_lz4_ddr          <= 24'd0;
           PoC_subframe_lz4_ddr_bytes <= 24'd0;       
           PoC_subframe_blit_lz4_ddr  <= 16'd0;
           PoC_subframe_wr_bytes      <= 28'd0;        
           PoC_frame_lz4_FB           <= 1'b0;          
           PoC_lz4_resume_blit        <= 1'b0;
           PoC_lz4_resume_audio       <= 1'b0;
           PoC_subframe_px_lz4        <= 24'd0;
           PoC_lz4_ABCD               <= 2'd0;
           PoC_lz4_field              <= 1'b0;          
           auto_blit_lz4              <= 1'b0;
           
           if (cmd_init) state        <= S_Dispatcher;                             
         end         
         
         S_Dispatcher: // what to do? dispatcher
         begin            
           {r_in, g_in, b_in} <= {8'h00,8'h00,8'h00};             
           vga_frame_reset    <= 1'b0;                                            
           vram_reset         <= 1'b0;        
           vram_wren1         <= 1'b0;                                                             
           vram_wren2         <= 1'b0;                                                             
           vram_wren3         <= 1'b0; 
           vram_wren4         <= 1'b0;
           sound_wren1        <= 1'b0;
           sound_wren2        <= 1'b0;
           sound_wren3        <= 1'b0;
           sound_wren4        <= 1'b0;                                                            
           ddr_data_write     <= 1'b0;
           ddr_data_req       <= 1'b0;                                                                              
           ddr_addr           <= 28'd0;             
           lz4_reset          <= 1'b0;                                        
           vram_active        <= cmd_init ? 1'b1 : 1'b0;                                            
           if (!cmd_init) begin   // reset to defaults                    
             state            <= S_Defaults;                            
           end else if (!ddr_busy) begin  
             if (cmd_scandoubler != PoC_pll_S && (vblank_core || PoC_subframe_px_vram == 0)) begin // scandoubler request for 480i              
               state                 <= S_Switchres_Scandoubler;
             end else            
             if (cmd_switchres && switchres_frame <= vga_frame && (vblank_core || PoC_subframe_px_vram == 0)) begin  // request modeline (apply after blit)  
               reset_switchres       <= 1'b1;                               
               ddr_data_req          <= 1'b1;
               ddr_addr              <= DDR_SW_HEADER; 
               ddr_burst             <= 8'd3;             
               ddr_data_idx          <= 2'd0;                             
               state                 <= S_Switchres_Header;                                                               
             end else                                      
             if (cmd_audio) begin     // audio blit samples requested from hps 
               reset_audio           <= 1'b1;   
               PoC_audio_samples     <= audio_samples;          
               PoC_audio_ddr_bytes   <= audio_samples << sound_chan;
               PoC_audio_count       <= 16'd0;                     
               PoC_audio_count_bytes <= 24'd0;                                                                   
               state                 <= S_Audio_Prepare;                                                               
             end else
             if (cmd_fskip) begin    // use framebuffer avoiding black screeen (auto blit)                                                                               
               state                 <= S_Blit_Auto_Skip;                                                               
             end else       
      //     if (!vga_frameskip && (blit_frame > PoC_frame_vram || blit_pixels > PoC_subframe_px_vram)) begin
      //       state              <= S_Blit_Pixels_Raw;
      //     end else             
             if ((cmd_blit || auto_blit) && !vga_frameskip) begin // pixels blit if fskip isn't activated                                                       
               reset_blit         <= cmd_blit && !cmd_switchres ? 1'b1 : 1'b0; 
               ddr_burst          <= 8'd1;                                     
               ddr_data_req       <= 1'b1;                                                                                            
               state              <= S_Blit_Header_Raw;                                                                           
             end else                                     
             if (cmd_blit_lz4 || auto_blit_lz4)  begin // lz4 blit                                                      
               reset_blit_lz4     <= cmd_blit_lz4 && !cmd_switchres ? 1'b1 : 1'b0;              
               ddr_burst          <= 8'd1;                                     
               ddr_data_req       <= 1'b1;              
               ddr_addr           <= DDR_LZ_HEADER;                                                                                         
               state              <= S_Blit_Header_Lz4;                                                                           
             end                      
           end
         end     
/*
         S_Blit_Pixels_Raw:  // new method
         begin              
           vram_reset <= !vram_synced;                     
           state      <= S_Blit_Raw; 
           if (blit_frame < vga_frame || blit_frame < PoC_frame_ddr || blit_frame < PoC_frame_vram || ((vblank_core || !vram_pixels || !vram_synced) && blit_frame <= vga_frame)) begin //frame arrives later (discard contaminate vram -> latency)
             PoC_subframe_px_vram    <= 24'd0;                                                                      
             PoC_subframe_bl_vram    <= 16'd0;
             PoC_subframe_px_ddr     <= 24'd0;
             PoC_subframe_bl_ddr     <= 16'd0; 
             PoC_subframe_vram_bytes <= 28'd0;                                                                                                                 
             PoC_subframe_ddr_bytes  <= 28'd0;
             PoC_frame_rgb_offset    <= 2'd0;              
             if (blit_frame > PoC_frame_vram) begin
               PoC_frame_vram        <= ddr_data[23:0];  
               PoC_frame_ddr         <= ddr_data[23:0];
             end 
           end else begin                                                                       
             if (blit_frame > PoC_frame_ddr && PoC_subframe_px_vram != 0 && PoC_frame_vram < PoC_frame_ddr && vram_synced) begin  // frame arrives soon, finish blit last asap                                                      
               PoC_subframe_px_ddr <= vga_pixels;
               PoC_subframe_bl_ddr <= PoC_subframe_bl_vram + 1'd1;                             
             end else begin                                                                   
               PoC_frame_ddr       <= blit_frame;
               PoC_subframe_px_ddr <= blit_pixels;    
               PoC_subframe_bl_ddr <= blit_pixels == vga_pixels ? PoC_subframe_bl_vram + 1'b1 : blit_num;                 
             end  
           end                                                                                                       
         end   
*/       
         S_Blit_Header_Raw:  // header ready
         begin   
           if (ddr_busy) ddr_data_req <= 1'b0;                                                       
           reset_blit <= 1'b0;              
           vram_reset <= !vram_synced;          
           if (ddr_data_ready) begin    
             ddr_data_req <= 1'b0;      
             auto_blit    <= PoC_frame_vram >= ddr_data[23:0] ? 1'b0 : 1'b1;                           
             state        <= S_Blit_Raw; 
             if (ddr_data[23:0] < vga_frame || ddr_data[23:0] < PoC_frame_ddr || ddr_data[23:0] < PoC_frame_vram || ((vblank_core || !vram_pixels || !vram_synced) && ddr_data[23:0] <= vga_frame)) begin //frame arrives later (discard contaminate vram -> latency)
               PoC_subframe_px_vram    <= 24'd0;                                                                      
               PoC_subframe_bl_vram    <= 16'd0;
               PoC_subframe_px_ddr     <= 24'd0;
               PoC_subframe_bl_ddr     <= 16'd0; 
               PoC_subframe_vram_bytes <= 28'd0;                                                                                                                 
               PoC_subframe_ddr_bytes  <= 28'd0;
               PoC_frame_rgb_offset    <= 2'd0;              
               if (ddr_data[23:0] > PoC_frame_vram) begin
                 PoC_frame_vram        <= ddr_data[23:0];  
                 PoC_frame_ddr         <= ddr_data[23:0];
               end 
             end else begin                                                                       
               if (ddr_data[23:0] > PoC_frame_ddr && PoC_subframe_px_vram != 0 && PoC_frame_vram < PoC_frame_ddr && vram_synced) begin  // frame arrives soon, finish blit last asap                                                      
                 PoC_subframe_px_ddr <= vga_pixels;
                 PoC_subframe_bl_ddr <= PoC_subframe_bl_vram + 1'd1;                             
               end else begin                                                                   
                 PoC_frame_ddr       <= ddr_data[23:0];
                 PoC_subframe_px_ddr <= ddr_data[47:24];    
                 PoC_subframe_bl_ddr <= ddr_data[47:24] == vga_pixels ? PoC_subframe_bl_vram + 1'b1 : ddr_data[63:48];                         
               end  
             end                                                                                             
           end                                   
         end     
         
         S_Blit_Raw:  // get pixels to blit from header
         begin           
           state      <= S_Dispatcher;  
           vram_reset <= 1'b0;                                            
           if (PoC_frame_ddr > PoC_frame_vram && PoC_subframe_px_ddr > PoC_subframe_px_vram && PoC_subframe_bl_ddr > PoC_subframe_bl_vram) begin 
             if (PoC_subframe_px_vram == 0) begin
               PoC_subframe_vram_bytes <= 24'd0;               
               vga_frameskip_prev      <= 1'b0;             
               PoC_frame_rgb_offset    <= 2'd0;                
               vram_reset              <= vga_pixels != vram_pixels ? 1'b1 : 1'b0; // prev. ddr crushed?  
               if (vram_queue == 0 && !vblank_core) vga_wait_vblank <= 1'b1;               
             end                                             
             PoC_subframe_ddr_bytes  <= (rgb_mode == 1) ? (PoC_subframe_px_ddr << 2) : (rgb_mode == 2) ? (PoC_subframe_px_ddr << 1) : (PoC_subframe_px_ddr << 1) + PoC_subframe_px_ddr;             
             state                   <= PoC_subframe_bl_ddr == 65535 ? S_Blit_End_Raw : S_Blit_Prepare_Raw;                               
           end                          
         end          
         
        S_Blit_Prepare_Raw: // Prepare fetch ddr when vram it's ready to get max burst
         begin                                
           ddr_data_req    <= 1'b0; 
           vram_reset      <= 1'b0;                     
           if (!cmd_audio && PoC_subframe_vram_bytes < PoC_subframe_ddr_bytes && (vga_pixels == PoC_subframe_px_ddr || ((PoC_subframe_ddr_bytes - PoC_subframe_vram_bytes) >> 3) > 0)) begin   
             if (!ddr_busy && vram_req_ready) begin                      
               ddr_burst    <= PoC_subframe_ddr_bytes - PoC_subframe_vram_bytes > 24'd1023 ? 8'd128 : vga_pixels == PoC_subframe_px_ddr ? ((PoC_subframe_ddr_bytes - PoC_subframe_vram_bytes) >> 3) + 1'b1 : (PoC_subframe_ddr_bytes - PoC_subframe_vram_bytes) >> 3;                                                           
               ddr_addr     <= PoC_FB_interlaced && (PoC_frame_switchres + PoC_frame_ddr) % 2 == 1 ? DDR_FD_OFFSET + PoC_subframe_vram_bytes : DDR_FB_OFFSET + PoC_subframe_vram_bytes;                          
               ddr_data_req <= 1'b1;                                              
               state        <= S_Blit_Copy_Raw;                                                                                                                
             end   
           end else state   <= S_Dispatcher;                                                                             
         end 
         
         S_Blit_Copy_Raw: 
         begin                                                             
           if (ddr_busy) ddr_data_req <= 1'b0;                                  
           vram_wren1                 <= 1'b0;  
           vram_wren2                 <= 1'b0;  
           vram_wren3                 <= 1'b0;
           vram_wren4                 <= 1'b0;                                
           vga_soft_reset             <= 1'b0;   
           if (vram_queue > 0) vga_wait_vblank <= 1'b0;          
           if (ddr_data_ready) begin             
             ddr_data_req             <= 1'b0;                        
             if (!ddr_busy) state     <= S_Blit_End_Raw; // end burst
             PoC_subframe_vram_bytes  <= PoC_subframe_vram_bytes + 8'd8;
             if (vram_synced) begin
               vram_drive_raw         <= 1'b1;  
               vram_drive_lz4         <= 1'b0;                
               decode_pixel(1'b0, ddr_data, PoC_subframe_px_ddr);                                                         
             end
           end           
         end 
         
         S_Blit_End_Raw: // Check if all pixels are writed
         begin 
           vram_wren1                <= 1'b0;
           vram_wren2                <= 1'b0;  
           vram_wren3                <= 1'b0; 
           vram_wren4                <= 1'b0;     
           if (PoC_subframe_vram_bytes + 8'd7 >= PoC_subframe_ddr_bytes) PoC_subframe_bl_vram <= PoC_subframe_bl_ddr;                
           if (PoC_subframe_px_vram >= vga_pixels || PoC_subframe_bl_ddr == 65535) begin // all pixels saved on vram                                                                                        
             if (PoC_frame_ddr > PoC_frame_vram) PoC_frame_vram <= PoC_frame_ddr;             
             PoC_subframe_bl_vram    <= 16'd0;
             PoC_subframe_px_vram    <= 24'd0; 
             PoC_subframe_px_ddr     <= 24'd0;      
             PoC_subframe_bl_ddr     <= 16'd0;
             PoC_subframe_vram_bytes <= 28'd0;
             PoC_subframe_ddr_bytes  <= 28'd0;
             PoC_frame_rgb_offset    <= 2'd0;                  
             vga_wait_vblank         <= 1'b0;             
             vram_drive_raw          <= 1'b0;           
             vram_reset              <= !vram_synced || PoC_subframe_px_vram != vga_pixels ? 1'b1 : 1'b0;   //vram_pixels not yet updated to compare!           
             state                   <= S_Dispatcher; 
           end else state            <= cmd_audio ? S_Dispatcher : S_Blit_Prepare_Raw;            
         end

         S_Blit_Auto_Skip:  // calculate pixels to get next line
         begin                                                               
           if (PoC_state_frameskip == S_Blit_Auto_First) PoC_px_frameskip <= (PoC_H << PoC_interlaced) + 24'd3;
           else if (PoC_state_frameskip == S_Blit_Auto_End) PoC_px_frameskip <= vga_pixels;
                else PoC_px_frameskip <= ((PoC_H * (vga_vcount + 10'd1 + PoC_interlaced)) >> PoC_FB_interlaced) + 24'd3;                               
           state <= PoC_state_frameskip == S_Blit_Auto_First ? S_Blit_Auto_First : S_Blit_Auto_Line;                                                                               
         end            
         
         S_Blit_Auto_First:  // blit first line of the next frame with rgb of last
         begin                                                               
           vga_frameskip           <= 1'b1;                   
           PoC_frame_ddr           <= vga_frame + 1;        
           PoC_subframe_px_ddr     <= PoC_px_frameskip;                                          
           PoC_subframe_px_vram    <= 24'd0;
           PoC_subframe_bl_ddr     <= 16'd1;                      
           PoC_subframe_bl_vram    <= 16'd1;                   
           PoC_subframe_ddr_bytes  <= (rgb_mode == 1) ? (PoC_px_frameskip << 2) : (rgb_mode == 2) ? (PoC_px_frameskip << 1) : (PoC_px_frameskip << 1) + PoC_px_frameskip;         
           PoC_subframe_vram_bytes <= 28'd0;             
           PoC_frame_rgb_offset    <= 2'd0;                                     
           vram_reset              <= 1'b1;            
           auto_blit               <= 1'b0;                        
           vram_drive_raw          <= 1'b0;
           vram_drive_lz4          <= 1'b0;                                  
           state                   <= S_Blit_Prepare_Raw;                                                                               
         end             
         
        S_Blit_Auto_Line:  // is next line blitted?
        begin            
        vram_reset                   <= 1'b0;                           
          if (!vram_synced) begin
             PoC_subframe_px_vram    <= 24'd0;
             PoC_subframe_bl_vram    <= 16'd0;                                  
             PoC_subframe_px_ddr     <= 24'd0;
             PoC_subframe_bl_ddr     <= 16'd0;         
             PoC_subframe_ddr_bytes  <= 28'd0;         
             PoC_subframe_vram_bytes <= 28'd0; 
             PoC_frame_rgb_offset    <= 2'd0;                    
             auto_blit               <= 1'b0;  
             vram_reset              <= 1'b1;             
             vram_drive_raw          <= 1'b0;
             vram_drive_lz4          <= 1'b0;                                                                              
             state                   <= S_Dispatcher;                                                                                                           
           end else 
           if (PoC_px_frameskip > vram_pixels) begin                                
             vga_frameskip           <= 1'b1;         
             PoC_frame_ddr           <= vga_frame;           
             PoC_subframe_px_ddr     <= PoC_px_frameskip;           
             PoC_subframe_bl_ddr     <= PoC_subframe_bl_vram + 16'd1;                     
             PoC_subframe_bl_vram    <= PoC_subframe_bl_vram + 16'd1;               
             PoC_subframe_ddr_bytes  <= (rgb_mode == 1) ? (PoC_px_frameskip << 2) : (rgb_mode == 2) ? (PoC_px_frameskip << 1) : (PoC_px_frameskip << 1) + PoC_px_frameskip; 
             auto_blit               <= 1'b0;                    
             state                   <= S_Blit_Prepare_Raw;                                                                   
           end else begin
             state                   <= S_Dispatcher;                                                                                                                                                 
           end                              
         end                 
         
         S_Switchres_Header: // switchres requested and data ready
         begin        
           if (ddr_busy) ddr_data_req <= 1'b0;     
           reset_switchres            <= 1'b0;                          
           if (ddr_data_ready) begin    
             ddr_data_req                        <= 1'b0;
             ddr_data_tmp[64*ddr_data_idx +: 64] <= ddr_data;           
             ddr_data_idx                        <= ddr_data_idx + 1'b1;                    
             if (!ddr_busy) state                <= S_Switchres_PLL;                
           end
         end
         
         S_Switchres_PLL: // apply switch on vblank (except at startup)
         begin                                                                                   
           if (vblank_core || vga_frame == 0 || (vram_pixels == 0 && PoC_frame_ddr == 0)) begin                                                                                          
           // modeline                                   
             PoC_H         <= ddr_data_tmp[0  +:16];
             PoC_HFP       <= ddr_data_tmp[16 +:08];
             PoC_HS        <= ddr_data_tmp[24 +:08];
             PoC_HBP       <= ddr_data_tmp[32 +:08];
             PoC_V         <= ddr_data_tmp[40 +:16];
             PoC_VFP       <= ddr_data_tmp[56 +:08];
             PoC_VS        <= ddr_data_tmp[64 +:08];
             PoC_VBP       <= ddr_data_tmp[72 +:08];                                 
           // pixel clock                                                
             PoC_pll_F_M0  <= ddr_data_tmp[80  +:08];
             PoC_pll_F_M1  <= ddr_data_tmp[88  +:08];
             PoC_pll_F_C0  <= ddr_data_tmp[96  +:08];
             PoC_pll_F_C1  <= ddr_data_tmp[104 +:08];
             PoC_pll_F_K   <= ddr_data_tmp[112 +:32];                                           
             PoC_ce_pix    <= ddr_data_tmp[144 +:08];        
          
             PoC_interlaced      <= ddr_data_tmp[152 +:08] >= 1 ? 1'b1 : 1'b0;                                               
             PoC_FB_interlaced   <= ddr_data_tmp[152 +:08] == 1 ? 1'b1 : 1'b0;                        
             PoC_frame_switchres <= switchres_frame + 1'b1;           
             PoC_pll_S           <= (forced_scandoubler || scandoubler_fx != 2'b00) && ddr_data_tmp[152 +:08] == 2 ? 1'b1 : 1'b0;                              
                                                                                                 
             req_modeline    <= ~new_modeline; // update pll                         
             new_vmode       <= ~new_vmode;    // notify to osd           
             state           <= S_Switchres_Mode;                                                                    
           end                   
         end        
         
         S_Switchres_Mode: // apply change clk
         begin              
           vga_soft_reset             <= 1'b1; // raster to V + 1  
           vram_reset                 <= 1'b1;             
           vga_frameskip              <= 1'b0;                  
           lz4_reset                  <= 1'b1;
           PoC_frame_vram             <= 24'd0;   
           PoC_subframe_px_vram       <= 24'd0;   
           PoC_subframe_bl_vram       <= 16'd0;  
           PoC_subframe_lz4_ddr_bytes <= 24'd0;
           PoC_subframe_blit_lz4_ddr  <= 16'd0;                       
           PoC_subframe_blit_lz4      <= 16'd0;                     
           PoC_subframe_wr_bytes      <= 28'd0;         
           PoC_subframe_px_lz4        <= 24'd0;   
           PoC_lz4_resume_blit        <= 1'b0;   
           PoC_lz4_resume_audio       <= 1'b0;   
           vram_drive_lz4             <= 1'b0;             
           vram_drive_raw             <= 1'b0;             
           lz4_compressed_bytes       <= 32'd0;                  
           req_modeline               <= ~new_modeline;                                 
           new_vmode                  <= ~new_vmode;                                                                       
           state                      <= S_Dispatcher;                                                                       
         end     
         
         S_Switchres_Scandoubler: // scandoubler change
         begin
           if (vblank_core || vga_frame == 0 || (vram_pixels == 0 && PoC_frame_ddr == 0)) begin 
             PoC_pll_S    <= cmd_scandoubler;         
             req_modeline <= ~new_modeline;                         
             new_vmode    <= ~new_vmode;               
             state        <= S_Switchres_Mode;                        
           end
         end
         
         S_Audio_Prepare: // Prepare fetch ddr when sound it's ready to get max burst
         begin                        
           reset_audio    <= 1'b0; 
           vram_reset     <= 1'b0;             
           if (ddr_busy) ddr_data_req <= 1'b0;                                                
           if (!ddr_busy) begin                     
             ddr_burst    <= PoC_audio_ddr_bytes - PoC_audio_count_bytes > 24'd1023 ? 8'd128 : ((PoC_audio_ddr_bytes - PoC_audio_count_bytes) >> 3) + 1'b1;
             ddr_addr     <= DDR_AB_OFFSET + PoC_audio_count_bytes;                                                                                         
             ddr_data_req <= 1'b1;                                              
             state        <= S_Audio_Copy;                                                                                                                
           end                                                                             
         end 

        S_Audio_Copy: 
        begin           
          if (ddr_busy) ddr_data_req <= 1'b0;                                  
          sound_wren1 <= 1'b0;                                                                                 
          sound_wren2 <= 1'b0;                                                                                 
          sound_wren3 <= 1'b0;                                                                                 
          sound_wren4 <= 1'b0;           
          if (ddr_data_ready) begin             
            ddr_data_req          <= 1'b0;                        
            if (!ddr_busy) state  <= S_Audio_End; // end burst
            PoC_audio_count_bytes <= PoC_audio_count_bytes + 8'd8;             
            sound_in1             <= ddr_data[00 +: 16]; 
            sound_in2             <= ddr_data[16 +: 16]; 
            sound_in3             <= ddr_data[32 +: 16]; 
            sound_in4             <= ddr_data[48 +: 16];                            
            if (sound_chan == 2'd2) begin 
              if (PoC_audio_samples - PoC_audio_count > 1) begin
                PoC_audio_count   <= PoC_audio_count + 2'd2;
                sound_wren1       <= 1'b1;  
                sound_wren2       <= 1'b1;  
                sound_wren3       <= 1'b1;  
                sound_wren4       <= 1'b1;  
              end else 
              if (PoC_audio_samples - PoC_audio_count > 0) begin  
                PoC_audio_count   <= PoC_audio_count + 2'd1;
                sound_wren1       <= 1'b1;  
                sound_wren2       <= 1'b1;                   
              end
            end else begin
              if (PoC_audio_samples - PoC_audio_count > 3) begin
                PoC_audio_count   <= PoC_audio_count + 3'd4;
                sound_wren1       <= 1'b1;  
                sound_wren2       <= 1'b1;  
                sound_wren3       <= 1'b1;  
                sound_wren4       <= 1'b1;  
              end else 
              if (PoC_audio_samples - PoC_audio_count > 2) begin  
                PoC_audio_count   <= PoC_audio_count + 2'd3;
                sound_wren1       <= 1'b1;  
                sound_wren2       <= 1'b1;  
                sound_wren3       <= 1'b1;  
              end else
              if (PoC_audio_samples - PoC_audio_count > 1) begin  
                PoC_audio_count   <= PoC_audio_count + 2'd2;
                sound_wren1       <= 1'b1;  
                sound_wren2       <= 1'b1;                   
              end else
              if (PoC_audio_samples - PoC_audio_count > 0) begin  
                PoC_audio_count   <= PoC_audio_count + 2'd1;
                sound_wren1       <= 1'b1;  
              end
            end
           end                                                                                                      
         end        

         S_Audio_End: // Check if all samples are writed
         begin 
           sound_wren1 <= 1'b0;
           sound_wren2 <= 1'b0;  
           sound_wren3 <= 1'b0; 
           sound_wren4 <= 1'b0;                     
           if (PoC_audio_count >= PoC_audio_samples) begin // all samples writed
             PoC_audio_samples     <= 16'd0;
             PoC_audio_count       <= 16'd0;
             PoC_audio_ddr_bytes   <= 24'd0;
             PoC_audio_count_bytes <= 24'd0; 
             state                 <= S_Dispatcher; 
           end else state          <= S_Audio_Prepare;            
         end
                  
       S_Blit_Header_Lz4:  // header lz4 ready
         begin                
           if (ddr_busy) ddr_data_req <= 1'b0;                                                             
           reset_blit_lz4             <= 1'b0;                                                                                              
           vram_reset                 <= !vram_synced;                    
           PoC_frame_lz4_FB           <= (PoC_frame_lz4_ddr < vga_frame || PoC_frame_lz4_ddr < PoC_frame_ddr || PoC_frame_lz4_ddr < PoC_frame_vram || ((vblank_core || !vram_pixels || !vram_synced || vram_drive_raw || cmd_fskip || vga_frameskip) && PoC_frame_lz4_ddr <= vga_frame)) ? 1'b1 : 1'b0;  //only framebuffer?          
           if (ddr_data_ready) begin  
             ddr_data_req             <= 1'b0;     
             auto_blit_lz4            <= PoC_frame_lz4 >= ddr_data[23:0] ? 1'b0 : 1'b1;                                        
             if (PoC_lz4_resume_blit || PoC_lz4_resume_audio || lz4_writed_bytes > lz4_readed_bytes) begin // lz4 has bytes pending, last blit isnt finished
               state <= S_Blit_Copy_End_Lz4;          
             end else begin                                            
               if (ddr_data[23:0] > PoC_frame_lz4_ddr && lz4_writed_bytes != 0) begin  // finish current frame before new one, read all bytes from last lz4 zone (not if only using for refresh FB)                                
                 state <= S_Blit_Lz4;                                  
                 PoC_subframe_lz4_ddr_bytes <= lz4_compressed_bytes; 
                 PoC_subframe_blit_lz4_ddr  <= PoC_subframe_blit_lz4 + 1'b1;                                                               
               end else begin                                
                 if (ddr_data[23:0] < vga_frame || ddr_data[23:0] < PoC_frame_ddr || ddr_data[23:0] < PoC_frame_vram || ((vblank_core || !vram_pixels || !vram_synced || vram_drive_raw || cmd_fskip || vga_frameskip) && ddr_data[23:0] <= vga_frame)) begin                    
                   state <= S_Blit_Lz4;
                   PoC_frame_lz4_FB <= 1'b1;                
                 end else begin
                   PoC_frame_lz4_FB <= 1'b0;                
                   state <= (!vram_synced || vram_drive_raw || cmd_fskip || vga_frameskip) ? S_Dispatcher : S_Blit_Lz4; // if vram is controlled by fskip and this is a future frame, wait vblank
                 end                       
                 PoC_frame_lz4_ddr          <= ddr_data[23:0];
                 PoC_subframe_lz4_ddr_bytes <= ddr_data[47:24]; 
                 PoC_subframe_blit_lz4_ddr  <= ddr_data[47:24] == lz4_compressed_bytes ? PoC_subframe_blit_lz4 + 1'b1 : ddr_data[63:48];                                              
               end
             end
           end                                   
         end         

         S_Blit_Lz4:  // get bytes to blit from header
         begin                                              
           state      <= S_Dispatcher;            
           vram_reset <= 1'b0;                       
           if (PoC_frame_lz4_ddr > PoC_frame_lz4 && PoC_subframe_lz4_ddr_bytes > lz4_writed_bytes && PoC_subframe_blit_lz4_ddr > PoC_subframe_blit_lz4) begin                                                                                                                                         
             if (lz4_writed_bytes == 0) begin                                                                            
               if (!vram_drive_raw) PoC_frame_rgb_offset <= 2'd0; 
               if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_queue == 0 && !vblank_core) vga_wait_vblank <= 1'b1;
               PoC_subframe_px_lz4   <= 24'd0;                                                                                
               vga_frameskip_prev    <= 1'b0;                              
               PoC_subframe_wr_bytes <= 28'd0; 
               lz4_compressed_bytes  <= lz4_size;               
               lz4_reset             <= 1'b1;
               vram_reset            <= (!vram_drive_raw && vga_pixels != vram_pixels) ? 1'b1 : 1'b0; // prev. lz4 crushed?                 
               PoC_lz4_ABCD          <= lz4_ABCD; 
               PoC_lz4_field         <= lz4_field;                 
             end                                                                    
             state                   <= PoC_subframe_blit_lz4_ddr == 65535 ? S_Blit_End_Lz4 : S_Blit_Prepare_Lz4;                                                                                                                                                                                   
           end                          
         end   

         S_Blit_Prepare_Lz4: // Prepare fetch ddr when lz4 it's ready to get max burst
         begin                                            
           ddr_data_req    <= 1'b0; 
           lz4_reset       <= 1'b0;
           vram_reset      <= 1'b0;                  
           if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_queue == 0 && !vblank_core)   vga_wait_vblank <= 1'b1;
           if (!cmd_audio && lz4_writed_bytes < PoC_subframe_lz4_ddr_bytes && (lz4_compressed_bytes == PoC_subframe_lz4_ddr_bytes || ((PoC_subframe_lz4_ddr_bytes - lz4_writed_bytes) >> 3) > 0)) begin           
             if (!ddr_busy && lz4_write_ready) begin                                                          
               ddr_burst    <= PoC_subframe_lz4_ddr_bytes - lz4_writed_bytes > 24'd1023 ? 8'd128 : lz4_compressed_bytes == PoC_subframe_lz4_ddr_bytes ? ((lz4_compressed_bytes - lz4_writed_bytes) >> 3) + 8'd1 : (PoC_subframe_lz4_ddr_bytes - lz4_writed_bytes) >> 3;                                                         
               ddr_addr     <= PoC_lz4_ABCD == 0 ? DDR_LZ_OFFSET_A + lz4_writed_bytes : PoC_lz4_ABCD == 1 ? DDR_LZ_OFFSET_B + lz4_writed_bytes : PoC_lz4_ABCD == 2 ? DDR_LZ_OFFSET_C + lz4_writed_bytes : DDR_LZ_OFFSET_D + lz4_writed_bytes;
               ddr_data_req <= 1'b1;                                              
               state        <= S_Blit_Copy_Lz4;                                                                                                                
             end   
           end else state   <= S_Dispatcher;                                                                             
         end 
                
         S_Blit_Copy_Lz4: // insert long words to lz4 module (input buffer always can with ddr_burst)
         begin                                
           if (ddr_busy) ddr_data_req <= 1'b0;                                  
           lz4_write_long             <= 1'b0;                                                                                                                                                                                                        
           lz4_run                    <= 1'b0;  
           lz4_stop                   <= 1'b1;                  
           if (ddr_data_ready) begin             
             ddr_data_req             <= 1'b0; 
             lz4_write_long           <= 1'b1; 
             lz4_run                  <= lz4_write_long;
             lz4_compressed_long      <= ddr_data;                                                                                
             if (!ddr_busy) state     <= S_Blit_Copy_End_Lz4;                              
           end           
         end 
 
         S_Blit_Copy_End_Lz4:
         begin             
           lz4_write_long  <= 1'b0;                                                                  
           lz4_stop        <= 1'b0;
           vga_wait_vblank <= 1'b0;   
           lz4_run         <= vram_req_ready || PoC_frame_lz4_FB ? 1'b1 : 1'b0;                
           state           <= S_Blit_Inflate_Lz4;        
         end
       
         S_Blit_Inflate_Lz4: // uncompress bytes 
         begin           
           vram_wren1      <= 1'b0;
           vram_wren2      <= 1'b0;
           vram_wren3      <= 1'b0;  
           vram_wren4      <= 1'b0;
           if (vram_queue > 0) vga_wait_vblank <= 1'b0;             
           ddr_data_write  <= ddr_data_write && ddr_busy ? 1'b1 : 1'b0;   // last uncompressed isnt writed yet                         
           vga_soft_reset  <= 1'b0;                                        
           lz4_run         <= lz4_done || cmd_fskip || cmd_audio || !cmd_init || (!vram_req_ready && !PoC_frame_lz4_FB) || !vram_synced ? 1'b0 : 1'b1;
           state           <= !(ddr_data_write && ddr_busy) && (lz4_paused || lz4_done || cmd_fskip || cmd_audio || !cmd_init || !vram_synced) ? S_Blit_End_Lz4 : S_Blit_Inflate_Lz4;                                                                                                                                                   
           if (lz4_long_valid && lz4_uncompressed_bytes > PoC_subframe_wr_bytes && !(ddr_data_write && ddr_busy) && PoC_subframe_px_lz4 < vga_pixels) begin                                                            
           //update framebuffer                           
             PoC_subframe_wr_bytes <= PoC_subframe_wr_bytes + 8'd8;    
             if (PoC_lz4_field == 2) begin                         
               ddr_addr            <= PoC_FB_interlaced && (PoC_frame_switchres + PoC_frame_lz4_ddr) % 2 == 1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end else begin
               ddr_addr            <= PoC_FB_interlaced && PoC_lz4_field == 1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end 
             ddr_data_write        <= 1'b1;
             ddr_burst             <= 8'd1;           
             ddr_data_to_write     <= lz4_uncompressed_long;                                               
           //end update
           //put pixels on vram
             if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_synced && PoC_subframe_px_lz4 < vga_pixels) begin   
               vram_drive_lz4          <= 1'b1;                 
               PoC_subframe_vram_bytes <= PoC_subframe_vram_bytes + 8'd8; //needed if fskip starts
               decode_pixel(1'b1, lz4_uncompressed_long, vga_pixels);     
             end                         
           end                      
         end
         
         S_Blit_End_Lz4: // Check if all pixels are writed
         begin 
           vram_wren1            <= 1'b0;
           vram_wren2            <= 1'b0;  
           vram_wren3            <= 1'b0; 
           vram_wren4            <= 1'b0;  
           ddr_data_write        <= 1'b0; 
           lz4_run               <= 1'b0;               
           PoC_lz4_resume_blit   <= cmd_fskip;                        
           PoC_lz4_resume_audio  <= cmd_audio;        
           if (lz4_writed_bytes + 8'd7 >= PoC_subframe_lz4_ddr_bytes) PoC_subframe_blit_lz4 <= PoC_subframe_blit_lz4_ddr;                          
           if (lz4_done || PoC_subframe_blit_lz4_ddr == 65535 || !vram_synced) begin                  
             if (vram_drive_lz4 && !cmd_fskip) begin
               if (PoC_frame_lz4_ddr > PoC_frame_vram) begin
                 PoC_frame_ddr         <= PoC_frame_lz4_ddr;         
                 PoC_frame_vram        <= PoC_frame_lz4_ddr;         
               end            
               PoC_subframe_px_vram    <= 24'd0;
               PoC_subframe_vram_bytes <= 24'd0;
               PoC_frame_rgb_offset    <= 2'd0;     
               vga_wait_vblank         <= 1'b0;
               vram_reset              <= !vram_synced || PoC_subframe_px_lz4 != vga_pixels ? 1'b1 : 1'b0;                                                                                                     
             end              
             if (PoC_frame_lz4_ddr > PoC_frame_lz4) PoC_frame_lz4 <= PoC_frame_lz4_ddr;         
             PoC_subframe_lz4_ddr_bytes <= 24'd0;
             PoC_subframe_blit_lz4_ddr  <= 16'd0;                        
             PoC_subframe_blit_lz4      <= 16'd0; 
             PoC_subframe_wr_bytes      <= 28'd0;         
             PoC_subframe_px_lz4        <= 24'd0;   
             PoC_lz4_resume_blit        <= 1'b0;   
             PoC_lz4_resume_audio       <= 1'b0;   
             vram_drive_lz4             <= 1'b0;      
             lz4_reset                  <= 1'b1;   
             lz4_compressed_bytes       <= 32'd0;   
             state                      <= S_Dispatcher; 
           end else state               <= !cmd_init || cmd_fskip || cmd_audio ? S_Dispatcher : S_Blit_Prepare_Lz4;                                               
         end

         S_Defaults: 
         begin        
          vram_reset         <= 1'b0;                                    
          {r_in, g_in, b_in} <= {8'h00,8'h00,8'h00};                                      
          PoC_H              <= 16'd256;
          PoC_HFP            <= 8'd10;
          PoC_HS             <= 8'd24;
          PoC_HBP            <= 8'd41;
          PoC_V              <= 16'd240;
          PoC_VFP            <= 8'd2;
          PoC_VS             <= 8'd3;
          PoC_VBP            <= 8'd16;
          PoC_pll_F_M0       <= 8'd4;
          PoC_pll_F_M1       <= 8'd4;
          PoC_pll_F_C0       <= 8'd3;
          PoC_pll_F_C1       <= 8'd2;
          PoC_pll_F_K        <= 32'd1182682725;
          PoC_ce_pix         <= 8'd16;
          PoC_pll_S          <= 1'b0;     
          PoC_interlaced     <= 1'b0;                                                                    
          PoC_FB_interlaced  <= 1'b0;                                                                    
          req_modeline       <= ~new_modeline;                   
          new_vmode          <= ~new_vmode;      
          state              <= S_Reset;                                                                                                           
         end     
         
         S_Reset:  
         begin           
          req_modeline       <= ~new_modeline;                   
          new_vmode          <= ~new_vmode;      
          vga_reset          <= 1'b1;
          sound_reset        <= 1'b1;         
          state              <= S_Idle;   
         end
         
         default:
         begin
           state <= S_Idle;                        
         end
   endcase                         
                                                                        
end
                          

////////////////////////////////////////////////////////////////////////////////
//
//                               VIDEO MODULES
//
////////////////////////////////////////////////////////////////////////////////

assign CLK_VIDEO = clk_sys;
wire vram_req_ready;
wire vram_end_frame;
wire vram_synced;
wire[23:0] vga_pixels, vram_pixels;
wire[23:0] vram_queue;

reg vga_soft_reset = 1'b0;
reg vga_wait_vblank = 1'b0;
reg vga_reset = 1'b1;
reg vga_frame_reset = 1'b0;
reg vram_active = 1'b0;
reg vram_reset = 1'b0;

reg vram_drive_raw = 1'b0;
reg vram_drive_lz4 = 1'b0;

wire[7:0] r_core, g_core, b_core;
wire hsync_core, vsync_core,  vblank_core, hblank_core, vga_de_core;
wire[15:0] vga_vcount;
wire[31:0] vga_frame;

reg[7:0] r_in = 8'h00, g_in = 8'h00, b_in = 8'h00; 
reg vram_wren1 = 1'b0, vram_wren2 = 1'b0, vram_wren3 = 1'b0, vram_wren4 = 1'b0;
reg[7:0] r_vram_in1 = 8'h00, r_vram_in2 = 8'h00, r_vram_in3 = 8'h00, r_vram_in4 = 8'h00;
reg[7:0] g_vram_in1 = 8'h00, g_vram_in2 = 8'h00, g_vram_in3 = 8'h00, g_vram_in4 = 8'h00;
reg[7:0] b_vram_in1 = 8'h00, b_vram_in2 = 8'h00, b_vram_in3 = 8'h00, b_vram_in4 = 8'h00;

vga vga 
(           
 .clk_sys        (clk_sys),      
 .ce_pix         (ce_pix),
 .vga_reset      (vga_reset),
 .vga_frame_reset(vga_frame_reset),
 .vga_soft_reset (vga_soft_reset),       
 .vga_wait_vblank(vga_wait_vblank),
 
  //modeline
 .H(PoC_H),
 .HFP(PoC_HFP),
 .HS(PoC_HS),
 .HBP(PoC_HBP),
 .V(PoC_V),
 .VFP(PoC_VFP),
 .VS(PoC_VS),
 .VBP(PoC_VBP),
 .interlaced(cmd_scandoubler && PoC_pll_S ? 1'b0 : PoC_interlaced),   
 //.interlaced(PoC_interlaced),   
 .FB_interlaced(PoC_FB_interlaced),   // only write on vram odd/even lines
  //vram 
 .vram_active    (vram_active),       // read pixels from vram, if 0 no vram consumed but vram_req is atended
 .vram_reset     (vram_reset),        // clean vram      
 .vram_wren1     (vram_wren1),        // write pixel {r_in, g_in, b_in} to vram    
 .r_vram_in1     (r_vram_in1),        // active vram r in
 .g_vram_in1     (g_vram_in1),        // active vram g in 
 .b_vram_in1     (b_vram_in1),        // active vram b in
 .vram_wren2     (vram_wren2),        // write pixel {r_in, g_in, b_in} to vram    
 .r_vram_in2     (r_vram_in2),        // active vram r in
 .g_vram_in2     (g_vram_in2),        // active vram g in 
 .b_vram_in2     (b_vram_in2),        // active vram b in
 .vram_wren3     (vram_wren3),        // write pixel {r_in, g_in, b_in} to vram    
 .r_vram_in3     (r_vram_in3),        // active vram r in
 .g_vram_in3     (g_vram_in3),        // active vram g in 
 .b_vram_in3     (b_vram_in3),        // active vram b in
 .vram_wren4     (vram_wren4),        // write pixel {r_in, g_in, b_in} to vram    
 .r_vram_in4     (r_vram_in4),        // active vram r in
 .g_vram_in4     (g_vram_in4),        // active vram g in 
 .b_vram_in4     (b_vram_in4),        // active vram b in
 .r_in           (r_in),              // non active vram r in (used for testing)
 .g_in           (g_in),              // non active vram g in (used for testing)
 .b_in           (b_in),              // non active vram b in (used for testing)  
 .vram_ready     (vram_req_ready),    // vram it's ready to write a new pixel    
 .vram_end_frame (vram_end_frame),    // in vram there ara all pixels of current frame      
 .vram_synced    (vram_synced),       // vram it's synced on frame
 .vram_pixels    (vram_pixels),       // pixels on vram (reset after saved new pixel of the next frame)      
 .vram_queue     (vram_queue),        // pixels prepared to read
 .vga_frame      (vga_frame),         // vga vblanks counter
 .vcount         (vga_vcount),        // vertical count raster position 
 .vga_pixels     (vga_pixels),        // number of pixels for that frame
  //out signals
 .hsync          (hsync_core),
 .vsync          (vsync_core),
 .r              (r_core),
 .g              (g_core),
 .b              (b_core),
 .vga_de         (vga_de_core),  
 .hblank         (hblank_core),
 .vblank         (vblank_core),
 .vga_f1         (VGA_F1)
         
);


wire hs_jt, vs_jt;

// H/V offset

wire [4:0]      hoffset = status[21:17];
wire [4:0]      voffset = status[26:22];
jtframe_resync jtframe_resync
(
 .clk(clk_sys),
 .pxl_cen(ce_pix),
 .hs_in(hsync_core),
 .vs_in(vsync_core),
 .LVBL(~vblank_core),
 .LHBL(~hblank_core),
 .hoffset(hoffset),
 .voffset(voffset),
 .hs_out(hs_jt),
 .vs_out(vs_jt)
);


video_mixer #(640, 0, 1) video_mixer(
 .CLK_VIDEO(CLK_VIDEO),
 .CE_PIXEL(CE_PIXEL),
 .ce_pix(ce_pix),

 .scandoubler(PoC_interlaced && !PoC_FB_interlaced ? 1'b0 : (forced_scandoubler || scandoubler_fx != 2'b00)),
 .hq2x(0),

 .gamma_bus(gamma_bus),

 .R(r_core),
 .G(g_core),
 .B(b_core),

 .HBlank(hblank_core),
 .VBlank(vblank_core),
 .HSync(hs_jt),
 .VSync(vs_jt),

 .VGA_R(VGA_R),
 .VGA_G(VGA_G),
 .VGA_B(VGA_B),
 .VGA_VS(VGA_VS),
 .VGA_HS(VGA_HS),
 .VGA_DE(VGA_DE_MIXER),

 .HDMI_FREEZE(HDMI_FREEZE)
);


wire VGA_DE_MIXER;
     
video_freak video_freak(
 .CLK_VIDEO(CLK_VIDEO),
 .CE_PIXEL(CE_PIXEL),
 .VGA_VS(VGA_VS),
 .HDMI_WIDTH(HDMI_WIDTH),
 .HDMI_HEIGHT(HDMI_HEIGHT),
 .VGA_DE(VGA_DE),
 .VIDEO_ARX(VIDEO_ARX),
 .VIDEO_ARY(VIDEO_ARY),

 .VGA_DE_IN(VGA_DE_MIXER),
 .ARX((!ar) ? ( no_rotate ? 12'd4 : 12'd3 ) : (ar - 1'd1)),
 .ARY((!ar) ? ( no_rotate ? 12'd3 : 12'd4 ) : 12'd0),
 .CROP_SIZE(crop_240p ? 240 : 0),
 .CROP_OFF(crop_offset),
 .SCALE(scale)
);

//////////////////////////////////// AUDIO /////////////////////////////////////////////////////
reg sound_reset = 1'b1;
reg sound_wren1 = 1'b0, sound_wren2 = 1'b0, sound_wren3 = 1'b0, sound_wren4 = 1'b0;
reg[15:0] sound_in1 = 16'd0, sound_in2 = 16'd0, sound_in3 = 16'd0, sound_in4 = 16'd0;


wire sound_write_ready;
wire[15:0] sound_l_out;
wire[15:0] sound_r_out;

sound sound
(           
 .clk_sys           (clk_sys),     
 .clk_audio         (CLK_AUDIO),        
 .vga_frame         (vga_frame),        
 .vga_vcount        (vga_vcount),       
 .vga_interlaced    (PoC_interlaced),   
 .sound_reset       (sound_reset),
 .sound_synced      (vram_synced & !vga_frameskip),
 .sound_enabled     (hps_audio),
 .sound_rate        (sound_rate),
 .sound_chan        (sound_chan),
 .sound_buffer      (hps_audio_buffer),       
 .sound_wren1       (sound_wren1),           
 .sound_in1         (sound_in1),        
 .sound_wren2       (sound_wren2),           
 .sound_in2         (sound_in2),               
 .sound_wren3       (sound_wren3),           
 .sound_in3         (sound_in3),        
 .sound_wren4       (sound_wren4),           
 .sound_in4         (sound_in4),               
 .sound_write_ready (sound_write_ready),                         
 .sound_l_out       (sound_l_out),
 .sound_r_out       (sound_r_out)        
);

/////////////////////////////////// LZ4 ///////////////////////////////////////////////////

reg lz4_reset = 1, lz4_run = 0, lz4_write_long = 0, lz4_stop = 0;
reg[31:0] lz4_compressed_bytes = 0;
reg[63:0] lz4_compressed_long = 0;
wire lz4_write_ready, lz4_byte_valid, lz4_long_valid, lz4_paused, lz4_done, lz4_error, lz4_read_ready;
wire[7:0] lz4_uncompressed_byte;
wire[63:0] lz4_uncompressed_long;
wire [31:0] lz4_uncompressed_bytes, lz4_readed_bytes, lz4_writed_bytes;
wire[3:0] lz4_state;

lz4 lz4
(           
 .lz4_clk                (clk_sys),     
 .lz4_reset              (lz4_reset), 
 .lz4_mode_64            (1'b1),    
 .lz4_run                (lz4_run),     
 .lz4_stop               (ddr_data_write && ddr_busy ? 1'b1 : lz4_stop), // last uncompressed not writed!
 .lz4_compressed_bytes   (lz4_compressed_bytes),       
 .lz4_compressed_long    (lz4_compressed_long),
 .lz4_write_long         (lz4_write_long),
 .lz4_write_ready        (lz4_write_ready),
 .lz4_uncompressed_byte  (lz4_uncompressed_byte),
 .lz4_byte_valid         (lz4_byte_valid),               
 .lz4_uncompressed_long  (lz4_uncompressed_long),
 .lz4_long_valid         (lz4_long_valid),               
 .lz4_uncompressed_bytes (lz4_uncompressed_bytes),           
 .lz4_paused             (lz4_paused),        
 .lz4_done               (lz4_done),               
 .lz4_error              (lz4_error),
 .lz4_state              (lz4_state), 
 .lz4_writed_bytes       (lz4_writed_bytes),
 .lz4_readed_bytes       (lz4_readed_bytes),
 .lz4_read_ready         (lz4_read_ready)                     
);   

       
endmodule

