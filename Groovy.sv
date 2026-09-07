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

`include "build_id.v" 
localparam CONF_STR = {
   "GroovyNLC;;",
   "-;",   
   "FC1,GMC,Load Gmc;",
   "-;",  
   "P1,Video;",   
   "P1O[4:3],Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",  
   "H0P1O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
   "H0P1O[6:5],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",          
   "H0P1O[10],Orientation,Horz,Vert;",
   "H0P1-;",
   "H1P1O[11],240p Crop,Off,On;",
   "H2P1O[16:12],Crop Offset,0,+1,+2,+3,+4,+5,+6,+7,+8,-8,-7,-6,-5,-4,-3,-2,-1;",     
   "P1-;",  
   "P1O[21:17],CRT H offset,0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12,-13,-14,-15,+16,+15,+14,+13,+12,+11,+10,+9,+8,+7,+6,+5,+4,+3,+2,+1;",  
   "P1O[26:22],CRT V offset,0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12,-13,-14,-15,+16,+15,+14,+13,+12,+11,+10,+9,+8,+7,+6,+5,+4,+3,+2,+1;",  
   "H8P1O[47],CRT scale enable, Off,On;",  
   "H3P1O[51:48],CRT scale factor,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
   "P1-;",
   "P1O[37],PWM,Off,On;",
   "P1-;",
   "D4P1-,Debug options;",
   "P1O[32],Volatile framebuffer,Off,On;",    
   "P1O[31:30],Framebuffer lead,1,4,8,16;",
   "P1O[46],Vsync overlay,Off,On;",
	"P1-;",
	"DBP1O[57:56],RGB mode,888,A888,565;",
	"DCP1O[58],LZ4 frames,Off,On;",
   "-;",  
   "P2,Audio;",
   "P2O[34],Audio,Off,On;",
   "P2O[36:35],Desired buffer (ms),0,16,32,64;",   
	"P2-;",
	"D9P2O[53:52],Rate,-,22050,44100,48000;",
	"DAP2O[55:54],Channels,-,1,2;",
   "-;",
   "P3,Server;",         
   "P3O[33],Screensaver,On,Off;",   
   "P3O[45:44],ARM clock,Stock,+200Mhz,+400Mhz;",
   "P3O[42],Jumbo frames (Max MTU),Off,On;",
   // The shortest value here is the floor a CAP_KEEPALIVE client must beat: it cannot read this
   // setting, so it has to assume the worst case and send keepalives more often than that.
   // Adding a shorter option silently breaks every client already in the field - version the
   // capability bit (groovy.cpp CAP_KEEPALIVE) if that is ever needed.
   "P3O[8:7],Idle timeout,5s,10s,15s,Off;",
   "P3-;",
   "D5P3-,Send inputs;",
   "P3O[39:38],PS2,Off,Keyboard,Keyboard & Mouse;",
   "P3O[41:40],Joysticks,Off,Digital,Analog;",
   "P3-;",
   "D6P3-,Debug options;",
   "P3O[28:27],Verbose,Off,1,2,3;",
   "P3O[29],Blit at,ASAP,End Line;", 
	"DDP3O[59],Server type,UDP,XDP;",
   "P3-;",	 
   "D7P3-,Save and reload to apply!;",
   "-;",
   "J1,Button 1,Button 2,Button 3,Button 4,Button 5,Button 6,Button 7,Button 8, Button 9, Button 10;",        
   "J2,Button 1,Button 2,Button 3,Button 4,Button 5,Button 6,Button 7,Button 8, Button 9, Button 10;",     
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

wire        allow_crop_240p = ~forced_scandoubler && scale == 0 && !direct_video;
wire        crop_240p = allow_crop_240p & status[11];
wire [4:0]  crop_offset = status[16:12] < 9 ? {status[16:12]} : ( status[16:12] + 5'd15 );
wire        hps_frameskip = !status[32];
wire        hps_audio = status[34];
wire [1:0]  hps_audio_buffer = status[36:35];
wire        hps_pwm = status[37];
wire        hps_vsync_overlay = status[46];

wire [60:0] status;

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
   .status_menumask(status_menumask), 
        
   .joystick_0(joy0),
   .joystick_1(joy1)
     
);

// OSD option visibility
wire [15:0] status_menumask; // a high value hides the menu item

assign status_menumask[15] = 0, 
       status_menumask[14] = 0, 
       status_menumask[13] = 1, 
       status_menumask[12] = 1, 
       status_menumask[11] = 1, 
       status_menumask[10] = 1, 
       status_menumask[9]  = 1, 
       status_menumask[8]  = 0, //atm, CRT scale don't support interlaced
       status_menumask[7]  = 1,
       status_menumask[6]  = 1,
       status_menumask[5]  = 1,
       status_menumask[4]  = 1, 
       status_menumask[3]  = ~hsize_enable, 		
       status_menumask[2]  = ~crop_240p, 
       status_menumask[1]  = ~allow_crop_240p, 
       status_menumask[0]  = direct_video;

////////////////////////////  HPS I/O  EXT ///////////////////////////////////



wire [35:0] EXT_BUS;
reg  reset_switchres = 0, vga_frameskip = 0, vga_frameskip_prev = 0, reset_blit = 0, auto_blit = 0, reset_audio = 0, cmd_fskip = 0, reset_blit_lz4 = 0, auto_blit_lz4 = 0; 
wire cmd_init, cmd_switchres, cmd_blit, cmd_logo, cmd_audio, cmd_blit_lz4, cmd_blit_vsync; 
wire [15:0] audio_samples;
wire [1:0] sound_rate, sound_chan, rgb_mode, lz4_field, lz4_ABCD;
wire lz4_delta;
wire [31:0] lz4_size, switchres_frame;
wire [1:0] codec_mode, nlc_near;   // codec_mode: 0=raw 1=LZ4 2=NLC (from hps_ext init word)
wire nlc_color;
wire [1:0] nlc_disp_mode;          // NLC display path: 0=streaming, 1=throttled (retired), 2=autonomous (init word [7:6])
wire nlc_rice;                     // NLC entropy pack: 1=Golomb-Rice, 0=TILED (init word [8])

// ---- wedge telemetry (declared here so hps_ext/ddr_mux2/ddram ports see real nets;
// composed and driven at the bottom of the module, next to the engine instance).
// These must stay pipelined. Feeding hps_ext combinational concatenations of registers spread
// across the whole die (ddram, mux, engine, FSM) costs the build its timing closure, and the
// silicon then shows data corruption with healthy control flow, which presents as a black
// screen. All telemetry is therefore aggregated through the dbg_*_r pipeline registers:
// telemetry tolerates one or two cycles of staleness, and each cross-module route gets its own
// full clock period. ----
wire [1:0]  dbg_mux_grant;                  // ddr_mux2 grant state (G_M0/G_PEND/G_M1/G_DRAIN)
wire [2:0]  dbg_ddram_state;                // {read_req, ddram state[1:0]}
wire [3:0]  dbg_ddr_timeout_cnt;            // ddram read-watchdog fires (saturating)
reg  [15:0] dbg_live_a_r = 16'd0, dbg_live_b_r = 16'd0;   // pipelined words 10/11
reg  [15:0] dbg_w12_r = 16'd0, dbg_w13_r = 16'd0;         // words 12/13 (frz latch or live eng info)
reg  [15:0] dbg_frz_a = 16'd0, dbg_frz_b = 16'd0;         // first-freeze latch
reg  [3:0]  dbg_wd_cnt = 4'd0;
reg  [7:0]  dbg_syncloss_cnt = 8'd0;      // 4 bits saturate seconds into a fault; 8 covers a whole session
reg  [15:0] dbg_w14_r = 16'd0;            // word 14: longest starved-pixel run
reg  [15:0] dbg_starve_frm = 16'd0, dbg_starve_max = 16'd0;
reg         dbg_starve_r = 1'b0;          // pipeline stage 1 for the vga.v starve strobe
reg  [3:0]  dbg_done_cnt = 4'd0;            // rolling count of engine done_stb (shows the publish rate)
reg         dbg_freeze_valid = 1'b0;        // the latch holds a captured freeze
reg         dbg_freeze_hit = 1'b0;          // 1-cycle pulse -> FSM liveness net (vram_reset)
reg  [1:0]  dbg_freeze_frames = 2'd0;
reg  [23:0] dbg_prev_px = 24'd0;
// input pipeline stage (cuts the vga.v/engine -> detector routes)
reg  [23:0] dbg_px_r = 24'd0;
reg  [15:0] dbg_engfr_r = 16'd0;
reg  [15:0] dbg_flush_r = 16'd0;
reg         dbg_sync_r = 1'b1, dbg_vb_r = 1'b0;

hps_ext hps_ext
(
        .clk_sys(clk_sys),
        .EXT_BUS(EXT_BUS),
        .state(state),		  
        .hps_rise(1'b1),        	  
        .hps_audio(hps_audio),  	 
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
        .codec_mode(codec_mode),
        .nlc_near(nlc_near),
        .nlc_color(nlc_color),
        .nlc_disp_mode(nlc_disp_mode),
        .nlc_rice(nlc_rice),
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
		  .lz4_delta(lz4_delta),
        .lz4_uncompressed_bytes(lz4_uncompressed_bytes),
        .cmd_blit_vsync (cmd_blit_vsync),
        .dbg_live_a(dbg_live_a_r),
        .dbg_live_b(dbg_live_b_r),
        .dbg_frz_a(dbg_w12_r),
        .dbg_frz_b(dbg_w13_r),
        .dbg_w14(dbg_w14_r)
/* debug
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
        .PoC_subframe_blit_lz4(PoC_subframe_blit_lz4) 
*/                      
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

wire ce_pix, ce_pix2;

reg [7:0] ce_pix_arm;
assign ce_pix_arm = cmd_scandoubler && PoC_pll_S ? (PoC_ce_pix >> 1) - 1'd1 : PoC_ce_pix - 1'd1; 

reg [3:0] cencnt = 4'd0;

always @(posedge clk_sys) begin     
         cencnt <= cencnt==ce_pix_arm ? 4'd0 : (cencnt+4'd1);             
end

always @(posedge clk_sys) begin
    ce_pix  <= cencnt == 4'd0;      
    ce_pix2 <= cencnt == (ce_pix_arm >> 1) - 1'b1;     
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


// NLC mode 2: two-master DDR arbiter. M0 is this blit FSM (bit-transparent, priority),
// M1 is the autonomous NLC decode engine (idle in modes 0 and 1). Grant contract in rtl/ddr_mux2.v.
wire [27:1] ddrm_addr;
wire [63:0] ddrm_din;
wire        ddrm_rd, ddrm_wr;
wire [7:0]  ddrm_burst;
wire        ddrm_busy, ddrm_dready;
// engine master port (driven by u_eng, the mode-2 autonomous decode engine, instantiated below)
wire        eng_req;
wire        eng_gnt;
wire [27:1] eng_addr;
wire [63:0] eng_din;
wire        eng_rd, eng_wr;
wire [7:0]  eng_burst;
wire        eng_busy, eng_dready;

ddr_mux2 ddr_mux
(
        .clk(clk_sys),
        .m0_addr(ddr_addr[27:1]),
        .m0_din(ddr_data_to_write),
        .m0_rd(ddr_data_req),
        .m0_burst(ddr_burst),
        .m0_wr(ddr_data_write),
        .m0_busy(ddr_busy),
        .m0_dready(ddr_data_ready),
        .m1_req(eng_req),
        .m1_gnt(eng_gnt),
        .m1_addr(eng_addr),
        .m1_din(eng_din),
        .m1_rd(eng_rd),
        .m1_burst(eng_burst),
        .m1_wr(eng_wr),
        .m1_busy(eng_busy),
        .m1_dready(eng_dready),
        .mem_addr(ddrm_addr),
        .mem_din(ddrm_din),
        .mem_rd(ddrm_rd),
        .mem_burst(ddrm_burst),
        .mem_wr(ddrm_wr),
        .mem_busy(ddrm_busy),
        .mem_dready(ddrm_dready),
        .dbg_grant(dbg_mux_grant)
);

ddram ddram
(
        .*,
        .mem_addr(ddrm_addr),
        .mem_dout(ddr_data),
        .mem_din(ddrm_din),
        .mem_rd(ddrm_rd),
        .mem_burst(ddrm_burst),
        .mem_wr(ddrm_wr),
        .mem_busy(ddrm_busy),
        .mem_dready(ddrm_dready),
        .dbg_state(dbg_ddram_state),
        .dbg_timeout_cnt(dbg_ddr_timeout_cnt)
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

// FrameSkip (non Volatile)
// Lines of VRAM the auto-blit keeps ahead of the beam, selected in the OSD (Framebuffer lead).
// One line is about 30us of slack against a FIFO that holds 154 lines at 640 wide, so any DDR
// stall longer than a line time starves the beam. Reading further ahead does not delay the
// display, which the raster still times, but it does move the decoder's deadline for each line
// the same distance earlier, spending the host's delivery budget: 1/4/8/16 lines costs
// 31.8/127/254/508us at 640x480p60, which is 0.2/0.8/1.5/3.0 percent of a frame.
// Every value is a power of two, so the products below stay shifts. Latched in S_Idle, which
// runs while cmd_init is low, to keep it fixed for a session rather than moving under the
// trigger mid-frame.
reg  [2:0]  autoblit_sh = 3'd0;                    // 0,2,3,4 -> lead 1,4,8,16
wire [23:0] autoblit_lead = 24'd1 << autoblit_sh;
wire [2:0]  autoblit_sh_sel = status[31:30] == 2'd0 ? 3'd0 :   // 1 line
                              status[31:30] == 2'd1 ? 3'd2 :   // 4
                              status[31:30] == 2'd2 ? 3'd3 :   // 8
                                                      3'd4;    // 16
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

// NLC (block-adaptive near-lossless) blit: dedicated FB-only path, codec_mode==2. 8'd80-85
parameter S_Blit_Header_NLC       = 8'd80;
parameter S_Blit_Setup_NLC        = 8'd81;
parameter S_Blit_Prepare_NLC      = 8'd82;
parameter S_Blit_Copy_NLC         = 8'd83;
parameter S_Blit_Inflate_NLC      = 8'd84;
parameter S_Blit_End_NLC          = 8'd85;
parameter S_Blit_Flush_NLC        = 8'd86;   // STAGE 1: burst-write the accumulated line chunk to the FB
parameter S_Blit_Present_NLC      = 8'd87;   // mode 2: engine-completed frame in the FB -> RAW-style blit

// LZ4 Blit_Delta
parameter S_Delta_Prepare         = 8'd60; 
parameter S_Delta_Copy            = 8'd61; 

// Audio
parameter S_Audio_Prepare         = 8'd70; 
parameter S_Audio_Copy            = 8'd71; 
parameter S_Audio_End             = 8'd72; 

/////////////////////////// REGS ////////////////////////////////////////////
  
reg [7:0] state     = S_Idle;  

// Header from arm
reg [23:0] PoC_frame_ddr       = 24'd0;
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
reg [23:0] PoC_frame_vram = 24'd0;

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
reg [31:0] PoC_subframe_lz4_ddr_bytes = 32'd0;
reg [15:0] PoC_subframe_blit_lz4_ddr = 16'd0;
reg [27:0] PoC_subframe_wr_bytes = 28'd0;

reg        PoC_frame_lz4_FB = 1'b0;
reg        PoC_lz4_resume_blit = 1'b0;
reg        PoC_lz4_resume_audio = 1'b0;
reg [23:0] PoC_subframe_px_lz4 = 24'd0;

reg        PoC_lz4_delta = 1'b0;
reg [6:0]  PoC_lz4_delta_index = 7'd0;
reg [63:0] PoC_lz4_delta_FB[128];
reg        PoC_lz4_delta_req;
reg [27:0] PoC_lz4_delta_bytes = 28'd0;

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
      if (vga_vcount <= PoC_interlaced && (vram_queue == 24'd0 || !vram_synced)) begin // frame end: vram empty, or a deferred starve to flush
        cmd_fskip             <= 1'b1;          
        PoC_state_frameskip   <= S_Blit_Auto_First;     
      end else
      if (!vblank_core) begin
        if (vga_vcount + autoblit_lead + PoC_interlaced >= PoC_V && (PoC_H << autoblit_sh) > vram_queue && vram_queue + 20 < vram_pixels && vga_pixels > vram_pixels && vram_pixels > (PoC_H << 2)) begin // last lines interlaced
            cmd_fskip           <= 1'b1;     
            PoC_state_frameskip <= S_Blit_Auto_End;
        end else
        if (vga_vcount + autoblit_lead + PoC_interlaced < PoC_V && (PoC_H << autoblit_sh) > vram_queue && vram_queue + 20 < vram_pixels && ((PoC_H * (vga_vcount + autoblit_lead + PoC_interlaced)) >> PoC_FB_interlaced) > vram_pixels) begin // next lines
            cmd_fskip           <= 1'b1;                 
            PoC_state_frameskip <= S_Blit_Auto_Line;
        end 
      end 
    end 
       

  // Mode-2 engine handshake service (every cycle, state-independent). The engine runs the
  // decode in the background; this block just ferries announces and completions between it and
  // the FSM. Later same-cycle writes in the case body override these defaults, since Verilog is
  // last-assignment-wins, which is exactly what the newest-wins pend policy wants.
  eng_wm_stb <= 1'b0;
  if (eng_adopt_ack) eng_pend_valid <= 1'b0;
  if (eng_done_stb) begin
    // host-space status (WaitSync/GET_STATUS pacing) advances on every completion
    if (eng_cur_frame > PoC_frame_lz4) PoC_frame_lz4 <= eng_cur_frame;
    // present-blit only to BOOTSTRAP the raster (frame 1 / post-switchres re-lock): once the
    // display runs, the frameskip auto-blit shows the FB continuously, which is the established
    // architecture: a mode-2 run displays 11 frames in 12 through repeats alone. A per-frame VRAM
    // present would fight those repeats for VRAM and produce the mid-scan band artefact.
    if (PoC_frame_vram == 24'd0 || vga_soft_reset) nlc_present_pending <= 1'b1;
    nlc_present_frame   <= eng_cur_frame;
  end
  // keep-alive: while the engine decodes, keep the dispatcher re-reading the announce header.
  // Same-frame chunk growth and the 65535 sentinel arrive as header rewrites with no new cmd
  // pulse. Must live HERE (continuous), not in the Header visit: at the first visit the engine
  // has not adopted yet (busy=0), which latched the keep-alive off and starved multi-chunk
  // frames at exactly one chunk (the 480i wedge). Mode-0/1 states override this default below.
  if (codec_mode == 2'd2 && nlc_disp_mode == 2'd2) auto_blit_lz4 <= eng_busy_w;
  // abort: session closed or a modeline is being applied -> wind the engine down; hold until idle
  eng_abort_r <= (eng_abort_r || !cmd_init || reset_switchres) && eng_busy_w;
  if (!cmd_init || reset_switchres) begin
    eng_pend_valid      <= 1'b0;
    nlc_present_pending <= 1'b0;
    nlc_present_active  <= 1'b0;
  end

   // case -> only evaluates first match (break implicit), if not then default
   case (state)
   
         S_Idle: // start?                         
         begin          			 
           //error_overlay              <= 1'b0;         
           {r_in, g_in, b_in}         <= {8'h00,8'h00,8'h00};                                            
           vga_reset                  <= 1'b0;
           vga_frame_reset            <= 1'b1;
           vga_soft_reset             <= 1'b0;
           vga_wait_vblank            <= 1'b0;
           vga_frameskip              <= 1'b0;
           vga_frameskip_prev         <= 1'b0;
           autoblit_sh                <= autoblit_sh_sel;
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
           PoC_frame_vram             <= 24'd0;            
           PoC_frame_ddr              <= 24'd0;           
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
           PoC_subframe_lz4_ddr_bytes <= 32'd0;       
           PoC_subframe_blit_lz4_ddr  <= 16'd0;
           PoC_subframe_wr_bytes      <= 28'd0;        
           PoC_frame_lz4_FB           <= 1'b0;          
           PoC_lz4_resume_blit        <= 1'b0;
           PoC_lz4_resume_audio       <= 1'b0;
           PoC_subframe_px_lz4        <= 24'd0;
           PoC_lz4_ABCD               <= 2'd0;
           PoC_lz4_field              <= 2'd0;          
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
             if (cmd_switchres && switchres_frame <= vga_frame && (vga_vcount > PoC_V || vga_frame == 0)) begin  // request modeline (apply after blit)  
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
             if (codec_mode == 2'd2 && nlc_disp_mode == 2'd2 && (nlc_present_pending || nlc_present_active) && !vga_frameskip) begin
               // mode 2: an engine-completed NLC frame sits in the FB, so present it RAW-style
               state                 <= S_Blit_Present_NLC;
             end else
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
               state              <= (codec_mode == 2'd2) ? S_Blit_Header_NLC : S_Blit_Header_Lz4; // host-driven codec select (NLC reuses the LZ4 transport)
             end
           end
         end     
       
         S_Blit_Header_Raw:  // header ready
         begin   
           if (ddr_busy) ddr_data_req <= 1'b0;                                                       
           reset_blit <= 1'b0;              
           vram_reset <= !vram_synced;          
           if (ddr_data_ready) begin    
             ddr_data_req <= 1'b0;      
             auto_blit    <= PoC_frame_vram >= ddr_data[23:0] || (!cmd_switchres && ddr_data[23:0] <= switchres_frame) ? 1'b0 : 1'b1;                           
             state        <= cmd_switchres && ddr_data[23:0] > switchres_frame && PoC_subframe_px_vram == 0 ? S_Dispatcher : S_Blit_Raw; 
             if ((!cmd_switchres && ddr_data[23:0] <= switchres_frame) || ddr_data[23:0] < vga_frame || ddr_data[23:0] < PoC_frame_ddr || ddr_data[23:0] < PoC_frame_vram || ((vblank_core || !vram_pixels || !vram_synced) && ddr_data[23:0] <= vga_frame)) begin //frame arrives later (discard contaminate vram -> latency)
               state                   <= S_Dispatcher;
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
               if (vram_queue == 0) vga_wait_vblank <= 1'b1;               
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
           if (vram_queue > PoC_H) vga_wait_vblank <= 1'b0;                    
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
             if (codec_mode == 2'd2) nlc_present_active <= 1'b0;   // mode 2: the present-blit completed
             state                   <= S_Dispatcher;
           end else state            <= cmd_audio ? S_Dispatcher : S_Blit_Prepare_Raw;
         end

         S_Blit_Auto_Skip:  // calculate pixels to get next line
         begin                                                               
           if (PoC_state_frameskip == S_Blit_Auto_First) PoC_px_frameskip <= ((PoC_H << autoblit_sh) << PoC_interlaced) + 24'd3;
           else if (PoC_state_frameskip == S_Blit_Auto_End) PoC_px_frameskip <= vga_pixels;
                else PoC_px_frameskip <= ((PoC_H * (vga_vcount + autoblit_lead + PoC_interlaced)) >> PoC_FB_interlaced) + 24'd3;                               
           state <= PoC_state_frameskip == S_Blit_Auto_First ? S_Blit_Auto_First : S_Blit_Auto_Line;                                                                               
         end            
         
         S_Blit_Auto_First:  // blit first line of the next frame with rgb of last
         begin                                                               
           vga_frameskip           <= 1'b1;                   
           PoC_frame_ddr           <= vga_frame + 1'b1;        
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
             PoC_frame_switchres <= vga_frame + 1'b1;           
             PoC_pll_S           <= (forced_scandoubler || scandoubler_fx != 2'b00) && ddr_data_tmp[152 +:08] == 2 ? 1'b1 : 1'b0;                              
                                                                                                 
             req_modeline    <= ~new_modeline; // update pll                         
             new_vmode       <= ~new_vmode;    // notify to osd           
             state           <= S_Switchres_Mode;                                                                    
           end                   
         end        
         
         S_Switchres_Mode: // apply change clk
         begin              
           vga_soft_reset             <= 1'b1; // raster to V + 1 and wait blit
           vram_reset                 <= 1'b1;             
           vga_frameskip              <= 1'b0;                  
           lz4_reset                  <= 1'b1;
           PoC_frame_ddr              <= vga_frame;
           PoC_frame_lz4_ddr          <= vga_frame;
           PoC_frame_lz4              <= vga_frame;
           PoC_frame_vram             <= 24'd0;   
           PoC_subframe_px_vram       <= 24'd0;   
           PoC_subframe_bl_vram       <= 16'd0;  
           PoC_subframe_lz4_ddr_bytes <= 32'd0;
           PoC_subframe_blit_lz4_ddr  <= 16'd0;                       
           PoC_subframe_blit_lz4      <= 16'd0;                     
           PoC_subframe_wr_bytes      <= 28'd0;         
           PoC_subframe_px_lz4        <= 24'd0;   
           PoC_lz4_resume_blit        <= 1'b0;   
           PoC_lz4_resume_audio       <= 1'b0;   
           vram_drive_lz4             <= 1'b0;             
           vram_drive_raw             <= 1'b0;             
           lz4_compressed_bytes       <= 32'd0;  
           auto_blit                  <= 1'b0;
           auto_blit_lz4              <= 1'b0;             
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
                   state <= (!vram_synced || vram_drive_raw || cmd_fskip || vga_frameskip || (cmd_switchres && ddr_data[23:0] > switchres_frame) || (!cmd_switchres && ddr_data[23:0] <= switchres_frame)) ? S_Dispatcher : S_Blit_Lz4; // if vram is controlled by fskip and this is a future frame, wait vblank
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
               if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_queue == 0) vga_wait_vblank <= 1'b1;
               PoC_subframe_px_lz4   <= 24'd0;                                                                                
               vga_frameskip_prev    <= 1'b0;                              
               PoC_subframe_wr_bytes <= 28'd0; 
               lz4_compressed_bytes  <= lz4_size;               
               lz4_reset             <= 1'b1;
               vram_reset            <= (!vram_drive_raw && vga_pixels != vram_pixels) ? 1'b1 : 1'b0; // prev. lz4 crushed?                 
               PoC_lz4_ABCD          <= lz4_ABCD; 
               PoC_lz4_field         <= lz4_field;   
               PoC_lz4_delta			 <= lz4_delta;		 
					PoC_lz4_delta_req		 <= lz4_delta;	
			      PoC_lz4_delta_bytes   <= (rgb_mode == 1) ? (vga_pixels << 2) : (rgb_mode == 2) ? (vga_pixels << 1) : (vga_pixels << 1) + vga_pixels;
               PoC_lz4_delta_FB[0]   <= 64'd0;
               PoC_lz4_delta_index   <= 7'd0;
             end                                                                    
             state                   <= PoC_subframe_blit_lz4_ddr == 65535 ? S_Blit_End_Lz4 : S_Blit_Prepare_Lz4;                                                                                                                                                                                   
           end                          
         end   

         S_Blit_Prepare_Lz4: // Prepare fetch ddr when lz4 it's ready to get max burst
         begin                                            
           ddr_data_req    <= 1'b0; 
           lz4_reset       <= 1'b0;
           vram_reset      <= 1'b0;                             
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
           lz4_write_long      <= 1'b0;                                                                                         
           lz4_stop            <= 1'b1;
           lz4_run             <= 1'b1;		       		  
           state               <= PoC_lz4_delta_req ? S_Delta_Prepare : S_Blit_Inflate_Lz4;        
         end
       
         S_Blit_Inflate_Lz4: // uncompress bytes 
         begin           
           vram_wren1      <= 1'b0;
           vram_wren2      <= 1'b0;
           vram_wren3      <= 1'b0;  
           vram_wren4      <= 1'b0;
			  ddr_data_write  <= ddr_data_write && ddr_busy ? 1'b1 : 1'b0;   // last uncompressed isnt writed yet; try again                        
			  
			  if (vram_queue > PoC_H) vga_wait_vblank <= 1'b0;  // wait vblank while lz4 can't uncompress H pixels
           if (!PoC_frame_lz4_FB) vga_soft_reset <= 1'b0;       			  
           if (!lz4_run && !(ddr_data_write && ddr_busy)) state <= S_Blit_End_Lz4;            
			  			  
			  lz4_run         <= !lz4_run || lz4_paused || lz4_done || cmd_fskip || cmd_audio || !cmd_init || !vram_synced || PoC_lz4_delta_req ? 1'b0 : 1'b1;
			  lz4_stop        <= !vram_req_ready && !PoC_frame_lz4_FB ? 1'b1 : 1'b0;			  
			  
           if (!PoC_lz4_delta_req && lz4_long_valid && lz4_uncompressed_bytes > PoC_subframe_wr_bytes && !(ddr_data_write && ddr_busy) && PoC_subframe_px_lz4 < vga_pixels) begin                                                            
           //update framebuffer                           
             PoC_subframe_wr_bytes <= PoC_subframe_wr_bytes + 8'd8;    
             if (PoC_lz4_field == 2'd2) begin                         
               ddr_addr            <= PoC_FB_interlaced && (PoC_frame_switchres + PoC_frame_lz4_ddr) % 2 == 1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end else begin
               ddr_addr            <= PoC_FB_interlaced && PoC_lz4_field == 2'd1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end 
             ddr_data_write        <= 1'b1;
             ddr_burst             <= 8'd1;   
				 ddr_data_to_write     <= lz4_uncompressed_long; 
             if (PoC_lz4_delta) begin				               				 								
				   PoC_lz4_delta_index   <= PoC_lz4_delta_index + 1'b1;	
	            PoC_lz4_delta_req     <= PoC_lz4_delta_index == 7'd127 ? 1'b1 : 1'b0; // we need read framebuffer to add frame delta
				 end 
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
           lz4_run               <= lz4_long_valid ? 1'b0 : 1'b1;      // follow uncompressing next word64 if possible
           lz4_stop              <= 1'b1;			  
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
               //error_overlay           <= !vram_synced || PoC_subframe_px_lz4 != vga_pixels ? 1'b1 : error_overlay;               
             end              
             if (PoC_frame_lz4_ddr > PoC_frame_lz4) PoC_frame_lz4 <= PoC_frame_lz4_ddr;         
             PoC_subframe_lz4_ddr_bytes <= 32'd0;
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
           end else state               <= (!cmd_init || cmd_fskip || cmd_audio) ? S_Dispatcher : PoC_lz4_delta_req ? S_Delta_Prepare : S_Blit_Prepare_Lz4;                                               
         end
         
         // ===================== NLC dedicated blit path (codec_mode==2) =====================
         // CLEAN FB-only NLC: decode compressed (LZ zones) -> framebuffer, then the auto-blit displays it
         // (decode is slower than the beam, so it can never stream live). Mirrors the LZ4 blit states but
         // feeds/drains u_nlc. NO dbuf, NO watchdog, NO live-streaming-to-VRAM, NO delta. Reuses the LZ4
         // bookkeeping (PoC_frame_lz4*/PoC_subframe_lz4_*, lz4_size/ABCD/field), codecs being mutually exclusive.
         S_Blit_Header_NLC:  // header ready
         begin
           nlc_out_ready  <= 1'b0; nlc_write_long <= 1'b0;
           if (ddr_busy) ddr_data_req <= 1'b0;
           reset_blit_lz4             <= 1'b0;
           vram_reset                 <= !vram_synced;
           // STREAMING (mirror LZ4): NLC decodes straight into the VRAM FIFO. Stream unless bootstrap/recover
           // (FB-mode only when VRAM isn't synced or RAW owns it). Streaming itself never caused the
           // frozen-framebuffer stall: the cause was the Inflate commit being gated on vram_req_ready, which
           // deadlocked at bootstrap. The fixed Inflate decouples commit (on long_valid) from advance (on
           // vram_req_ready) exactly like LZ4, so streaming is robust. NLC decodes at 11.8 Mpix/s against a
           // 240p beam at 6.9, so it keeps the sub-frame FIFO fed with no FB round-trip.
           // NLC 480i still needs FB-mode, because streaming fills VRAM linearly while the interlaced scanout
           // reads even and odd fields. That rework is deferred, so NLC runs progressive-only for now.
           PoC_frame_lz4_FB           <= (!vram_synced || vram_drive_raw) ? 1'b1 : 1'b0;
           if (ddr_data_ready) begin
             ddr_data_req             <= 1'b0;
             // Mode 2: hand the announce to the autonomous engine and return; the FSM never
             // decodes. Same-frame chunk growth -> watermark strobe; new frame -> newest-wins pend.
             // The stale-vs-switchres gate mirrors the mode-0 idle-adopt gate below.
             if (nlc_disp_mode == 2'd2) begin
               state         <= S_Dispatcher;
               // (keep-alive for header re-reads is maintained by the mode-2 service block above)
               if ((cmd_switchres && ddr_data[23:0] > switchres_frame) || (!cmd_switchres && ddr_data[23:0] <= switchres_frame)) begin
                 // held for a pending modeline / stale vs the applied one: ignore
               end else if (eng_busy_w && ddr_data[23:0] == eng_cur_frame) begin
                 eng_wm_bytes  <= ddr_data[47:24];
                 eng_wm_final  <= (ddr_data[63:48] == 16'd65535) || (ddr_data[47:24] >= lz4_size);
                 eng_wm_stb    <= 1'b1;
               end else if (ddr_data[23:0] > PoC_frame_lz4) begin
                 eng_pend_frame <= ddr_data[23:0];
                 eng_pend_bytes <= ddr_data[47:24];
                 eng_pend_size  <= lz4_size;
                 eng_pend_final <= (ddr_data[63:48] == 16'd65535) || (ddr_data[47:24] >= lz4_size);
                 eng_pend_src   <= lz4_ABCD == 2'd0 ? DDR_LZ_OFFSET_A : lz4_ABCD == 2'd1 ? DDR_LZ_OFFSET_B : lz4_ABCD == 2'd2 ? DDR_LZ_OFFSET_C : DDR_LZ_OFFSET_D;
                 eng_pend_dst   <= (lz4_field == 2'd2) ? ((PoC_FB_interlaced && (PoC_frame_switchres + ddr_data[23:0]) % 2 == 1) ? DDR_FD_OFFSET : DDR_FB_OFFSET)
                                                       : ((PoC_FB_interlaced && lz4_field == 2'd1) ? DDR_FD_OFFSET : DDR_FB_OFFSET);
                 eng_pend_fb    <= (vga_pixels << 1) + vga_pixels;
                 eng_pend_valid <= 1'b1;
               end
             end else begin
             // STAGE A: while a decode is in-flight keep re-entering the NLC path (auto_blit_lz4) so it gets
             // FSM time across dispatcher visits and RUNS TO COMPLETION; do NOT abandon it for a new frame.
             auto_blit_lz4            <= nlc_busy ? 1'b1 : 1'b0;
             if (nlc_busy) begin
               // DEFECT 1/4 FIX: in-flight -> resume this frame, IGNORE newer announces (no restart). A
               // same-frame chunk announce still grows this frame's fetch watermark.
               if (ddr_data[23:0] == nlc_cur_frame) begin
                 PoC_subframe_lz4_ddr_bytes <= ddr_data[47:24];
                 PoC_subframe_blit_lz4_ddr  <= ddr_data[63:48];
               end
               state <= S_Blit_Inflate_NLC;
             end else if (PoC_lz4_resume_audio) begin
               state <= S_Blit_Inflate_NLC;
             end else begin
               // decoder idle: adopt the newest announced frame and start a fresh decode
               state <= ((cmd_switchres && ddr_data[23:0] > switchres_frame) || (!cmd_switchres && ddr_data[23:0] <= switchres_frame)) ? S_Dispatcher : S_Blit_Setup_NLC;
               PoC_frame_lz4_ddr          <= ddr_data[23:0];
               PoC_subframe_lz4_ddr_bytes <= ddr_data[47:24];
               PoC_subframe_blit_lz4_ddr  <= ddr_data[47:24] == nlc_compressed_bytes ? PoC_subframe_blit_lz4 + 1'b1 : ddr_data[63:48];
             end
             end   // close the mode-0/1 (non-engine) branch
           end
         end

         S_Blit_Present_NLC: // mode 2: an engine-completed frame is in the FB, blit it exactly like RAW
         begin
           state <= S_Blit_Raw;
           if (nlc_present_pending) begin
             // START a fresh present. DISPLAY-space numbering, strictly ahead of both the raster
             // frame and the last published frame, because an equal frame number makes
             // S_Blit_Raw's guard silently skip the blit. No vram_reset and no forced wait_vblank
             // here: S_Blit_Raw primes itself when the queue is empty, and parking the raster
             // every frame truncates the bottom of the picture.
             nlc_present_pending     <= 1'b0;
             nlc_present_active      <= 1'b1;
             PoC_frame_ddr           <= (PoC_frame_vram >= vga_frame ? PoC_frame_vram : vga_frame) + 1'b1;
             PoC_subframe_px_ddr     <= vga_pixels;
             PoC_subframe_bl_ddr     <= 16'd1;
             PoC_subframe_px_vram    <= 24'd0;
             PoC_subframe_bl_vram    <= 16'd0;
             PoC_subframe_vram_bytes <= 28'd0;
             PoC_frame_rgb_offset    <= 2'd0;
             // No bootstrap park is needed here. vga_soft_reset parks the raster at v_cnt=V+1,
             // inside vblank (vga.v:714), so the first scan after release always starts at the top
             // of the frame, and S_Blit_Raw arms vga_wait_vblank itself when the queue is empty.
             // The brief black top and bottom seen at the start of a 480i pass is the CRT's
             // vertical lock settling after the codec-switch re-lock, not an RTL defect.
           end
           // Resume path (active, the blit yielded to audio/fskip): fall through to S_Blit_Raw,
           // whose guards continue from px_vram/vram_bytes exactly like a resumed RAW blit. If a
           // frameskip repeat published PoC_frame_vram past our frame meanwhile, the blit guard is
           // moot because the repeats already display this FB content, so drop the present.
           // Otherwise the Dispatcher->Present->Raw loop spins forever and starves the announce
           // branch below it, and the engine never re-adopts after frame 1.
           else if (!(PoC_frame_ddr > PoC_frame_vram)) begin
             nlc_present_active <= 1'b0;
             state              <= S_Dispatcher;
           end
         end

         S_Blit_Setup_NLC:  // reset the decoder for a new frame + init counters
         begin
           nlc_out_ready  <= 1'b0; nlc_write_long <= 1'b0;
           state      <= S_Dispatcher;
           vram_reset <= 1'b0;
           if (PoC_frame_lz4_ddr > PoC_frame_lz4 && (PoC_frame_lz4_ddr != nlc_cur_frame || nlc_long_valid || (PoC_subframe_lz4_ddr_bytes > nlc_writed_bytes && PoC_subframe_blit_lz4_ddr > PoC_subframe_blit_lz4))) begin
             if (nlc_writed_bytes == 0 || PoC_frame_lz4_ddr != nlc_cur_frame) begin
               nlc_cur_frame         <= PoC_frame_lz4_ddr;
               if (!vram_drive_raw) PoC_frame_rgb_offset <= 2'd0;
               if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_queue == 0) vga_wait_vblank <= 1'b1;   // STREAMING: prime VRAM before the beam scans (mirror LZ4 :1341)
               PoC_subframe_px_lz4   <= 24'd0;
               PoC_subframe_px_vram    <= 24'd0;
               PoC_subframe_vram_bytes <= 28'd0;
               PoC_subframe_blit_lz4 <= 16'd0;
               vga_frameskip_prev    <= 1'b0;
               PoC_subframe_wr_bytes <= 28'd0;
               nlc_compressed_bytes  <= lz4_size;
               nlc_reset             <= 1'b1;
               nlc_busy              <= 1'b1;   // STAGE A: decode now in-flight; run to completion before adopting a new frame
               auto_blit_lz4         <= 1'b1;   // arm the dispatcher keep-alive at decode start. Header only arms
                                                // it when nlc_busy was already 1, so a frame interrupted before any
                                                // re-entry parked in the Dispatcher until the next announce, about
                                                // 40ms at the sender cadence that exposed it
               nlc_stall_cnt         <= 21'd0;  // arm the liveness window fresh per frame
               nlc_lb_wcnt           <= 8'd0;   // STAGE 1: fresh chunk accumulator + flush pointer per frame
               nlc_flushed_bytes     <= 28'd0;
               nlc_flush_end         <= 1'b0; nlc_fl_pre <= 1'b0; nlc_fl_run <= 1'b0; nlc_lb_rd <= 8'd0;
               vram_reset            <= (!vram_drive_raw && vga_pixels != vram_pixels) ? 1'b1 : 1'b0;
               PoC_lz4_ABCD          <= lz4_ABCD;
               PoC_lz4_field         <= lz4_field;
             end
             state                   <= PoC_subframe_blit_lz4_ddr == 65535 ? S_Blit_End_NLC : S_Blit_Prepare_NLC;
           end
         end

         S_Blit_Prepare_NLC: // fetch a burst of compressed words from the LZ zone (FIFO-safe)
         begin
           nlc_out_ready  <= 1'b0; nlc_write_long <= 1'b0;
           ddr_data_req   <= 1'b0;
           nlc_reset      <= 1'b0;
           vram_reset     <= 1'b0;
           if (!cmd_audio && nlc_writed_bytes < PoC_subframe_lz4_ddr_bytes && (nlc_compressed_bytes == PoC_subframe_lz4_ddr_bytes || ((PoC_subframe_lz4_ddr_bytes - nlc_writed_bytes) >> 3) > 0)) begin
             if (!ddr_busy && nlc_write_ready) begin
               ddr_burst    <= PoC_subframe_lz4_ddr_bytes - nlc_writed_bytes > 24'd1023 ? 8'd128 : nlc_compressed_bytes == PoC_subframe_lz4_ddr_bytes ? ((nlc_compressed_bytes - nlc_writed_bytes) >> 3) + 8'd1 : (PoC_subframe_lz4_ddr_bytes - nlc_writed_bytes) >> 3;   // STAGE 2: 128-word feed bursts (the parallel decoder's input FIFO is 256 deep, write_ready = >=136 free)
               ddr_addr     <= PoC_lz4_ABCD == 0 ? DDR_LZ_OFFSET_A + nlc_writed_bytes : PoC_lz4_ABCD == 1 ? DDR_LZ_OFFSET_B + nlc_writed_bytes : PoC_lz4_ABCD == 2 ? DDR_LZ_OFFSET_C + nlc_writed_bytes : DDR_LZ_OFFSET_D + nlc_writed_bytes;
               ddr_data_req <= 1'b1;
               state        <= S_Blit_Copy_NLC;
             end
           end else if (nlc_long_valid) state <= S_Blit_Inflate_NLC;   // drain-race: commit the pending word
           else state   <= S_Dispatcher;
         end

         S_Blit_Copy_NLC: // feed the fetched word into the decoder
         begin
           nlc_out_ready  <= 1'b0;
           if (ddr_busy) ddr_data_req <= 1'b0;
           nlc_write_long <= 1'b0;
           if (ddr_data_ready) begin
             ddr_data_req        <= 1'b0;
             nlc_write_long      <= 1'b1;          // one accepted word (write_ready checked in Prepare)
             nlc_compressed_long <= ddr_data;
             if (!ddr_busy) state <= S_Blit_Inflate_NLC;
           end
         end

         S_Blit_Inflate_NLC: // STREAM decoded words to VRAM + ACCUMULATE the FB copy for a burst write (STAGE 1)
         begin
           vram_wren1 <= 1'b0; vram_wren2 <= 1'b0; vram_wren3 <= 1'b0; vram_wren4 <= 1'b0;
           nlc_write_long <= 1'b0;
           nlc_stall_cnt  <= nlc_stall_cnt + 1'b1;   // liveness tick (reset to 0 on each commit below)
           if (vram_queue > (PoC_H << 2)) vga_wait_vblank <= 1'b0;   // VRAM primed -> let the beam scan. DEEPER than
                                                              // LZ4's 1-line prime (:1408): NLC decode (2.09 cyc/px)
                                                              // is slower, so 1 line of buffer briefly underruns at
                                                              // frame boundaries, which shows as the end-of-frame
                                                              // sync drop. ~4 lines carries enough to cover the
                                                              // refill gap. Primes in ~0.1ms << vblank -> never hangs.
                                                              // (TUNABLE: deepen to <<3 if HW sync=0 still >0.)
           if (!PoC_frame_lz4_FB) vga_soft_reset <= 1'b0;      // release the raster soft-reset (mirror LZ4 :1409)
           // COMMIT decision (blocking temp so the exit routing below sees THIS cycle's commit). Same guards as
           // before: long_valid once via ub>wr_bytes, px<vga_pixels, and deliberately not vram_req_ready,
           // which is what caused the bootstrap deadlock. Plus chunk space (wcnt<NLC_CHUNK: no commit while
           // the chunk awaits its flush). There is no !(ddr_data_write&&ddr_busy) term because Inflate no
           // longer issues DDR writes, the flush does, so the decoder no longer freezes per FB write and
           // only pauses during the per-chunk flush.
           // Mode 1, the throttled path, is retired. It was intrinsically conflicted: the throttled stream
           // and the frameskip share one vram_queue counter, so no threshold both arms the frameskip
           // (under 1 line) and keeps the decode progressing (4 lines or more), which wedges. Its
           // `vram_queue < (PoC_H<<2)` term also put the fifo_vga queue counter straight into the vram_in
           // commit gating, which became the worst setup path at -0.410ns. Mode 2, the autonomous engine,
           // supersedes it, and nlc_disp_mode==1 now behaves as mode 0.
           nlc_m1_go = 1'b1;
           nlc_commit_v = nlc_long_valid && nlc_uncompressed_bytes > PoC_subframe_wr_bytes
                          && PoC_subframe_px_lz4 < vga_pixels && nlc_lb_wcnt < NLC_CHUNK && nlc_m1_go;
           // ADVANCE the decoder = mirror `lz4_run && !lz4_stop`: gate on VRAM readiness (streaming backpressure)
           // + chunk space (must match the commit gating or a consumed word would never be stored).
           nlc_out_ready  <= (vram_req_ready || PoC_frame_lz4_FB) && nlc_long_valid && (nlc_lb_wcnt < NLC_CHUNK) && nlc_m1_go ? 1'b1 : 1'b0;
           if (nlc_commit_v) begin
             nlc_lbuf[nlc_lb_wcnt] <= nlc_uncompressed_long;   // accumulate the FB copy (burst-written by the flush)
             nlc_lb_wcnt           <= nlc_lb_wcnt + 1'b1;
             PoC_subframe_wr_bytes <= PoC_subframe_wr_bytes + 8'd8;
             nlc_stall_cnt         <= 21'd0;   // progress -> reset the liveness window
             // Stream the decoded word straight into VRAM (mirror LZ4 :1432). This is the display, and keeps the
             // sub-frame FIFO fed ahead of the beam.
             if (!vram_drive_raw && !PoC_frame_lz4_FB && vram_synced && PoC_subframe_px_lz4 < vga_pixels) begin
               vram_drive_lz4          <= 1'b1;
               PoC_subframe_vram_bytes <= PoC_subframe_vram_bytes + 8'd8;
               decode_pixel(1'b1, nlc_uncompressed_long, vga_pixels);
             end
           end
           // EXITS (after the commit so the flush check sees the just-committed word). Any exit with accumulated
           // words FLUSHES FIRST (the FB byte-stream contract: all committed words land in DDR before leaving the
           // NLC path), then routes to End. A full chunk flushes and returns here.
           if (nlc_frame_done && !(ddr_data_write && ddr_busy)) begin
             state         <= (nlc_lb_wcnt != 8'd0 || nlc_commit_v) ? S_Blit_Flush_NLC : S_Blit_End_NLC;
             nlc_flush_end <= 1'b1; nlc_fl_pre <= 1'b0; nlc_fl_run <= 1'b0; nlc_lb_rd <= 8'd0;
           end
           else if (nlc_writed_bytes < PoC_subframe_lz4_ddr_bytes &&
                    ( (nlc_paused && !nlc_long_valid && !(ddr_data_write && ddr_busy))
                      || ((cmd_audio || cmd_fskip) && !(ddr_data_write && ddr_busy)) )) begin
             state         <= (nlc_lb_wcnt != 8'd0 || nlc_commit_v) ? S_Blit_Flush_NLC : S_Blit_End_NLC;
             nlc_flush_end <= 1'b1; nlc_fl_pre <= 1'b0; nlc_fl_run <= 1'b0; nlc_lb_rd <= 8'd0;
           end
           else if (nlc_lb_wcnt == NLC_CHUNK && !(ddr_data_write && ddr_busy)) begin   // chunk full -> flush, come back
             state         <= S_Blit_Flush_NLC;
             nlc_flush_end <= 1'b0; nlc_fl_pre <= 1'b0; nlc_fl_run <= 1'b0; nlc_lb_rd <= 8'd0;
           end
         end

         S_Blit_Flush_NLC: // burst-write the accumulated chunk to the FB: ONE DDR transaction of nlc_lb_wcnt beats
         begin
           vram_wren1 <= 1'b0; vram_wren2 <= 1'b0; vram_wren3 <= 1'b0; vram_wren4 <= 1'b0;
           nlc_out_ready <= 1'b0; nlc_write_long <= 1'b0;
           if (!nlc_fl_pre) begin
             // prime 1: aim the read port at word 0 (nlc_lb_q <- nlc_lbuf[0] at this edge); set up the transaction
             nlc_fl_pre <= 1'b1;
             ddr_burst  <= nlc_lb_wcnt;
             if (PoC_lz4_field == 2'd2) begin
               ddr_addr <= (PoC_FB_interlaced && (PoC_frame_switchres + PoC_frame_lz4_ddr) % 2 == 1 ? DDR_FD_OFFSET : DDR_FB_OFFSET) + nlc_flushed_bytes;
             end else begin
               ddr_addr <= (PoC_FB_interlaced && PoC_lz4_field == 2'd1 ? DDR_FD_OFFSET : DDR_FB_OFFSET) + nlc_flushed_bytes;
             end
           end else if (!nlc_fl_run) begin
             // prime 2: present word 0 (read port prefetches word 1)
             nlc_fl_run        <= 1'b1;
             ddr_data_to_write <= nlc_lb_q;
             ddr_data_write    <= 1'b1;
             nlc_lb_rd         <= 8'd0;
           end else if (ddr_data_write && !ddr_busy) begin      // beat nlc_lb_rd accepted this edge
             if (nlc_lb_rd == nlc_lb_wcnt - 1'b1) begin         // last beat -> transaction done
               ddr_data_write    <= 1'b0;
               nlc_flushed_bytes <= nlc_flushed_bytes + {17'd0, nlc_lb_wcnt, 3'b000};
               nlc_lb_wcnt       <= 8'd0;
               nlc_fl_pre        <= 1'b0; nlc_fl_run <= 1'b0; nlc_lb_rd <= 8'd0;
               state             <= nlc_flush_end ? S_Blit_End_NLC : S_Blit_Inflate_NLC;
             end else begin
               ddr_data_to_write <= nlc_lb_q;                   // next word (prefetched by the 1-ahead read port)
               ddr_addr          <= ddr_addr + 28'd8;
               nlc_lb_rd         <= nlc_lb_rd + 1'b1;
             end
           end
         end

         S_Blit_End_NLC: // finalize / fetch-more
         begin
           vram_wren1 <= 1'b0; vram_wren2 <= 1'b0; vram_wren3 <= 1'b0; vram_wren4 <= 1'b0;
           nlc_out_ready  <= 1'b0; nlc_write_long <= 1'b0;
           ddr_data_write <= 1'b0;
           PoC_lz4_resume_blit   <= cmd_fskip;
           PoC_lz4_resume_audio  <= cmd_audio;
           if (nlc_writed_bytes + 8'd7 >= PoC_subframe_lz4_ddr_bytes) PoC_subframe_blit_lz4 <= PoC_subframe_blit_lz4_ddr;
           // Complete on the same deterministic measure as Inflate (nlc_frame_done), not on a bare
           // `blit==65535`. For the slow NLC decode that sentinel arrives at about 3% of the frame, so
           // completing on it alone would publish a near-empty FB. nlc_frame_done means FB full, or
           // nlc_done, or a liveness stall.
           if (nlc_frame_done) begin
             if (vram_drive_lz4 && !cmd_fskip) begin
               // Streaming completed: the frame was decoded straight into VRAM during Inflate, so just publish
               // it (mirror LZ4 End :1451). This is the normal 240p path: no FB->VRAM blit, no DDR contention.
               if (PoC_frame_lz4_ddr > PoC_frame_vram) begin
                 PoC_frame_ddr         <= PoC_frame_lz4_ddr;
                 PoC_frame_vram        <= PoC_frame_lz4_ddr;
               end
               PoC_subframe_px_vram    <= 24'd0;
               PoC_subframe_vram_bytes <= 28'd0;
               PoC_frame_rgb_offset    <= 2'd0;
               vga_wait_vblank         <= 1'b0;
               vram_reset              <= (!vram_synced || PoC_subframe_px_lz4 != vga_pixels) ? 1'b1 : 1'b0;
             end else begin
               // FB-mode fallback (late frame, or VRAM not ready): present the FB via RAW's S_Blit_Raw,
               // aligned to a frame boundary. Park the raster, so vga.v holds its internal wait until the next
               // vblank, and clear the FIFO residue left by in-flight fskip repeats. Without this the blit
               // lands mid-scan, appended after repeat pixels, which produces the wrapped and segmented band
               // artefact. Note the number space: once repeats run, PoC_frame_vram lives in display-frame
               // numbering, because Auto_First publishes vga_frame+1. Present with the same numbering or
               // S_Blit_Raw's guard silently skips the blit and leaves a black parked frame.
               PoC_frame_ddr           <= vga_frame + 1'b1;
               PoC_subframe_px_ddr     <= vga_pixels;
               PoC_subframe_px_vram    <= 24'd0;
               PoC_subframe_bl_ddr     <= 16'd1;
               PoC_subframe_bl_vram    <= 16'd0;
               PoC_subframe_vram_bytes <= 28'd0;
               PoC_frame_rgb_offset    <= 2'd0;
               vga_wait_vblank         <= 1'b1;
               vram_reset              <= 1'b1;
             end
             if (PoC_frame_lz4_ddr > PoC_frame_lz4) PoC_frame_lz4 <= PoC_frame_lz4_ddr;
             PoC_subframe_lz4_ddr_bytes <= 32'd0;
             PoC_subframe_blit_lz4_ddr  <= 16'd0;
             PoC_subframe_blit_lz4      <= 16'd0;
             PoC_subframe_wr_bytes      <= 28'd0;
             PoC_subframe_px_lz4        <= 24'd0;
             PoC_lz4_resume_blit        <= 1'b0;
             PoC_lz4_resume_audio       <= 1'b0;
             nlc_reset                  <= 1'b1;
             nlc_busy                   <= 1'b0;   // frame complete -> ready to adopt the next
             nlc_compressed_bytes       <= 32'd0;
             auto_blit_lz4              <= 1'b0;
             nlc_lb_wcnt                <= 8'd0;   // STAGE 1: chunk accumulator idle for the next frame
             nlc_flushed_bytes          <= 28'd0;
             state                      <= (vram_drive_lz4 && !cmd_fskip) ? S_Dispatcher : S_Blit_Raw;
             vram_drive_lz4             <= 1'b0;   // release VRAM ownership for the next frame / repeats
           end else state               <= (!cmd_init || cmd_fskip || cmd_audio) ? S_Dispatcher : S_Blit_Prepare_NLC;
         end
         // =================== end NLC dedicated blit path ===================

			S_Delta_Prepare: // Prepare fetch ddr to get pixel from FB and add to lz4
         begin                                
           ddr_data_req      <= 1'b0;    
           PoC_lz4_delta_req <= 1'b0;			  
           if (!ddr_busy) begin                      
             ddr_burst    <= PoC_lz4_delta_bytes - PoC_subframe_wr_bytes > 24'd1023 ? 8'd128 : ((PoC_lz4_delta_bytes - PoC_subframe_wr_bytes) >> 3) + 1'b1;
				 if (PoC_lz4_field == 2'd2) begin                         
               ddr_addr            <= PoC_FB_interlaced && (PoC_frame_switchres + PoC_frame_lz4_ddr) % 2 == 1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end else begin
               ddr_addr            <= PoC_FB_interlaced && PoC_lz4_field == 2'd1 ? DDR_FD_OFFSET + PoC_subframe_wr_bytes : DDR_FB_OFFSET + PoC_subframe_wr_bytes; 
             end              
             ddr_data_req        <= 1'b1;    
				 PoC_lz4_delta_index	<= 7'd0;			 
             state        <= S_Delta_Copy;                                                                                                                
           end            
         end 		

		   S_Delta_Copy:
         begin        
           if (ddr_busy) ddr_data_req <= 1'b0;    			  
           if (ddr_data_ready) begin    
             ddr_data_req                          <= 1'b0;			
				 PoC_lz4_delta_FB[PoC_lz4_delta_index] <= ddr_data;             
             PoC_lz4_delta_index                   <= PoC_lz4_delta_index + 1'b1;                    
             if (!ddr_busy) begin 
				   PoC_lz4_delta_index    <= 7'd0;					
				   state                  <= S_Blit_Copy_End_Lz4;
				 end
           end
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

   // Display liveness net, the last safety layer: the freeze detector saw two or more
   // full frames of sync=0 with a frozen VRAM write counter while inited. Force the vram
   // resync here so no stuck or starved dispatch path can leave the display red forever;
   // the worst case is one repeated recovery attempt per 2-frame window. Placed after the
   // endcase so it overrides any same-cycle state assignment to vram_reset.
   if (dbg_freeze_hit) vram_reset <= 1'b1;

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
wire vram_starve;
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
wire[23:0] vga_frame;

reg[7:0] r_in = 8'h00, g_in = 8'h00, b_in = 8'h00; 
reg vram_wren1 = 1'b0, vram_wren2 = 1'b0, vram_wren3 = 1'b0, vram_wren4 = 1'b0;
reg[7:0] r_vram_in1 = 8'h00, r_vram_in2 = 8'h00, r_vram_in3 = 8'h00, r_vram_in4 = 8'h00;
reg[7:0] g_vram_in1 = 8'h00, g_vram_in2 = 8'h00, g_vram_in3 = 8'h00, g_vram_in4 = 8'h00;
reg[7:0] b_vram_in1 = 8'h00, b_vram_in2 = 8'h00, b_vram_in3 = 8'h00, b_vram_in4 = 8'h00;

//reg error_overlay = 1'b0;

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
 .cmd_blit_vsync (cmd_blit_vsync),    // blit command to know vga_vcount
 .vsync_skip     (vga_frameskip || !vram_synced),
 .vsync_overlay  (hps_vsync_overlay), // vsync overlay
 .vram_defer_sync(!vram_drive_lz4),   // defer on the framebuffer-fed path; LZ4 streaming keeps the immediate stop
 //.error_overlay  (error_overlay),
 .vram_ready     (vram_req_ready),    // vram it's ready to write a new pixel    
 .vram_end_frame (vram_end_frame),    // in vram there ara all pixels of current frame      
 .vram_synced    (vram_synced),       // vram it's synced on frame
 .vram_starve    (vram_starve),       // starve strobe -> starved-pixel telemetry
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

wire [4:0] hoffset = status[21:17];
wire [4:0] voffset = status[26:22];
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

// Horizontal scaling for CRT
wire       hsize_enable = status[47];
wire [3:0] hsize_scale = status[51:48];
wire       hsize_hs, hsize_vs, hsize_hb, hsize_vb;
wire [7:0] hsize_r, hsize_g, hsize_b;

 jtframe_hsize #(.COLORW(8)) u_hsize(
        .clk        ( clk_sys  ),
        .pxl_cen    ( ce_pix   ),
        .pxl2_cen   ( ce_pix2  ),

        .scale      ( hsize_scale  ),
        .offset     ( 5'd0         ),
        .enable     ( hsize_enable ),

        .r_in       ( r_core    ),
        .g_in       ( g_core    ),
        .b_in       ( b_core    ),
        .HS_in      ( hs_jt ),
        .VS_in      ( vs_jt ),
        .HB_in      ( hblank_core ),
        .VB_in      ( vblank_core ),
        // filtered video
        .HS_out     ( hsize_hs  ),
        .VS_out     ( hsize_vs  ),
        .HB_out     ( hsize_hb  ),
        .VB_out     ( hsize_vb  ),
        .r_out      ( hsize_r   ),
        .g_out      ( hsize_g   ),
        .b_out      ( hsize_b   )
    );

video_mixer #(640, 0, 1) video_mixer(
 .CLK_VIDEO(CLK_VIDEO),
 .CE_PIXEL(CE_PIXEL),
 .ce_pix(ce_pix),

 .scandoubler(PoC_interlaced && !PoC_FB_interlaced ? 1'b0 : (forced_scandoubler || scandoubler_fx != 2'b00)),
 .hq2x(0),

 .gamma_bus(gamma_bus),
 
 .R(hsize_r),
 .G(hsize_g),
 .B(hsize_b),

 .HBlank(hsize_hb),
 .VBlank(hsize_vb),
 .HSync(hsize_hs),
 .VSync(hsize_vs),

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
 .lz4_stop               ((ddr_data_write && ddr_busy) || (PoC_lz4_delta_req) ? 1'b1 : lz4_stop), // last uncompressed not writed!
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
 .lz4_read_ready         (lz4_read_ready),
 .lz4_delta_long         (PoC_lz4_delta_FB[PoC_lz4_delta_index])
);

// ---- NLC (block-adaptive near-lossless) decoder: clean FB-only path (codec_mode==2) ----
// Reuses the LZ4 blit transport (DDR-LZ zones + lz4_size announce); codec_mode selects this vs lz4.v.
// NLC always decodes to the framebuffer (decode is slower than the beam); the clean auto-blit displays it.
// No double buffer, no watchdog and no live streaming: the auto-blit is the only display path.
reg         nlc_reset            = 1'b1;
reg         nlc_write_long       = 1'b0;
reg  [63:0] nlc_compressed_long  = 64'd0;
reg  [31:0] nlc_compressed_bytes = 32'd0;
reg         nlc_out_ready        = 1'b0;
reg  [23:0] nlc_cur_frame        = 24'd0;
reg         nlc_busy             = 1'b0;   // STAGE A: a decode is in-flight (started, not yet nlc_done)
reg  [20:0] nlc_stall_cnt        = 21'd0;  // liveness: Inflate cycles without a commit. Threshold must EXCEED one
                                           // VBLANK (~1.4ms = ~120k cyc): the streaming decoder legitimately waits out
                                           // the whole blank with a full VRAM FIFO (no drain) at 480p. 2^20 = 12.7ms.
// ---- STAGE 1 BURST FB WRITES: accumulate decoded words in an on-chip line buffer; flush each full chunk as ONE
// DDR burst transaction. Calibrated against hardware: each single-beat write costs ~80 cycles of per-transaction
// f2sdram overhead, and at 28,800 writes per frame that is the measured NLC frame time of 40ms. Bursting
// amortizes it, taking 41ms down to roughly 7-10ms at 240p, which is 60fps. ----
localparam  NLC_CHUNK            = 8'd120;  // words per burst (960 B); linear chunking, resolution-agnostic
(* ramstyle = "M10K" *) reg [63:0] nlc_lbuf [0:127];   // 128x64 = one M10K (SDP: FSM writes, registered read)
reg  [63:0] nlc_lb_q;                      // registered read data (M10K recipe: NO reset, 1-ahead comb. address)
reg  [7:0]  nlc_lb_ra;                     // combinational read address (aimed one word ahead of the stream)
reg  [7:0]  nlc_lb_wcnt          = 8'd0;   // words accumulated in the chunk (0..NLC_CHUNK)
reg  [7:0]  nlc_lb_rd            = 8'd0;   // index of the word currently presented during a flush
reg  [27:0] nlc_flushed_bytes    = 28'd0;  // FB bytes actually burst-written to DDR (the flush address pointer)
reg         nlc_flush_end        = 1'b0;   // route after the flush: 1 -> S_Blit_End_NLC, 0 -> back to Inflate
reg         nlc_fl_pre           = 1'b0;   // flush prime 1 done (lb_q <- lbuf[0])
reg         nlc_fl_run           = 1'b0;   // flush streaming (word 0 presented)
reg         nlc_commit_v;                  // blocking temp: this cycle's Inflate commit fired
reg         nlc_m1_go;                     // blocking temp: mode-1 throttle gate (queue below the low threshold)
// flush read port: during streaming aim one ahead of the presented word (+2 across an accepted beat) so nlc_lb_q
// always holds the NEXT word; outside streaming park at 0 / 1 for the two prime cycles.
always @* begin
    if (state != S_Blit_Flush_NLC || !nlc_fl_pre) nlc_lb_ra = 8'd0;                      // idle / prime 1: fetch word 0
    else if (!nlc_fl_run)                         nlc_lb_ra = 8'd1;                      // prime 2: prefetch word 1
    else nlc_lb_ra = (ddr_data_write && !ddr_busy && nlc_lb_rd < nlc_lb_wcnt - 1'b1) ? nlc_lb_rd + 8'd2 : nlc_lb_rd + 8'd1;
end
always @(posedge clk_sys) nlc_lb_q <= nlc_lbuf[nlc_lb_ra];   // registered M10K read (no reset)
wire        nlc_write_ready, nlc_long_valid, nlc_paused, nlc_done;
wire [63:0] nlc_uncompressed_long;
wire [31:0] nlc_uncompressed_bytes, nlc_writed_bytes, nlc_readed_bytes;
// STAGE A2 robust completion: the FB is fully written (deterministic) OR the decoder signalled done OR the
// end-of-frame drain stalled past a bounded window. NLC must never wedge the display, the same
// guarantee LZ4 has via its 65535 escape). Decoder emits 3 bytes/pixel; a frame is vga_pixels*3 FB bytes.
wire [27:0] nlc_frame_bytes = (vga_pixels << 1) + vga_pixels;
wire        nlc_frame_done  = nlc_done
                            || (PoC_subframe_wr_bytes >= nlc_frame_bytes)
                            || (nlc_writed_bytes >= PoC_subframe_lz4_ddr_bytes && nlc_stall_cnt > 21'd1048575);

// ---- Mode 2: the autonomous decode engine and its FSM-side handshake registers ----
// The engine owns the decoder (via the input muxes below) and the DDR M1 port under
// nlc_disp_mode==2; modes 0 and 1 are untouched, with the muxes selecting the FSM's registers.
reg         eng_pend_valid = 1'b0, eng_pend_final = 1'b0;
reg  [23:0] eng_pend_frame = 24'd0;
reg  [31:0] eng_pend_size  = 32'd0, eng_pend_bytes = 32'd0;
reg  [27:0] eng_pend_src   = 28'd0, eng_pend_dst   = 28'd0, eng_pend_fb = 28'd0;
reg         eng_wm_stb     = 1'b0,  eng_wm_final   = 1'b0;
reg  [31:0] eng_wm_bytes   = 32'd0;
reg         eng_abort_r    = 1'b0;
reg         nlc_present_pending = 1'b0, nlc_present_active = 1'b0;
reg  [23:0] nlc_present_frame   = 24'd0;
wire        eng_adopt_ack, eng_busy_w, eng_done_stb, eng_wd_fired;
wire [23:0] eng_cur_frame;
wire [27:0] eng_flushed;
wire [3:0]  eng_st_w;
wire        eng_dec_reset, eng_dec_wlong, eng_dec_oready;
wire [63:0] eng_dec_clong;
wire        nlc_eng_sel = (nlc_disp_mode == 2'd2) && (codec_mode == 2'd2);

nlc_engine u_eng
(
 .clk            (clk_sys),
 .abort          (eng_abort_r),
 .pend_valid     (eng_pend_valid),
 .pend_frame     (eng_pend_frame),
 .pend_size      (eng_pend_size),
 .pend_bytes     (eng_pend_bytes),
 .pend_final     (eng_pend_final),
 .pend_src       (eng_pend_src),
 .pend_dst       (eng_pend_dst),
 .pend_fb_bytes  (eng_pend_fb),
 .adopt_ack      (eng_adopt_ack),
 .wm_stb         (eng_wm_stb),
 .wm_bytes       (eng_wm_bytes),
 .wm_final       (eng_wm_final),
 .dec_reset      (eng_dec_reset),
 .dec_clong      (eng_dec_clong),
 .dec_wlong      (eng_dec_wlong),
 .dec_wready     (nlc_write_ready),
 .dec_ulong      (nlc_uncompressed_long),
 .dec_lvalid     (nlc_long_valid),
 .dec_oready     (eng_dec_oready),
 .dec_writed     (nlc_writed_bytes),
 .dec_done       (nlc_done),
 .m_req          (eng_req),
 .m_gnt          (eng_gnt),
 .m_addr         (eng_addr),
 .m_din          (eng_din),
 .m_rd           (eng_rd),
 .m_burst        (eng_burst),
 .m_wr           (eng_wr),
 .m_busy         (eng_busy),
 .m_dready       (eng_dready),
 .m_dout         (ddr_data),
 .busy           (eng_busy_w),
 .done_stb       (eng_done_stb),
 .cur_frame      (eng_cur_frame),
 .flushed_bytes  (eng_flushed),
 .wd_fired       (eng_wd_fired),
 .eng_state      (eng_st_w)
);

// ---- wedge telemetry: live debug words, first-freeze latch, liveness pulse ----
// Fully pipelined; see the declaration-site comment for why. Sources are registered
// locally in stage 1 (dbg_px_r/engfr_r/flush_r/sync_r/vb_r), then aggregated into the
// hps_ext-facing word registers in stage 2. No combinational cross-module route
// reaches hps_ext or the freeze latch.
// Word 10 (live_a): [7:0] blit FSM state, [11:8] engine state, [13:12] ddr_mux2 grant,
//                   [15:14] ddram state.
// Word 11 (live_b): [0] ddram read_req, [1] eng busy, [2] eng pend_valid,
//                   [3] freeze latched, [7:4] engine wd_fired count (sat),
//                   [11:8] ddram read-watchdog count (sat),
//                   [15:12] engine done_stb rolling count, which shows the publish rate:
//                           it must tick about once per poll at 60Hz, and a frozen count
//                           means the engine is not completing frames.
// Word 12: frz latched ? freeze-time copy of word 10 : eng_cur_frame[15:0].
// Word 13: frz latched ? freeze context {vga_frame[11:0], audio, pend, busy, read_req}
//                      : {syncloss count, eng flushed_bytes[15:4]} (FB-write progress).
always @(posedge clk_sys) begin : dbg_pipe
  // stage 1: register remote sources locally
  dbg_px_r    <= vram_pixels;
  dbg_engfr_r <= eng_cur_frame[15:0];
  dbg_flush_r <= eng_flushed[19:4];
  dbg_sync_r  <= vram_synced;
  dbg_starve_r<= vram_starve;
  dbg_vb_r    <= vblank_core;
  // stage 2: aggregate into the hps_ext-facing words
  dbg_live_a_r <= {dbg_ddram_state[1:0], dbg_mux_grant, eng_st_w, state};
  dbg_live_b_r <= {dbg_done_cnt, dbg_ddr_timeout_cnt, dbg_wd_cnt,
                   dbg_freeze_valid, eng_pend_valid, eng_busy_w, dbg_ddram_state[2]};
  dbg_w12_r    <= dbg_freeze_valid ? dbg_frz_a : dbg_engfr_r;
  dbg_w13_r    <= dbg_freeze_valid ? dbg_frz_b : {dbg_syncloss_cnt, dbg_flush_r[7:0]};
  dbg_w14_r    <= dbg_starve_max;
end

always @(posedge clk_sys) begin : dbg_freeze_detect
  reg old_vb, old_wd, old_unsync;
  dbg_freeze_hit <= 1'b0;
  if (eng_done_stb) dbg_done_cnt <= dbg_done_cnt + 4'd1;   // rolling (wraps by design)
  if (eng_wd_fired && !old_wd && dbg_wd_cnt != 4'hF)      dbg_wd_cnt       <= dbg_wd_cnt + 4'd1;
  if (!dbg_sync_r && !old_unsync && dbg_syncloss_cnt != 8'hFF) dbg_syncloss_cnt <= dbg_syncloss_cnt + 8'd1;
  // Worst frame's starved-pixel total, rather than the longest contiguous run. The auto-blit
  // refills each line, so a long stall arrives as several runs of at most PoC_H, and a contiguous
  // measure would saturate at one line however big the stall was. The per-frame total scales with
  // the stall and compares directly against PoC_H * the selected lead, the budget it buys.
  if (ce_pix && dbg_starve_r) begin
    if (dbg_starve_frm != 16'hFFFF) dbg_starve_frm <= dbg_starve_frm + 16'd1;
    if (dbg_starve_frm >= dbg_starve_max) dbg_starve_max <= dbg_starve_frm + 16'd1;
  end
  if (dbg_vb_r && !old_vb) dbg_starve_frm <= 16'd0;   // per-frame accumulator
  if (dbg_vb_r && !old_vb) begin
    dbg_prev_px <= dbg_px_r;
    if (cmd_init && !dbg_sync_r && dbg_px_r == dbg_prev_px) begin
      if (dbg_freeze_frames == 2'd2) begin
        dbg_freeze_hit    <= 1'b1;          // -> FSM liveness net (vram_reset pulse)
        dbg_freeze_frames <= 2'd0;          // re-arm: retries every ~2 frames while stuck
        if (!dbg_freeze_valid) begin        // first occurrence: latch the scene
          dbg_freeze_valid <= 1'b1;
          dbg_frz_a        <= dbg_live_a_r;
          dbg_frz_b        <= {vga_frame[11:0], cmd_audio, eng_pend_valid, eng_busy_w, dbg_ddram_state[2]};
        end
      end else dbg_freeze_frames <= dbg_freeze_frames + 2'd1;
    end else dbg_freeze_frames <= 2'd0;
  end
  if (!cmd_init) begin
    dbg_freeze_valid  <= 1'b0;
    dbg_freeze_frames <= 2'd0;
    dbg_wd_cnt        <= 4'd0;
    dbg_syncloss_cnt  <= 8'd0;
    dbg_starve_frm    <= 16'd0;
    dbg_starve_max    <= 16'd0;
    dbg_done_cnt      <= 4'd0;
  end
  old_vb     <= dbg_vb_r;
  old_wd     <= eng_wd_fired;
  old_unsync <= !dbg_sync_r;
end

nlc_decode_ddr #(.MAXW(720), .WBITS(4), .NP(3)) u_nlc
(
 .clk                 (clk_sys),
 .reset               (nlc_eng_sel ? eng_dec_reset : nlc_reset),
 .cfg_w               (PoC_H),                          // active width (switchres)
 .cfg_h               (PoC_V >> PoC_FB_interlaced),     // field height when interlaced
 .cfg_near            ({1'b0, nlc_near}),
 .cfg_rice            (nlc_rice),
 .cfg_tile            (7'd16),
 .cfg_color           (nlc_color),
 .compressed_long     (nlc_eng_sel ? eng_dec_clong  : nlc_compressed_long),
 .write_long          (nlc_eng_sel ? eng_dec_wlong  : nlc_write_long),
 .write_ready         (nlc_write_ready),
 .out_ready           (nlc_eng_sel ? eng_dec_oready : nlc_out_ready),
 .uncompressed_long   (nlc_uncompressed_long),
 .long_valid          (nlc_long_valid),
 .uncompressed_bytes  (nlc_uncompressed_bytes),
 .writed_bytes        (nlc_writed_bytes),
 .readed_bytes        (nlc_readed_bytes),
 .paused              (nlc_paused),
 .done                (nlc_done)
);

endmodule

