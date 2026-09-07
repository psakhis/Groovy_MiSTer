// clean_disp_tb.v: frame-dumping sim of the upstream display stack:
// the REAL clean rtl/vga.v + rtl/fifo_vga.v + rtl/lz4.v + the clean blit FSM extracted VERBATIM from the
// clean Groovy.sv (sim/extract_clean_fsm.sh -> /tmp/clean_fsm_gen/*.vh). NO NLC, NO dbuf. Feeds RAW and
// real LZ4 frames the way the host does, and DUMPS the actual VGA_R/G/B output to one .ppm per frame so we
// can SEE what the sim displays and calibrate it against hardware on a known-good pathway.
//
// plusargs: +codec=0(RAW)|1(LZ4)  +frames=N  +cadence=C  +w=W +h=H  +interlace=0|2  +lz4hex=path  +debug=1
`timescale 1ns/1ps

module clean_disp_tb;
    integer N_FRAMES, CADENCE, CODEC, DEBUG, ILACE, W, H, CHUNK, NMARK, CEPIX, NLCMODE, CHUNKGAP;
    integer WMDROP, WMRACEG; reg WMRACE;
    // /58 reconnect repro: pulse cmd_init low/high + replay CmdSwitchres right after frame
    // RECONNECT_AFTER streams (0 = disabled, default). RECONNECT_LOWCYC = how long to hold cmd_init
    // low (mirrors the real setInit() forced edge landing over SPI, not an instant toggle).
    integer RECONNECT_AFTER, RECONNECT_LOWCYC, TRACE_WINDOW_CYC;
    reg        wmrace_pend = 0;          // a final watermark rewrite is deferred into the next announce
    reg [63:0] wmrace_hdr  = 0;
    integer HFP, HSv, HBP, VFP, VSv, VBP;     // modeline porches to send (defaults = real 720x480i)
    reg [2047:0] MDIR;                        // dir of nlc_synth marker_NNN.{raw,lz4}
    initial begin
        if (!$value$plusargs("frames=%d",   N_FRAMES)) N_FRAMES = 6;
        if (!$value$plusargs("nmark=%d",     NMARK))    NMARK    = 8;
        if (!$value$plusargs("mdir=%s",      MDIR))     MDIR     = "/tmp/markers";
        if (!$value$plusargs("cadence=%d",   CADENCE))  CADENCE  = 0;       // 0 => auto (one full frame period)
        if (!$value$plusargs("codec=%d",     CODEC))    CODEC    = 0;       // 0=RAW 1=LZ4
        if (!$value$plusargs("w=%d",         W))        W        = 320;
        if (!$value$plusargs("h=%d",         H))        H        = 240;
        if (!$value$plusargs("interlace=%d", ILACE))    ILACE    = 0;       // 0 progressive (simple frame dump)
        if (!$value$plusargs("chunk=%d",     CHUNK))    CHUNK    = 60000;
        if (!$value$plusargs("chunkgap=%d",  CHUNKGAP)) CHUNKGAP = 200;   // cycles between watermark announces (/56: HW ingest pacing)
        if (!$value$plusargs("cepix=%d",     CEPIX))    CEPIX    = 12;      // HW-faithful 240p beam (clk_sys/12); was wrongly 6 (2x too fast)
        if (!$value$plusargs("debug=%d",     DEBUG))    DEBUG    = 0;
        if (!$value$plusargs("nlcmode=%d",   NLCMODE))  NLCMODE  = 0;       // /46 NLC display mode (0=/45 stream)
        nlc_disp_mode = NLCMODE[1:0];
        $display("NLCMODE = %0d", NLCMODE);
        suppress_done = $test$plusargs("suppress_done");   // FAULT INJECTION: model HW where nlc_done never fires
        donly         = $test$plusargs("donly");           // OLD /36 completion (nlc_done only) for reproduction
        // /57 watermark-race fault injection (the trigger of the /57 E_RUN park): the frame's FINAL
        // watermark rewrite (wm==size / 65535 sentinel) is the ONLY carrier of input finality; if the
        // FSM never observes it the engine starves non-final. +wmdrop=F drops frame F's final rewrite
        // outright (deterministic); +wmrace defers EVERY frame's final rewrite into the next frame's
        // announce window, +wmracegap cycles ahead of it (HPS write-level back-to-back race, statistical).
        if (!$value$plusargs("wmdrop=%d",    WMDROP))   WMDROP   = 0;
        WMRACE = $test$plusargs("wmrace");
        if (!$value$plusargs("wmracegap=%d", WMRACEG))  WMRACEG  = 20;
        if (!$value$plusargs("reconnect_after=%d", RECONNECT_AFTER)) RECONNECT_AFTER = 0;
        if (!$value$plusargs("reconnect_lowcyc=%d", RECONNECT_LOWCYC)) RECONNECT_LOWCYC = 50;
        if (!$value$plusargs("trace_window=%d", TRACE_WINDOW_CYC)) TRACE_WINDOW_CYC = 3000000;
        if (!$value$plusargs("hfp=%d", HFP)) HFP = 29;
        if (!$value$plusargs("hs=%d",  HSv)) HSv = 69;
        if (!$value$plusargs("hbp=%d", HBP)) HBP = 117;
        if (!$value$plusargs("vfp=%d", VFP)) VFP = 3;
        if (!$value$plusargs("vs=%d",  VSv)) VSv = 6;
        if (!$value$plusargs("vbp=%d", VBP)) VBP = 34;
        if (!$value$plusargs("pll_glitch_ns=%d", PLL_GLITCH_NS)) PLL_GLITCH_NS = 0;
        if (!$value$plusargs("pll_glitch_period_ns=%d", PLL_GLITCH_PERIOD_NS)) PLL_GLITCH_PERIOD_NS = 6;
    end

    // /58 PLL-relock-gap repro: this sim cannot model a real analog PLL relock transient (Verilator
    // has no setup/hold-time concept) - but it CAN model the logical gap found in Groovy.sv: nothing
    // in the clk_sys domain ever waits for pll_locked before resuming after a CmdSwitchres replay
    // (S_Switchres_PLL -> S_Switchres_Mode unconditionally, Groovy.sv:1294). +pll_glitch_ns=N
    // (default 0 = disabled, no effect on any existing invocation) freezes clk_sys's toggling for N ns,
    // triggered right at a simulated reconnect's CmdSwitchres replay (do_reconnect, below), standing in
    // for "the real PLL output is unlocked/retuning here and nothing waits for it."
    // NOTE: force/release on clk_sys crashes Verilator internally ("destroy locked Thread Pool")
    // under --timing mode - not used. Restructuring the plain `always #6 clk_sys=~clk_sys` oscillator
    // into a conditional also costs a large (~15x) sim-speed regression (Verilator loses whatever
    // fast-path it has for the bare idiom) - accepted here deliberately since this is a one-off
    // diagnostic build, not the default; +pll_glitch_ns=0 (the default) restores the plain oscillator
    // behavior exactly, so unrelated/normal sim runs should use an unmodified clean_disp build if speed
    // matters.
    integer PLL_GLITCH_NS;
    reg     pll_glitch_active = 1'b0;
    // a full clock STOP is actually the safest possible perturbation (everything pauses and resumes
    // in perfect sync) - a real unlocked PLL is more likely to keep producing edges at a WRONG rate
    // (VCO over/undershoot) than to stop outright. +pll_glitch_period_ns=P (default 6 = no change)
    // sets the half-period used WHILE pll_glitch_active is set, instead of stopping clk_sys.
    integer PLL_GLITCH_PERIOD_NS;

    // ----------------------------------------------------------------- clock + ce_pix (clean Groovy.sv:505)
    reg clk_sys = 0;
    always begin
        if (pll_glitch_active) #(PLL_GLITCH_PERIOD_NS); else #6;
        clk_sys = ~clk_sys;
    end
    integer cycles = 0; always @(posedge clk_sys) cycles = cycles + 1;
    wire [7:0] ce_pix_arm = (cmd_scandoubler && PoC_pll_S) ? (PoC_ce_pix >> 1) - 8'd1 : PoC_ce_pix - 8'd1;
    reg [3:0] cencnt = 4'd0;
    always @(posedge clk_sys) cencnt <= (cencnt == ce_pix_arm[3:0]) ? 4'd0 : cencnt + 4'd1;
    reg ce_pix = 1'b0;
    always @(posedge clk_sys) ce_pix <= (cencnt == 4'd0);

    `include "states_params.vh"
    `include "ddr_params.vh"

    // ----------------------------------------------------------------- behavioral DDR (idealized for bring-up;
    // contention added during Phase-2 calibration). Single read/write port, fixed latency.
    reg [63:0] mem [0:(1<<21)-1];
    // FSM-side port registers (the extracted FSM drives these; the arbiter's M0 port consumes them)
    reg  [27:0] ddr_addr = 0;
    reg  [7:0]  ddr_burst = 0;
    reg         ddr_data_req = 0, ddr_data_write = 0;
    reg  [63:0] ddr_data_to_write = 0;
    wire [63:0] ddr_data;              // dout: shared fan-out (/55: now the REAL ddram's mem_dout)
    wire        ddr_data_ready;        // /47: now the arbiter's M0 view
    wire        ddr_busy;              // /47: now the arbiter's M0 view

    // /47: the REAL rtl/ddr_mux2.v sits between the FSM and the DDR model, exactly as in Groovy.sv.
    // M1 = the NLC engine master (tied idle until the engine lands; nlc_disp_mode==2 will drive it).
    wire [27:1] dm_addr_h;
    wire [27:0] dm_addr = {dm_addr_h, 1'b0};
    wire [63:0] dm_din;
    wire        dm_rd, dm_wr;
    wire [7:0]  dm_burst;
    wire        dm_dready;             // /55: now driven by the REAL rtl/ddram.sv
    wire        dm_busy;
    wire        eng_req;
    wire        eng_gnt;
    wire [27:1] eng_addr;
    wire [63:0] eng_din;
    wire        eng_rd, eng_wr;
    wire [7:0]  eng_burst;
    wire        eng_busy, eng_dready;
    ddr_mux2 ddr_mux (
        .clk(clk_sys),
        .m0_addr(ddr_addr[27:1]), .m0_din(ddr_data_to_write), .m0_rd(ddr_data_req),
        .m0_burst(ddr_burst), .m0_wr(ddr_data_write), .m0_busy(ddr_busy), .m0_dready(ddr_data_ready),
        .m1_req(eng_req), .m1_gnt(eng_gnt), .m1_addr(eng_addr), .m1_din(eng_din), .m1_rd(eng_rd),
        .m1_burst(eng_burst), .m1_wr(eng_wr), .m1_busy(eng_busy), .m1_dready(eng_dready),
        .mem_addr(dm_addr_h), .mem_din(dm_din), .mem_rd(dm_rd), .mem_burst(dm_burst), .mem_wr(dm_wr),
        .mem_busy(dm_busy), .mem_dready(dm_dready));

    // ------------------------------------------------------------------------------------------
    // /55: the REAL rtl/ddram.sv now sits between the mux and an Avalon-MM BFM (waitrequest +
    // readdatavalid + burstcount, f2sdram-like), replacing the behavioral mem-port model — the
    // wedge lived in exactly this (previously unsimulated) layer. The BFM keeps the calibrated
    // /41 cost model (READ_LAT / WR_OVERHEAD / WR_BEAT, same plusargs) and adds the /55 hazard:
    // Avalon readdatavalid asserted WHILE waitrequest is high (legal Avalon; the old ddram
    // silently dropped such beats -> read_req stuck -> permanent bus freeze):
    //   +rdvbusy_every=N : every Nth delivered read beat coincides with busy
    //   +rdvbusy_prob=P  : each beat coincides with busy with probability P% ($urandom)
    //   +rdvbusy_once=B  : exactly ONE hazarded beat, at delivered-beat number B
    //                      (single-fault proof: one dropped beat = permanent wedge pre-/55)
    //   +deadburst_once=B: the transaction containing beat B stops delivering beats
    //                      entirely (f2sdram anomaly model) — exercises the /55 ddram
    //                      read-watchdog (synthesized beats) + the FSM liveness net
    // Build clean_disp_legacy55 (-DDDRAM_LEGACY, sim/ddram_legacy.v) to reproduce the wedge on
    // the pre-/55 ddram; the fixed build must survive the same hazard bit-identically.
    wire        AV_BUSY;
    wire [7:0]  AV_BURSTCNT;
    wire [28:0] AV_ADDR;
    reg  [63:0] AV_DOUT = 0;
    reg         AV_DOUT_READY = 0;
    wire        AV_RD, AV_WE;
    wire [63:0] AV_DIN;

`ifdef DDRAM_LEGACY
    ddram_legacy u_ddram (
`else
    ddram u_ddram (
`endif
        .DDRAM_CLK(clk_sys), .DDRAM_BUSY(AV_BUSY), .DDRAM_BURSTCNT(AV_BURSTCNT),
        .DDRAM_ADDR(AV_ADDR), .DDRAM_DOUT(AV_DOUT), .DDRAM_DOUT_READY(AV_DOUT_READY),
        .DDRAM_RD(AV_RD), .DDRAM_DIN(AV_DIN), .DDRAM_BE(), .DDRAM_WE(AV_WE),
        .mem_addr(dm_addr_h), .mem_dout(ddr_data), .mem_din(dm_din), .mem_rd(dm_rd),
        .mem_burst(dm_burst), .mem_wr(dm_wr), .mem_busy(dm_busy), .mem_dready(dm_dready)
`ifndef DDRAM_LEGACY
        , .dbg_state(), .dbg_timeout_cnt()
`endif
    );

    // DDR cost model = per-TRANSACTION OVERHEAD (f2sdram bridge arbitration / row / ARM contention) + per-BEAT.
    // CALIBRATED to /41: a SINGLE-BEAT FB write = WR_OVERHEAD + WR_BEAT = 80 clk_sys cyc (unchanged semantics).
    integer READ_LAT = 14, WR_OVERHEAD = 78, WR_BEAT = 2;
    integer RDVBUSY_EVERY = 0, RDVBUSY_PROB = 0, RDVBUSY_ONCE = 0, DEADBURST_ONCE = 0;
    reg dead_now = 0, dead_used = 0;
    initial begin
        if (!$value$plusargs("readlat=%d",     READ_LAT))    READ_LAT    = 14;
        if (!$value$plusargs("wroverhead=%d",  WR_OVERHEAD)) WR_OVERHEAD = 78;
        if (!$value$plusargs("wrbeat=%d",      WR_BEAT))     WR_BEAT     = 2;
        // back-compat: +writebusy=W forces single-beat cost = W (overhead=W, beat=0)
        if ($value$plusargs("writebusy=%d", WR_OVERHEAD)) WR_BEAT = 0;
        if (!$value$plusargs("rdvbusy_every=%d", RDVBUSY_EVERY)) RDVBUSY_EVERY = 0;
        if (!$value$plusargs("rdvbusy_prob=%d",  RDVBUSY_PROB))  RDVBUSY_PROB  = 0;
        if (!$value$plusargs("rdvbusy_once=%d",  RDVBUSY_ONCE))  RDVBUSY_ONCE  = 0;
        if (!$value$plusargs("deadburst_once=%d", DEADBURST_ONCE)) DEADBURST_ONCE = 0;
    end

    integer av_rd_left = 0, av_rd_lat = 0, av_wr_left = 0, av_busy_left = 0;
    integer av_beatno = 0;                       // delivered read beats (hazard cadence)
    reg [28:0] av_rd_addr = 0, av_wr_addr = 0;
    reg av_reading = 0, av_hazard_r = 0, av_hz = 0;
    // ---- EXTERNAL-MASTER DDR STALL (models HPS traffic on the shared hard memory controller).
    // Injected HERE, at the Avalon/f2sdram boundary, NOT at ddr_mux2: the contention modelled is
    // another master on the SAME hard controller, which the fabric arbiter cannot see or mitigate.
    //   +extstall_line=L  : beam line (vga vcount) at which the stall starts
    //   +extstall_cyc=N   : clk_sys cycles to hold the controller busy
    //   +extstall_first=F : first vga_frame to inject on (default 3, i.e. after bootstrap)
    //   +extstall_every=E : inject at most once every E frames (default 1)
    integer EXTSTALL_LINE = 0, EXTSTALL_CYC = 0, EXTSTALL_FIRST = 3, EXTSTALL_EVERY = 1;
    integer av_ext_left = 0, ext_injections = 0, ext_last_frame = 0;
    reg     ext_line_d = 0;
    initial begin
        if (!$value$plusargs("extstall_line=%d",  EXTSTALL_LINE))  EXTSTALL_LINE  = 0;
        if (!$value$plusargs("extstall_cyc=%d",   EXTSTALL_CYC))   EXTSTALL_CYC   = 0;
        if (!$value$plusargs("extstall_first=%d", EXTSTALL_FIRST)) EXTSTALL_FIRST = 3;
        if (!$value$plusargs("extstall_every=%d", EXTSTALL_EVERY)) EXTSTALL_EVERY = 1;
    end
    always @(posedge clk_sys) begin
        ext_line_d <= (vga_vcount == EXTSTALL_LINE[15:0]);
        if (av_ext_left > 0) av_ext_left <= av_ext_left - 1;
        if (EXTSTALL_CYC > 0 && (vga_vcount == EXTSTALL_LINE[15:0]) && !ext_line_d
            && vga_frame >= EXTSTALL_FIRST
            && (ext_injections == 0 || (vga_frame - ext_last_frame) >= EXTSTALL_EVERY)) begin
            av_ext_left    <= EXTSTALL_CYC;
            ext_last_frame  = vga_frame;
            ext_injections  = ext_injections + 1;
            $display("[EXTSTALL] vga_frame=%0d line=%0d hold=%0d cyc | vram_queue=%0d vram_pixels=%0d cyc=%0d",
                     vga_frame, vga_vcount, EXTSTALL_CYC, vram_queue, vram_pixels, cycles);
        end
    end

    assign AV_BUSY = (av_busy_left > 0) || av_hazard_r || (av_ext_left > 0);
    always @(posedge clk_sys) begin
        AV_DOUT_READY <= 1'b0;
        av_hazard_r   <= 1'b0;
        // write beat: one per non-busy cycle while WE held (ddram streams its declared burst)
        if (AV_WE && !AV_BUSY) begin
            if (av_wr_left == 0) begin           // first beat of a write TRANSACTION
                mem[AV_ADDR[20:0]] <= AV_DIN;
                av_wr_addr   <= AV_ADDR + 29'd1;
                av_wr_left   <= (AV_BURSTCNT > 1) ? AV_BURSTCNT - 1 : 0;
                av_busy_left <= WR_OVERHEAD + WR_BEAT;
            end else begin                       // continuation beat (address increments internally)
                mem[av_wr_addr[20:0]] <= AV_DIN;
                av_wr_addr   <= av_wr_addr + 29'd1;
                av_wr_left   <= av_wr_left - 1;
                av_busy_left <= WR_BEAT;
            end
        end
        // read command accept (ddram never issues while a read/write is in flight)
        if (AV_RD && !AV_BUSY && !av_reading) begin
            av_reading <= 1'b1;
            av_rd_addr <= AV_ADDR;
            av_rd_left <= (AV_BURSTCNT == 0) ? 1 : AV_BURSTCNT;
            av_rd_lat  <= READ_LAT;
        end
        if (av_reading) begin
            // /55 dead-burst injection: silently stop delivering this transaction's beats
            if (DEADBURST_ONCE > 0 && !dead_used && !dead_now
                && av_beatno + 1 >= DEADBURST_ONCE && av_rd_left > 0) begin
                dead_now  <= 1'b1;
                dead_used <= 1'b1;
                $display("[HZ] DEAD BURST injected: beats %0d..%0d never delivered, cyc=%0d",
                         av_beatno + 1, av_beatno + av_rd_left, cycles);
            end
            if (dead_now) begin
                if (av_rd_left > 0) begin            // swallow the rest of the burst silently
                    av_rd_addr <= av_rd_addr + 29'd1;
                    av_rd_left <= av_rd_left - 1;
                    av_beatno  <= av_beatno + 1;
                    if (av_rd_left == 1) begin av_reading <= 1'b0; dead_now <= 1'b0; end
                end
            end
            else if (av_rd_lat > 0) av_rd_lat <= av_rd_lat - 1;
            else if (av_rd_left > 0) begin
                AV_DOUT       <= mem[av_rd_addr[20:0]];
                AV_DOUT_READY <= 1'b1;
                av_rd_addr    <= av_rd_addr + 29'd1;
                av_rd_left    <= av_rd_left - 1;
                av_beatno     <= av_beatno + 1;
                // /55 hazard: this beat's readdatavalid coincides with waitrequest
                av_hz = (RDVBUSY_EVERY > 0 && ((av_beatno + 1) % RDVBUSY_EVERY == 0))
                     || (RDVBUSY_PROB  > 0 && (($urandom % 100) < RDVBUSY_PROB))
                     || (RDVBUSY_ONCE  > 0 && (av_beatno + 1 == RDVBUSY_ONCE));
                if (av_hz && RDVBUSY_ONCE > 0)
                    $display("[HZ] single rdv-during-busy beat injected: beat=%0d cyc=%0d", av_beatno + 1, cycles);
                av_hazard_r   <= av_hz;
                if (av_rd_left == 1) av_reading <= 1'b0;
            end
        end
        if (av_busy_left > 0) av_busy_left <= av_busy_left - 1;
    end

    // ----------------------------------------------------------------- REAL clean LZ4 decoder
    reg         lz4_reset = 0, lz4_run = 0, lz4_stop = 0, lz4_write_long = 0;
    reg [31:0]  lz4_compressed_bytes = 0;
    reg [63:0]  lz4_compressed_long = 0;
    wire        lz4_write_ready, lz4_byte_valid, lz4_long_valid, lz4_paused, lz4_done, lz4_error, lz4_read_ready;
    wire [7:0]  lz4_uncompressed_byte;
    wire [63:0] lz4_uncompressed_long;
    wire [31:0] lz4_uncompressed_bytes, lz4_writed_bytes, lz4_readed_bytes;
    wire [3:0]  lz4_state;
    lz4 lz4 (
        .lz4_clk(clk_sys), .lz4_reset(lz4_reset), .lz4_mode_64(1'b1),
        .lz4_run(lz4_run),
        .lz4_stop((ddr_data_write && ddr_busy) || (PoC_lz4_delta_req) ? 1'b1 : lz4_stop),
        .lz4_compressed_bytes(lz4_compressed_bytes), .lz4_compressed_long(lz4_compressed_long),
        .lz4_write_long(lz4_write_long), .lz4_write_ready(lz4_write_ready),
        .lz4_uncompressed_byte(lz4_uncompressed_byte), .lz4_byte_valid(lz4_byte_valid),
        .lz4_uncompressed_long(lz4_uncompressed_long), .lz4_long_valid(lz4_long_valid),
        .lz4_uncompressed_bytes(lz4_uncompressed_bytes), .lz4_paused(lz4_paused), .lz4_done(lz4_done),
        .lz4_error(lz4_error), .lz4_state(lz4_state), .lz4_writed_bytes(lz4_writed_bytes),
        .lz4_readed_bytes(lz4_readed_bytes), .lz4_read_ready(lz4_read_ready),
        .lz4_delta_long(64'd0));

    // ---- NLC decoder (codec_mode==2). cfg driven by the tb; the FSM (extracted) selects it. ----
    reg  [1:0]  codec_mode = 0, nlc_near = 0;
    reg         nlc_color = 1;
    // /46 PROTOTYPING FRAMEWORK: NLC display-path mode selector. mode 0 = /45 streaming (verbatim, the fallback);
    // 1 = B-throttle; 2 = B-autonomous-drain; (3 spare). The extracted FSM branches on nlc_disp_mode; the tb drives
    // it from +nlcmode=N so every approach is one reversible, A/B-comparable gated branch (HW: hps_ext init [7:6]).
    reg  [1:0]  nlc_disp_mode = 0;
    reg         nlc_reset = 1, nlc_write_long = 0, nlc_out_ready = 0;
    reg  [63:0] nlc_compressed_long = 0;
    reg  [31:0] nlc_compressed_bytes = 0;
    reg  [23:0] nlc_cur_frame = 0;
    reg         nlc_busy = 0;   // STAGE A: a decode is in-flight (started, not yet nlc_done)
    reg  [20:0] nlc_stall_cnt = 0;   // liveness window (must exceed one vblank ~120k cyc)
    reg         nlc_stream_ok = 1;  // STREAM-ABANDON flag (the /42 fix; mirrored from Groovy.sv)
    // STAGE 1 burst-FB-write support regs (mirror of Groovy.sv; the FSM body comes via the extractor)
    localparam  NLC_CHUNK = 8'd120;
    reg [63:0]  nlc_lbuf [0:127];
    reg [63:0]  nlc_lb_q;
    reg [7:0]   nlc_lb_ra;
    reg [7:0]   nlc_lb_wcnt = 0, nlc_lb_rd = 0;
    reg [27:0]  nlc_flushed_bytes = 0;
    reg         nlc_flush_end = 0, nlc_fl_pre = 0, nlc_fl_run = 0;
    reg         nlc_commit_v;
    reg         nlc_m1_go;   // /46 mode-1 throttle gate (blocking temp used by the extracted FSM)
    always @* begin
        if (state != S_Blit_Flush_NLC || !nlc_fl_pre) nlc_lb_ra = 8'd0;
        else if (!nlc_fl_run)                         nlc_lb_ra = 8'd1;
        else nlc_lb_ra = (ddr_data_write && !ddr_busy && nlc_lb_rd < nlc_lb_wcnt - 1'b1) ? nlc_lb_rd + 8'd2 : nlc_lb_rd + 8'd1;
    end
    always @(posedge clk_sys) nlc_lb_q <= nlc_lbuf[nlc_lb_ra];
    wire        nlc_write_ready, nlc_long_valid, nlc_paused, nlc_done_raw;
    // FAULT INJECTION (+suppress_done): force the FSM's view of nlc_done LOW to model HW, where the last-row
    // edge never asserts. With it, the OLD nlc_done-only completion WEDGES (reproduces /36); the STAGE A2
    // robust completion (nlc_frame_done) must still complete via FB-full / liveness.
    reg         suppress_done = 0;
    wire        nlc_done = nlc_done_raw && !suppress_done;
    wire [63:0] nlc_uncompressed_long;
    wire [31:0] nlc_uncompressed_bytes, nlc_writed_bytes, nlc_readed_bytes;
    // STAGE A2 robust completion (mirror of Groovy.sv): FB fully written OR nlc_done OR end-of-frame liveness.
    // +donly forces the OLD /36 behaviour (complete ONLY on nlc_done) for the reproduction test.
    reg         donly = 0;
    wire [27:0] nlc_frame_bytes = (vga_pixels << 1) + vga_pixels;
    wire        nlc_frame_done  = donly ? nlc_done
                                : ( nlc_done
                                  || (PoC_subframe_wr_bytes >= nlc_frame_bytes)
                                  || (nlc_writed_bytes >= PoC_subframe_lz4_ddr_bytes && nlc_stall_cnt > 21'd1048575) );
    // /47 MODE 2: decoder input muxes — the engine owns u_nlc under nlc_disp_mode==2 (as in Groovy.sv)
    wire        eng_dec_reset, eng_dec_wlong, eng_dec_oready;
    wire [63:0] eng_dec_clong;
    wire        nlc_eng_sel = (nlc_disp_mode == 2'd2) && (codec_mode == 2'd2);
    reg         nlc_rice_r;                       // R3: +rice = session negotiated the Golomb-Rice pack
    initial nlc_rice_r = $test$plusargs("rice");
    nlc_decode_ddr #(.MAXW(720), .WBITS(4), .NP(3)) u_nlc (
        .clk(clk_sys), .reset(nlc_eng_sel ? eng_dec_reset : nlc_reset),
        .cfg_w(PoC_H), .cfg_h(PoC_V >> PoC_FB_interlaced),
        .cfg_near({1'b0, nlc_near}), .cfg_tile(7'd16), .cfg_color(nlc_color), .cfg_rice(nlc_rice_r),
        .compressed_long(nlc_eng_sel ? eng_dec_clong : nlc_compressed_long),
        .write_long(nlc_eng_sel ? eng_dec_wlong : nlc_write_long), .write_ready(nlc_write_ready),
        .out_ready(nlc_eng_sel ? eng_dec_oready : nlc_out_ready),
        .uncompressed_long(nlc_uncompressed_long), .long_valid(nlc_long_valid),
        .uncompressed_bytes(nlc_uncompressed_bytes), .writed_bytes(nlc_writed_bytes),
        .readed_bytes(nlc_readed_bytes), .paused(nlc_paused), .done(nlc_done_raw));

    // /47 MODE 2: the autonomous engine + the FSM-side handshake registers (mirrors Groovy.sv)
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
    nlc_engine u_eng (
        .clk(clk_sys), .abort(eng_abort_r),
        .pend_valid(eng_pend_valid), .pend_frame(eng_pend_frame), .pend_size(eng_pend_size),
        .pend_bytes(eng_pend_bytes), .pend_final(eng_pend_final),
        .pend_src(eng_pend_src), .pend_dst(eng_pend_dst), .pend_fb_bytes(eng_pend_fb),
        .adopt_ack(eng_adopt_ack),
        .wm_stb(eng_wm_stb), .wm_bytes(eng_wm_bytes), .wm_final(eng_wm_final),
        .dec_reset(eng_dec_reset), .dec_clong(eng_dec_clong), .dec_wlong(eng_dec_wlong),
        .dec_wready(nlc_write_ready), .dec_ulong(nlc_uncompressed_long), .dec_lvalid(nlc_long_valid),
        .dec_oready(eng_dec_oready), .dec_writed(nlc_writed_bytes), .dec_done(nlc_done),
        .m_req(eng_req), .m_gnt(eng_gnt), .m_addr(eng_addr), .m_din(eng_din), .m_rd(eng_rd),
        .m_burst(eng_burst), .m_wr(eng_wr), .m_busy(eng_busy), .m_dready(eng_dready), .m_dout(ddr_data),
        .busy(eng_busy_w), .done_stb(eng_done_stb), .cur_frame(eng_cur_frame),
        .flushed_bytes(eng_flushed), .wd_fired(eng_wd_fired), .eng_state(eng_st_w));

    // ----------------------------------------------- clean FSM state (declared to match the clean Groovy.sv)
    reg [7:0]  state = S_Idle;
    reg [15:0] PoC_H = 0;  reg [7:0] PoC_HFP = 0, PoC_HS = 0, PoC_HBP = 0;
    reg [15:0] PoC_V = 0;  reg [7:0] PoC_VFP = 0, PoC_VS = 0, PoC_VBP = 0;
    reg        PoC_interlaced = 0, PoC_FB_interlaced = 0, PoC_pll_S = 0;
    reg [7:0]  PoC_pll_F_M0, PoC_pll_F_M1, PoC_pll_F_C0, PoC_pll_F_C1;
    reg [7:0]  PoC_ce_pix = 8'd6;
    reg [31:0] PoC_pll_F_K;
    reg [23:0] PoC_frame_switchres = 0;
    reg [23:0] PoC_frame_ddr = 0, PoC_frame_vram = 0, PoC_frame_lz4_ddr = 0, PoC_frame_lz4 = 0;
    reg [23:0] PoC_subframe_px_ddr = 0, PoC_subframe_px_vram = 0, PoC_subframe_px_lz4 = 0;
    reg [15:0] PoC_subframe_bl_ddr = 0, PoC_subframe_bl_vram = 0;
    reg [27:0] PoC_subframe_vram_bytes = 0, PoC_subframe_ddr_bytes = 0, PoC_subframe_wr_bytes = 0;
    reg [31:0] PoC_subframe_lz4_ddr_bytes = 0;
    reg [15:0] PoC_subframe_blit_lz4_ddr = 0, PoC_subframe_blit_lz4 = 0;
    reg        PoC_lz4_resume_blit = 0, PoC_lz4_resume_audio = 0;
    reg [1:0]  PoC_lz4_ABCD = 0, PoC_lz4_field = 0;
    reg        PoC_lz4_delta = 0, PoC_lz4_delta_req = 0;
    reg [23:0] PoC_px_frameskip = 0;
    reg [7:0]  PoC_state_frameskip = 0;
    reg        PoC_frame_lz4_FB = 0, vram_drive_lz4 = 0, vram_drive_raw = 0;
    reg        reset_blit = 0, reset_blit_lz4 = 0, auto_blit = 0, auto_blit_lz4 = 0;
    reg        vram_reset = 0, vga_wait_vblank = 0, vga_soft_reset = 0;
    reg        vga_frameskip = 0, vga_frameskip_prev = 0, cmd_fskip = 0;
    reg        vram_active = 0, vga_reset = 0, vga_frame_reset = 0;
    reg [1:0]  PoC_frame_rgb_offset = 0;
    reg [1:0]  ddr_data_idx = 0;
    reg [191:0] ddr_data_tmp = 0;
    reg        vram_wren1=0, vram_wren2=0, vram_wren3=0, vram_wren4=0;
    reg [7:0]  r_vram_in1, g_vram_in1, b_vram_in1, r_vram_in2, g_vram_in2, b_vram_in2;
    reg [7:0]  r_vram_in3, g_vram_in3, b_vram_in3, r_vram_in4, g_vram_in4, b_vram_in4;
    reg [7:0]  r_in = 0, g_in = 0, b_in = 0;
    reg        reset_switchres = 0, reset_audio = 0;
    reg        req_modeline = 0, new_vmode = 0;
    wire       new_modeline = req_modeline;
    reg        sound_reset=0, sound_wren1=0, sound_wren2=0, sound_wren3=0, sound_wren4=0;
    reg [15:0] PoC_audio_samples = 0; reg [23:0] PoC_audio_ddr_bytes = 0;
    reg [15:0] PoC_audio_count = 0;  reg [23:0] PoC_audio_count_bytes = 0;
    reg [15:0] sound_in1=0, sound_in2=0, sound_in3=0, sound_in4=0;
    reg [1:0]  PoC_lz4_delta_index = 0;
    reg [27:0] PoC_lz4_delta_bytes = 0;
    reg [63:0] PoC_lz4_delta_FB [0:3];   // delta-frame buffer (non-delta path unused; declared for the FSM)
    // /58 reconnect repro: was a tied-high wire (never exercised a reconnect). Now driveable so
    // do_reconnect (below) can pulse it low/high exactly like the real setInit() forced edge (/87 fix).
    reg        cmd_init = 1'b1;
    wire       cmd_audio = 1'b0, cmd_logo = 1'b0, cmd_scandoubler = 1'b0;
    wire       hps_frameskip = 1'b1;
    wire [1:0] scandoubler_fx = 2'b00; wire forced_scandoubler = 1'b0;
    wire [1:0] rgb_mode = 2'd0;
    wire [1:0] sound_chan = 2'd0;     wire [15:0] audio_samples = 16'd0;
    reg        cmd_switchres = 0, cmd_blit = 0, cmd_blit_lz4 = 0;
    reg [31:0] switchres_frame = 0;
    reg [31:0] lz4_size = 0; reg [1:0] lz4_ABCD = 0, lz4_field = 0;
    reg        lz4_delta = 0;
    wire       cmd_blit_vsync = 1'b0;
    // request latches (hps_ext semantics)
    reg cmd_blit_req = 0, cmd_blit_lz4_req = 0, cmd_switchres_req = 0;
    always @(posedge clk_sys) begin
        if (cmd_blit_req)      cmd_blit      <= 1'b1; else if (reset_blit)      cmd_blit      <= 1'b0;
        if (cmd_blit_lz4_req)  cmd_blit_lz4  <= 1'b1; else if (reset_blit_lz4)  cmd_blit_lz4  <= 1'b0;
        if (cmd_switchres_req) cmd_switchres <= 1'b1; else if (reset_switchres) cmd_switchres <= 1'b0;
    end

    // ----------------------------------------------------------------- REAL clean vga.v
    wire        vram_req_ready, vram_synced, vram_end_frame;
    wire        vram_starve;

    // Mirrors the Groovy.sv framebuffer-lead select, which is an OSD option there and a plusarg
    // here: +lead=1|4|8|16. The FSM body latches autoblit_sh from autoblit_sh_sel in S_Idle.
    integer LEAD;
    reg  [2:0]  autoblit_sh = 3'd0;
    wire [23:0] autoblit_lead = 24'd1 << autoblit_sh;
    wire [2:0]  autoblit_sh_sel = (LEAD >= 16) ? 3'd4 : (LEAD >= 8) ? 3'd3 : (LEAD >= 4) ? 3'd2 : 3'd0;
    initial if (!$value$plusargs("lead=%d", LEAD)) LEAD = 1;
    wire [23:0] vram_pixels, vram_queue, vga_frame, vga_pixels;
    wire [15:0] vga_vcount;
    wire [7:0]  vr, vg, vb; wire vga_de_w, vga_hblank, VGA_F1, vga_hs, vga_vs;
    wire        vblank_core;
    vga vga (
        .clk_sys(clk_sys), .ce_pix(ce_pix),
        .vga_reset(vga_reset), .vga_frame_reset(vga_frame_reset), .vga_soft_reset(vga_soft_reset),
        .vga_wait_vblank(vga_wait_vblank),
        .H(PoC_H), .HFP(PoC_HFP), .HS(PoC_HS), .HBP(PoC_HBP),
        .V(PoC_V), .VFP(PoC_VFP), .VS(PoC_VS), .VBP(PoC_VBP),
        .interlaced(cmd_scandoubler && PoC_pll_S ? 1'b0 : PoC_interlaced),
        .FB_interlaced(PoC_FB_interlaced),
        .vram_active(vram_active), .vram_reset(vram_reset),
        .vram_wren1(vram_wren1), .r_vram_in1(r_vram_in1), .g_vram_in1(g_vram_in1), .b_vram_in1(b_vram_in1),
        .vram_wren2(vram_wren2), .r_vram_in2(r_vram_in2), .g_vram_in2(g_vram_in2), .b_vram_in2(b_vram_in2),
        .vram_wren3(vram_wren3), .r_vram_in3(r_vram_in3), .g_vram_in3(g_vram_in3), .b_vram_in3(b_vram_in3),
        .vram_wren4(vram_wren4), .r_vram_in4(r_vram_in4), .g_vram_in4(g_vram_in4), .b_vram_in4(b_vram_in4),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .cmd_blit_vsync(cmd_blit_vsync),
        .vsync_skip(vga_frameskip || !vram_synced), .vsync_overlay(1'b0), .vram_defer_sync(!vram_drive_lz4),
        .vram_ready(vram_req_ready), .vram_pixels(vram_pixels), .vram_queue(vram_queue),
        .vram_end_frame(vram_end_frame), .vram_synced(vram_synced), .vram_starve(vram_starve),
        .vga_frame(vga_frame), .vcount(vga_vcount), .vga_pixels(vga_pixels),
        .hsync(vga_hs), .vsync(vga_vs), .r(vr), .g(vg), .b(vb),
        .vga_de(vga_de_w), .hblank(vga_hblank), .vblank(vblank_core), .vga_f1(VGA_F1));

    `include "decode_pixel.vh"

    // ----------------------------------------------------------------- the clean FSM (whole case body)
    always @(posedge clk_sys) begin
        cmd_fskip <= 1'b0;
        `include "fskip_monitor.vh"
        `include "states_all.vh"
        // /55 DISPLAY LIVENESS NET (mirrors Groovy.sv post-endcase): force resync after a
        // detected freeze — placed after the case so it overrides same-cycle assignments.
        if (dbg_freeze_hit) vram_reset <= 1'b1;
    end

    // /55 freeze detector (mirrors Groovy.sv): >=2 full frames of sync=0 with a frozen
    // vram_pixels counter => pulse the liveness net + log once (the sim FREEZE_LATCH).
    reg        dbg_freeze_hit = 0, dbg_freeze_valid = 0;
    reg [1:0]  dbg_freeze_frames = 0;
    reg [23:0] dbg_prev_px = 0;
    reg        frz_vb_d = 0;
    always @(posedge clk_sys) begin
        frz_vb_d <= vblank_core;
        dbg_freeze_hit <= 1'b0;
        if (vblank_core && !frz_vb_d) begin
            dbg_prev_px <= vram_pixels;
            if (!vram_synced && vram_pixels == dbg_prev_px) begin
                if (dbg_freeze_frames == 2'd2) begin
                    dbg_freeze_hit    <= 1'b1;
                    dbg_freeze_frames <= 2'd0;
                    if (!dbg_freeze_valid) begin
                        dbg_freeze_valid <= 1'b1;
                        $display("*** FREEZE_LATCH cyc=%0d fsm=%0d eng=%0d busy=%0d px=%0d q=%0d ***",
                                 cycles, state, eng_st_w, dm_busy, vram_pixels, vram_queue);
                    end
                end else dbg_freeze_frames <= dbg_freeze_frames + 2'd1;
            end else dbg_freeze_frames <= 2'd0;
        end
    end

    // /55 BUS-WEDGE monitor: mem_busy stuck high = the arbiter/ddram layer froze (the /55
    // signature underneath the red screen). One loud line per run, for both builds.
    integer busfree_cyc = 0; reg buswedge_logged = 0;
    always @(posedge clk_sys) begin
        if (!dm_busy) busfree_cyc <= cycles;
        if (!buswedge_logged && vga_frame > 0 && (cycles - busfree_cyc) > 3000000) begin
            buswedge_logged <= 1;
            $display("*** BUS WEDGE: mem_busy stuck high >3M cyc @%0d (fsm=%0d eng=%0d eng_req=%0d) ***",
                     cycles, state, eng_st_w, eng_req);
        end
    end

    // ----------------------------------------------------------------- FRAME DUMP (the new capability)
    // LINE-ALIGNED capture: x resets at each active-line end (de falling edge), y = line index. Writes one
    // .ppm per displayed frame. (Progressive here; interlaced field-interleave is a later polish item.)
    // INTERLACE-AWARE capture: progressive (ILACE==0) dumps each frame at vblank; interlaced (ILACE!=0)
    // interleaves the two fields (VGA_F1 selects even/odd rows) and dumps the full frame after BOTH fields,
    // so the dumped image matches what an interlaced CRT integrates — directly comparable to HW.
    integer capx = 0, capy = 0, frames_out = 0, maxrow = 0, fieldcnt = 0, row;
    reg [7:0] img [0:3*1280*720-1];
    reg vbl_d = 0, de_d = 0;
    reg [255:0] fname;
    always @(posedge clk_sys) begin
        vbl_d <= vblank_core;
        if (ce_pix) begin
            de_d <= vga_de_w;
            if (vga_de_w) begin
                row = (ILACE != 0) ? (capy*2 + (VGA_F1 ? 1 : 0)) : capy;
                if (row < 720 && capx < W && (row*W+capx)*3+2 < 3*1280*720) begin
                    img[(row*W+capx)*3+0] = vr; img[(row*W+capx)*3+1] = vg; img[(row*W+capx)*3+2] = vb;
                end
                if (row > maxrow) maxrow = row;
                capx = capx + 1;
            end else if (de_d) begin                 // de falling edge = end of an active line
                capy = capy + 1; capx = 0;
            end
        end
        if (vblank_core && !vbl_d) begin             // a field (progressive: a frame) just ended
            capx = 0; capy = 0;
            fieldcnt = fieldcnt + 1;
            if ((ILACE == 0) || (fieldcnt >= 2)) begin
                if (maxrow > 1) begin
                    $sformat(fname, "frame_%0d_%03d_fv%0d.ppm", CODEC, frames_out, PoC_frame_vram);
                    dump_ppm(fname, maxrow + 1);
                    analyse_frame(maxrow + 1);
                    // latency analysis hook: pair with the [ANN] lines (announce cycle per frame#)
                    // to compute announce -> displayed-content latency offline (P2.4)
                    $display("[CAP] file=%0s cyc=%0d", fname, cycles);
                    frames_out = frames_out + 1;
                end
                fieldcnt = 0; maxrow = 0;
            end
        end
    end
    // Two measures of the same thing, so the real telemetry can be checked against ground truth.
    // GROUND TRUTH samples vram_starve directly on ce_pix. The MIRROR reproduces Groovy.sv exactly,
    // including the one-cycle dbg_pipe register the strobe passes through before an edge-sensitive
    // ce_pix samples it - hardware reported a sync-loss with starve_px=0, which should be impossible,
    // and this pair is what tells the two apart.
    integer starve_run = 0, starve_max = 0, starve_px_total = 0;      // ground truth
    reg tb_vb_d = 0;
    always @(posedge clk_sys) begin
        tb_vb_d <= vblank_core;
        if (ce_pix && display_up && vram_starve) begin
            starve_run = starve_run + 1;
            starve_px_total = starve_px_total + 1;
            if (starve_run > starve_max) starve_max = starve_run;
        end
        if (vblank_core && !tb_vb_d) starve_run = 0;
    end

    // exact mirror of Groovy.sv dbg_pipe + dbg_freeze_detect
    reg        m_starve_r = 0, m_sync_r = 1, m_vb_r = 0, m_old_vb = 0, m_old_unsync = 0;
    integer    m_starve_frm = 0, m_starve_max = 0, m_syncloss = 0;
    always @(posedge clk_sys) begin
        m_starve_r <= vram_starve;
        m_sync_r   <= vram_synced;
        m_vb_r     <= vblank_core;
        if (!m_sync_r && !m_old_unsync && m_syncloss != 255) m_syncloss = m_syncloss + 1;
        if (ce_pix && m_starve_r) begin
            if (m_starve_frm != 65535) m_starve_frm = m_starve_frm + 1;
            if (m_starve_frm >= m_starve_max) m_starve_max = m_starve_frm + 1;
        end
        if (m_vb_r && !m_old_vb) m_starve_frm = 0;
        m_old_vb     <= m_vb_r;
        m_old_unsync <= !m_sync_r;
    end

    // ARTIFACT ANALYSER: red = vga.v R_NO_VRAM (FIFO starved); black-after-red = the vram_reset park
    // (vram_wait_vblank blanks the rest of the frame). Content baseline is measured by the no-inject run.
    integer red_n, blk_n, first_red_row, first_red_col, blk_after, last_red_row;
    task analyse_frame(input integer rows);
        integer x, y, i, rr, seen_red;
        begin
            rr = (rows > H) ? H : rows;
            red_n = 0; blk_n = 0; first_red_row = -1; first_red_col = -1;
            blk_after = 0; seen_red = 0; last_red_row = -1;
            for (y = 0; y < rr; y = y + 1)
              for (x = 0; x < W; x = x + 1) begin
                i = (y*W + x)*3;
                if (img[i] == 8'hFF && img[i+1] == 8'h00 && img[i+2] == 8'h00) begin
                    red_n = red_n + 1; last_red_row = y;
                    if (!seen_red) begin seen_red = 1; first_red_row = y; first_red_col = x; end
                end else if (img[i] == 8'h00 && img[i+1] == 8'h00 && img[i+2] == 8'h00) begin
                    blk_n = blk_n + 1;
                    if (seen_red) blk_after = blk_after + 1;
                end
              end
            $display("[ANALYSE] fv=%0d rows=%0d red=%0d firstred=(r%0d,c%0d) lastredrow=%0d blackafterred=%0d blacktotal=%0d",
                     PoC_frame_vram, rr, red_n, first_red_row, first_red_col, last_red_row, blk_after, blk_n);
        end
    endtask

    task dump_ppm(input [255:0] nm, input integer rows);
        integer i, fdo, rr;
        begin
            rr = (rows > H) ? H : rows;
            fdo = $fopen(nm, "wb");
            $fwrite(fdo, "P6\n%0d %0d\n255\n", W, rr);
            for (i = 0; i < W*rr*3; i = i + 1) $fwrite(fdo, "%c", img[i]);
            $fclose(fdo);
            if (DEBUG) $display("[%0d] dumped %0s (%0dx%0d)", cycles, nm, W, rr);
        end
    endtask

    // DEBUG: dump the DDR framebuffer (what the decode/FSM actually wrote) — word-aligned at DDR_FB_OFFSET>>3,
    // so == the source marker bytes iff the FB write is correct. Isolates write-side vs display-side bugs.
    task dump_fb(input [255:0] nm);
        integer i, fdo; reg [63:0] w; reg [27:0] b0;
        begin
            b0 = 28'hff & 28'h7FFFFF8;   // FB word base byte (DDR_FB_OFFSET word-aligned)
            fdo = $fopen(nm, "wb");
            for (i = 0; i < W*H*3; i = i + 1) begin
                w = mem[(b0 + i) >> 3];
                $fwrite(fdo, "%c", w[((b0 + i) & 7)*8 +: 8]);
            end
            $fclose(fdo);
            $display("[%0d] dumped FB -> %0s", cycles, nm);
        end
    endtask

    // ----------------------------------------------------------------- HPS feeder (mirrors the real path)
    reg [7:0] lz4buf [0:4194303]; integer lz4cs;
    task write_word(input [27:0] byte_addr, input [63:0] w); begin mem[byte_addr>>3] = w; end endtask

    // modeline word bit layout (clean Groovy.sv switchres parse, ddr_data_tmp from 3 DDR words):
    //  word@8  : H[0:15] HFP[16:23] HS[24:31] HBP[32:39] V[40:55] VFP[56:63]
    //  word@16 : VS[0:7] VBP[8:15] M0[16:23] M1[24:31] C0[32:39] C1[40:47] K[48:63]
    //  word@24 : K[0:15] ce_pix[16:23] interlace[24:31]
    task do_switchres;
        reg [63:0] w1, w2, w3;
        begin
            w1 = 0;
            w1[0  +: 16] = W[15:0]; w1[16 +: 8] = HFP[7:0]; w1[24 +: 8] = HSv[7:0]; w1[32 +: 8] = HBP[7:0];
            w1[40 +: 16] = H[15:0]; w1[56 +: 8] = VFP[7:0];
            w2 = 0; w2[0 +: 8] = VSv[7:0]; w2[8 +: 8] = VBP[7:0];
            w2[16 +: 8] = 8'd4; w2[24 +: 8] = 8'd4; w2[32 +: 8] = 8'd3; w2[40 +: 8] = 8'd2;   // PLL dummies
            w3 = 0; w3[16 +: 8] = CEPIX[7:0]; w3[24 +: 8] = ILACE[7:0];                         // ce_pix (HW 240p=12), interlace
            write_word(28'd8, w1); write_word(28'd16, w2); write_word(28'd24, w3);
            switchres_frame = 0;
            cmd_switchres_req = 1; @(posedge clk_sys); @(posedge clk_sys); cmd_switchres_req = 0;
            while (cmd_switchres) @(posedge clk_sys);
        end
    endtask

    // /58 reconnect repro: mirrors what a REAL reconnect does to the core -- setInit()'s forced
    // cmd_init edge (the /87 fix) plus a CmdSwitchres replay (api/groovymister.cpp:987, sent by
    // every reconnect when a modeline was already established). Both independently assert
    // eng_abort_r in the extracted FSM (Groovy.sv:949-950: `!cmd_init || reset_switchres`).
    reg        reconnect_active = 0;
    integer    trace_window_start = -1;
    reg        trace_window_active = 0;
    task do_reconnect;
        begin
            reconnect_active = 1;
            $display("[RECONNECT] cmd_init -> 0 @cyc=%0d", cycles);
            cmd_init = 1'b0;
            repeat (RECONNECT_LOWCYC) @(posedge clk_sys);
            cmd_init = 1'b1;
            $display("[RECONNECT] cmd_init -> 1 @cyc=%0d", cycles);
            trace_window_start  = cycles;
            trace_window_active = 1;
            repeat (50) @(posedge clk_sys);
            if (PLL_GLITCH_NS > 0) begin
                $display("[RECONNECT] PLL glitch: freezing clk_sys for %0dns starting @cyc=%0d", PLL_GLITCH_NS, cycles);
                pll_glitch_active = 1'b1;
                fork
                    do_switchres;
                    #(PLL_GLITCH_NS) pll_glitch_active = 1'b0;
                join
                $display("[RECONNECT] switchres replayed (through a %0dns clk_sys freeze) @cyc=%0d", PLL_GLITCH_NS, cycles);
            end else begin
                do_switchres;
                $display("[RECONNECT] switchres replayed @cyc=%0d", cycles);
            end
            reconnect_active = 0;
        end
    endtask

    // /58 reconnect DDR-contention trace: dumps on any CHANGE (FSM state, ddr_mux2 grant, engine
    // state, wd_fired rising edge) for a bounded window after the simulated reconnect -- to see
    // exactly what wins DDR arbitration while the engine's liveness watchdog fires. Edge-triggered
    // (not per-cycle) to keep the log a readable size across a multi-million-cycle window.
    reg [7:0] trc_fsm_d = 0; reg [1:0] trc_g_d = 0; reg [3:0] trc_eng_d = 0; reg trc_wdf_d = 0;
    always @(posedge clk_sys) begin
        trc_fsm_d <= state; trc_g_d <= ddr_mux.g; trc_eng_d <= eng_st_w; trc_wdf_d <= eng_wd_fired;
        if (trace_window_active) begin
            if (state != trc_fsm_d || ddr_mux.g != trc_g_d || eng_st_w != trc_eng_d || (eng_wd_fired && !trc_wdf_d))
                $display("[RTRC %0d] fsm=%0d->%0d mux_g=%0d->%0d eng_st=%0d->%0d wd_fired=%0d pend=%0d wd=%0d busy=%0d ddr_req=%0d ddr_busy=%0d",
                         cycles, trc_fsm_d, state, trc_g_d, ddr_mux.g, trc_eng_d, eng_st_w,
                         eng_wd_fired, eng_pend_valid, u_eng.wd, eng_busy_w, ddr_data_req, ddr_busy);
            if ((cycles - trace_window_start) > TRACE_WINDOW_CYC) trace_window_active = 0;
        end
    end

    // RAW: $fread the BYTE-EXACT nlc_synth marker_NNN.raw (the SAME generator hardware uses — no Verilog
    // re-implementation, so sim and HW show identical visuals) and write it to the FB, then blit. The marker
    // moves per frame (magenta bar position + binary counter), so the dumped sequence tests MOTION.
    reg [7:0] framebuf [0:1036799];   // 720*480*3
    task feed_raw(input [23:0] fr);
        integer fd, nb, i, idx; reg [511:0] nm;
        begin
            idx = (fr - 1) % NMARK;
            $sformat(nm, "%0s/marker_%03d.raw", MDIR, idx);
            fd = $fopen(nm, "rb");
            if (fd == 0) begin $display("FATAL: cannot open %0s", nm); $finish; end
            nb = $fread(framebuf, fd); $fclose(fd);
            // The real host writes pixel data WORD-ALIGNED (HEADER_OFFSET=248); the clean decode reads
            // 64-bit words and extracts {r,g,b}=word[0+:24]. So the FB must start at the word boundary
            // (DDR_FB_OFFSET masked to /8), NOT the raw 0xff (byte 7 of the word) which shifts the bytes.
            for (i = 0; i < W*H*3; i = i + 1) put_byte((DDR_FB_OFFSET & 28'h7FFFFF8) + i, framebuf[i]);
            blit_header(fr);
        end
    endtask
    task blit_header(input [23:0] fr);
        reg [63:0] hdr;
        begin
            hdr = 0; hdr[23:0] = fr; hdr[47:24] = (W*H); hdr[63:48] = 16'd1;
            write_word(28'd0, hdr);
            cmd_blit_req = 1; @(posedge clk_sys); @(posedge clk_sys); cmd_blit_req = 0;
            $display("[ANN] fr=%0d cyc=%0d", fr, cycles);
        end
    endtask

    // byte-granular DDR write (read-modify-write the 64-bit word)
    task put_byte(input [27:0] ba, input [7:0] d);
        reg [63:0] w; integer sh;
        begin w = mem[ba>>3]; sh = (ba[2:0])*8; w[sh +: 8] = d; mem[ba>>3] = w; end
    endtask

    // LZ4: $fread the BYTE-EXACT nlc_synth marker_NNN.lz4 (same generator hardware uses), deposit in zone A +
    // header, trigger cmd_blit_lz4 (chunked announces, like the real receive path).
    task feed_lz4(input [23:0] fr);
        integer fd, i, sent, nblit, idx; reg [27:0] base; reg [63:0] w, hdr; reg [511:0] nm;
        begin
            idx = (fr - 1) % NMARK;
            $sformat(nm, "%0s/marker_%03d.lz4", MDIR, idx);
            fd = $fopen(nm, "rb");
            if (fd == 0) begin $display("FATAL: cannot open %0s", nm); $finish; end
            lz4cs = $fread(lz4buf, fd); $fclose(fd);
            base = DDR_LZ_OFFSET_A & 28'h7FFFFF8;
            for (i = 0; i < lz4cs + 8; i = i + 8) begin
                w = {lz4buf[i+7],lz4buf[i+6],lz4buf[i+5],lz4buf[i+4],lz4buf[i+3],lz4buf[i+2],lz4buf[i+1],lz4buf[i]};
                mem[(base+i)>>3] = w;
            end
            lz4_size = lz4cs; lz4_ABCD = 0; lz4_field = 0;
            hdr = 0; hdr[23:0] = fr; write_word(DDR_LZ_HEADER, hdr);
            cmd_blit_lz4_req = 1; @(posedge clk_sys); @(posedge clk_sys); cmd_blit_lz4_req = 0;
            $display("[ANN] fr=%0d cyc=%0d", fr, cycles);
            sent = 0; nblit = 0;
            while (sent < lz4cs) begin
                sent = (sent + CHUNK > lz4cs) ? lz4cs : sent + CHUNK;
                nblit = nblit + 1;
                hdr = 0; hdr[23:0] = fr; hdr[47:24] = sent[23:0]; hdr[63:48] = nblit[15:0];
                write_word(DDR_LZ_HEADER, hdr);
                repeat (CHUNKGAP) @(posedge clk_sys);
            end
        end
    endtask

    // NLC: same as feed_lz4 but reads the byte-exact nlc_synth marker_NNN.nlc into LZ zone A; codec_mode==2
    // routes the dispatcher to the NLC decoder. NLC reuses the LZ4 blit transport + announce.
    task feed_nlc(input [23:0] fr);
        integer fd, i, sent, nblit, idx, zone; reg [27:0] base; reg [63:0] w, hdr; reg [511:0] nm;
        begin
            // /57 wmrace: the PREVIOUS frame's final watermark rewrite lands back-to-back with THIS
            // frame's announce (the HPS write-level race under bursty traffic). With a small gap the
            // FSM's ~us header re-read cadence usually MISSES it -> the engine starves non-final.
            if (WMRACE && wmrace_pend) begin
                write_word(DDR_LZ_HEADER, wmrace_hdr);
                wmrace_pend = 0;
                repeat (WMRACEG) @(posedge clk_sys);
            end
            idx = (fr - 1) % NMARK;
            $sformat(nm, "%0s/marker_%03d.nlc", MDIR, idx);
            fd = $fopen(nm, "rb");
            if (fd == 0) begin $display("FATAL: cannot open %0s", nm); $finish; end
            lz4cs = $fread(lz4buf, fd); $fclose(fd);
            // HW-faithful: rotate the 4 DDR-LZ zones so an in-flight decode of frame N is NOT overwritten by
            // the next frame's data (the host rotates per frame). Without this the single-zone sim corrupts
            // every overlapping decode — a sim artifact, not an FSM bug.
            zone = (fr - 1) % 4;
            base = (zone==0 ? DDR_LZ_OFFSET_A : zone==1 ? DDR_LZ_OFFSET_B : zone==2 ? DDR_LZ_OFFSET_C : DDR_LZ_OFFSET_D) & 28'h7FFFFF8;
            for (i = 0; i < lz4cs + 8; i = i + 8) begin
                w = {lz4buf[i+7],lz4buf[i+6],lz4buf[i+5],lz4buf[i+4],lz4buf[i+3],lz4buf[i+2],lz4buf[i+1],lz4buf[i]};
                mem[(base+i)>>3] = w;
            end
            lz4_size = lz4cs; lz4_ABCD = zone[1:0]; lz4_field = 0;
            if ($test$plusargs("adopt_late")) begin
                // TEST: mimic the HW case where the FSM only adopts the frame AFTER its data + 65535 sentinel are
                // already in DDR (slow/starved FSM). The header shows blit=65535 the moment the FSM reads it.
                hdr = 0; hdr[23:0] = fr; hdr[47:24] = lz4cs[23:0]; hdr[63:48] = 16'd65535; write_word(DDR_LZ_HEADER, hdr);
                cmd_blit_lz4_req = 1; @(posedge clk_sys); @(posedge clk_sys); cmd_blit_lz4_req = 0;
                $display("[ANN] fr=%0d cyc=%0d", fr, cycles);
                repeat (CHUNKGAP) @(posedge clk_sys);
            end else begin
            hdr = 0; hdr[23:0] = fr; write_word(DDR_LZ_HEADER, hdr);
            cmd_blit_lz4_req = 1; @(posedge clk_sys); @(posedge clk_sys); cmd_blit_lz4_req = 0;
            $display("[ANN] fr=%0d cyc=%0d", fr, cycles);
            sent = 0; nblit = 0;
            while (sent < lz4cs) begin
                sent = (sent + CHUNK > lz4cs) ? lz4cs : sent + CHUNK;
                nblit = nblit + 1;
                hdr = 0; hdr[23:0] = fr; hdr[47:24] = sent[23:0]; hdr[63:48] = nblit[15:0];
                // /57: a chunk rewrite with wm==size ALSO conveys finality (the FSM's final check is
                // sentinel||wm>=size), so the race modes must suppress the last rewrite too.
                if ((fr == WMDROP || WMRACE) && sent >= lz4cs) ;
                else write_word(DDR_LZ_HEADER, hdr);
                repeat (CHUNKGAP) @(posedge clk_sys);
            end
            end
            // HW-faithful final-blit SENTINEL: the HPS sends one last announce with nblit=65535 once the whole
            // compressed frame is in DDR (groovy.cpp:1964). Stage A's sim never sent this, so it missed the
            // /36 wedge. Now the FSM sees "all data present" exactly as on hardware.
            hdr = 0; hdr[23:0] = fr; hdr[47:24] = lz4cs[23:0]; hdr[63:48] = 16'd65535;
            if (fr == WMDROP)
                $display("[WMDROP] fr=%0d final watermark rewrite SUPPRESSED (last observed wm < size, no sentinel)", fr);
            else if (WMRACE && fr > 1) begin
                // deferred into the next frame's announce window (never frame 1: the TB's feed loop is
                // vblank-paced, and a stalled bootstrap frame would stall the pacing itself — on HW the
                // host announces on its own clock, so the equivalent situation self-resolves)
                wmrace_hdr = hdr; wmrace_pend = 1;
            end
            else write_word(DDR_LZ_HEADER, hdr);
        end
    endtask

    // NLC completion counter — the sim analog of the HW `eof` count (how often a frame reaches nlc_done).
    integer nlc_completions = 0; reg nlc_done_d = 0;
    always @(posedge clk_sys) begin
        nlc_done_d <= nlc_done;
        if (nlc_done && !nlc_done_d) nlc_completions = nlc_completions + 1;
    end

    // /57 ENGINE-WEDGE monitor — the exact HW signature: engine busy with a newer frame pending while
    // completions, FB flushes and busy edges are ALL frozen for >3 liveness windows (3x2^20 cyc). The
    // stale-wd ping-pong (E_RUN<->E_FLSHRQ, escapes firing on an inherited saturated counter) parks
    // exactly like this; a healthy engine always shows done_stb / flushed growth / an adopt well
    // inside one window (a starved frame abandons after ONE window, 2^20 cyc).
    integer eng_prog_cyc = 0; reg engwedge_logged = 0; reg [27:0] engfl_d = 0; reg engbusy_d = 0;
    integer eng_done_total = 0;
    always @(posedge clk_sys) begin
        engfl_d   <= eng_flushed;
        engbusy_d <= eng_busy_w;
        if (eng_done_stb) eng_done_total = eng_done_total + 1;
        if (!eng_busy_w || eng_done_stb || eng_flushed != engfl_d || eng_busy_w != engbusy_d)
            eng_prog_cyc = cycles;
        if (eng_busy_w && eng_pend_valid && (cycles - eng_prog_cyc) > 3145728 && !engwedge_logged) begin
            engwedge_logged = 1;
            $display("*** ENGWEDGE @%0d: engine parked st=%0d fr=%0d wm=%0d/%0d final=%0d wcnt=%0d wd_fired=%0d flushed=%0d pend=%0d (the /57 E_RUN park) ***",
                     cycles, eng_st_w, eng_cur_frame, u_eng.cur_wm, u_eng.cur_size, {31'd0,u_eng.cur_final},
                     u_eng.wcnt, eng_wd_fired, eng_flushed, eng_pend_valid);
        end
    end

    // /41 THROUGHPUT CALIBRATION METRIC — robust, phase-independent, measured IDENTICALLY for RAW/LZ4/NLC:
    // eof_frames = count of vram_end_frame (the FPGA `eof`) rising edges = frames that FULLY completed;
    // disp_frames = vga_frame elapsed. Completion rate = eof_frames/disp_frames. Calibrate the DDR model so the
    // RATIO matches /41 (RAW 25.2% / LZ4 21.5% / NLC 4.4% => NLC completes ~5x fewer full frames than LZ4).
    integer eof_frames = 0; reg [23:0] vgf0 = 0; reg captured0 = 0; reg [23:0] pfv_d0 = 0;
    // PUBLISHED-FRAME PERIOD = time between PoC_frame_vram advances (a frame actually completed decode+published)
    // = the sim's per-frame PROCESSING time, comparable to the /41 HW frame period (RAW/LZ4 ~15ms, NLC ~40ms).
    // (vram_end_frame was WRONG — it fires per DISPLAY frame/beam, not per decode completion.)
    integer last_pub_cyc = 0, pub_period_sum = 0, pub_period_n = 0;
    // CLEANEST NLC processing metric: nlc_busy duration (Setup 0->1 to End 1->0) = the decode+FB-write time for ONE
    // frame, unconfounded by frameskip republishing. Average it -> the NLC per-frame processing time (HW: ~40ms).
    reg nb_d = 0; integer nb_start = 0, nb_sum = 0, nb_n = 0;
    always @(posedge clk_sys) begin
        nb_d <= nlc_busy;
        if (nlc_busy && !nb_d) nb_start <= cycles;
        if (!nlc_busy && nb_d && vga_frame > 3 && nb_start > 0) begin nb_sum = nb_sum + (cycles - nb_start); nb_n = nb_n + 1; end
    end
    always @(posedge clk_sys) begin
        pfv_d0 <= PoC_frame_vram;
        if (PoC_frame_vram != pfv_d0 && vga_frame > 3) begin
            eof_frames = eof_frames + 1;
            if (last_pub_cyc > 0) begin pub_period_sum = pub_period_sum + (cycles - last_pub_cyc); pub_period_n = pub_period_n + 1; end
            last_pub_cyc = cycles;
        end
        if (!captured0 && vga_frame > 3) begin vgf0 <= vga_frame; captured0 <= 1'b1; end
    end

    // STAGE A2 NO-WEDGE ASSERTION + displayed-frame counter. A frame is DISPLAYED when PoC_frame_vram advances
    // (the robust completion can publish WITHOUT nlc_done, so we track display progress, not the done edge).
    // The FSM must NEVER sit busy in the NLC states without producing a displayed frame — that is the /36 wedge.
    integer nlc_displayed = 0, last_progress_cyc = 0; reg [23:0] fv_d = 0; reg wedged = 0;
    always @(posedge clk_sys) begin
        fv_d <= PoC_frame_vram;
        if (PoC_frame_vram != fv_d) begin nlc_displayed = nlc_displayed + 1; last_progress_cyc = cycles; end
        if (CODEC == 2 && nlc_busy && (cycles - last_progress_cyc) > (3000000 + vga_pixels*12) && !wedged) begin   // threshold scales with resolution (a legit 480p frame is ~3.2M cyc pre-Stage-B)
            wedged = 1;
            $display("*** WEDGE: no displayed NLC frame for >3M cyc while nlc_busy @%0d (st=%0d done=%0d wr=%0d/%0d ub=%0d) ***",
                     cycles, state, nlc_done, PoC_subframe_wr_bytes, nlc_frame_bytes, nlc_uncompressed_bytes);
        end
    end

    // FIFO HEALTH — the /37 failure: the VRAM FIFO underruns (the producer can't feed it ahead of the beam),
    // so vga.v drops vram_synced -> garbage. Count underrun events (sync drops while the display is up) and the
    // min FIFO occupancy during active scan. Streaming should keep vram_synced solid + vram_queue well above 0.
    integer vram_unsync_events = 0, vqmin = 100000000; reg vs_d = 0; reg display_up = 0;
    always @(posedge clk_sys) begin
        vs_d <= vram_synced;
        if (vga_frame > 0) display_up <= 1;                       // display has bootstrapped
        if (display_up && vs_d && !vram_synced) vram_unsync_events = vram_unsync_events + 1;  // underrun: sync just dropped
        if (display_up && !vblank_core && vram_synced && vram_queue < vqmin) vqmin = vram_queue;
    end

    // TRUE starvation margin: vram_queue sampled only at an ACTIVE-AREA pixel pop (vqmin above also
    // samples hblank, where nothing is being drained). vq_lt_line counts pops with under one line queued.
    integer vqmin_act = 100000000, vq_lt_line = 0, act_px = 0;
    integer vqmin_line = -1, vqlow_first = 100000, vqlow_last = 0;
    always @(posedge clk_sys) if (ce_pix && display_up && vga_frame >= 3 && vga_de_w && vram_synced) begin
        act_px = act_px + 1;
        if (vram_queue < vqmin_act) begin vqmin_act = vram_queue; vqmin_line = vga_vcount; end
        if (vram_queue < PoC_H) begin
            vq_lt_line = vq_lt_line + 1;
            if (vga_vcount < vqlow_first) vqlow_first = vga_vcount;
            if (vga_vcount > vqlow_last)  vqlow_last  = vga_vcount;
        end
    end

    // FSM SCHEDULING — the /39 failure: the NLC FSM never COMMITS decoded frames on HW (frozen FB). Measure where
    // the FSM spends time (fskip auto-blit vs the NLC decode states) + how many FB writes actually fire + whether
    // the FB region ever CHANGES. If the sim reproduces /39 it will show: FSM starved into the auto-blit, ~0 FB
    // writes, a frozen FB.
    integer fsk_cyc=0, inf_cyc=0, prep_cyc=0, ablit_cyc=0, fbw_cnt=0, tot_cyc=0; reg dw_d=0;
    integer fbmode_cyc=0, strm_stall_cyc=0;
    reg [63:0] fb_sig=0, fb_sig_prev=0; integer fb_changes=0; integer scnt=0;
    always @(posedge clk_sys) begin
        if (CODEC==2) begin
            tot_cyc=tot_cyc+1;
            if (cmd_fskip) fsk_cyc=fsk_cyc+1;
            if (state==S_Blit_Inflate_NLC) inf_cyc=inf_cyc+1;
            // streaming vs FB mode + streaming-gate stall (commit blocked by !vram_req_ready = the /39 suspect)
            if (state==S_Blit_Inflate_NLC && PoC_frame_lz4_FB) fbmode_cyc=fbmode_cyc+1;
            if (state==S_Blit_Inflate_NLC && nlc_long_valid && !PoC_frame_lz4_FB && !vram_req_ready) strm_stall_cyc=strm_stall_cyc+1;
            if (state==S_Blit_Prepare_NLC)  prep_cyc=prep_cyc+1;
            if (state>=S_Blit_Auto_Skip && state<=8'd29) ablit_cyc=ablit_cyc+1;   // auto-blit states 26-29
            dw_d<=ddr_data_write;
            if (ddr_data_write && !dw_d && ddr_addr < DDR_AB_OFFSET) fbw_cnt=fbw_cnt+1;  // FB-region write edge
            // periodic FB-region signature (does the framebuffer ever change, like /39?)
            scnt=scnt+1;
            if (scnt>=40000) begin
                scnt=0; fb_sig = mem[(28'hff)>>3] ^ mem[(28'hff+96000)>>3] ^ mem[(28'hff+192000)>>3];
                if (fb_sig!=fb_sig_prev) fb_changes=fb_changes+1; fb_sig_prev=fb_sig;
            end
        end
    end

    // PHASE trace: log the rgb-offset + vram byte phase at each blit-read start (Prepare_Raw entry) to catch the
    // frame-2+ byte-phase divergence (frame 1 displays exact, frames 2+ show a +1/+2 phase error).
    reg [7:0] st_pd = 0; integer blit_log = 0;
    always @(posedge clk_sys) begin
        st_pd <= state;
        // catch the BUG: a fresh read (vram_bytes==0) that starts with rgb_off != 0, and show the state that led in
        if (CODEC==2 && state==8'd22 && st_pd!=8'd22 && PoC_subframe_vram_bytes==0 && blit_log < 80) begin
            $display("[BLIT cyc=%0d from_state=%0d] fv=%0d fd=%0d px_vram=%0d px_ddr=%0d vram_bytes=%0d rgb_off=%0d bl_ddr=%0d bl_vram=%0d %0s",
                cycles, st_pd, PoC_frame_vram, PoC_frame_ddr, PoC_subframe_px_vram, PoC_subframe_px_ddr,
                PoC_subframe_vram_bytes, PoC_frame_rgb_offset, PoC_subframe_bl_ddr, PoC_subframe_bl_vram,
                (PoC_frame_rgb_offset!=0) ? "<<< BUG: fresh read, nonzero offset" : "");
            blit_log = blit_log + 1;
        end
    end

    // frame-start snapshot: queue/sync at each vcount wrap (+debug=1) — why does Auto_First miss?
    reg [9:0] vc_d = 0;
    always @(posedge clk_sys) if (DEBUG) begin
        vc_d <= vga_vcount;
        if (vga_vcount == 10'd0 && vc_d != 10'd0)
            $display("[VC0 %0d] queue=%0d sync=%0d vram_px=%0d frame_vram=%0d vga_frame=%0d st=%0d",
                     cycles, vram_queue, vram_synced, vram_pixels, PoC_frame_vram, vga_frame, state);
    end

    // PULSE-ACCURATE repeat-path counters (the SCHED %-metrics hide 1-cycle pulses)
    integer fsk_pulses = 0, auto_first_n = 0, auto_line_n = 0, blitraw_n = 0; reg [7:0] stp2 = 0;
    always @(posedge clk_sys) begin
        stp2 <= state;
        if (cmd_fskip) fsk_pulses = fsk_pulses + 1;
        if (state == 8'd27 && stp2 != 8'd27) auto_first_n = auto_first_n + 1;
        if (state == 8'd28 && stp2 != 8'd28) auto_line_n  = auto_line_n + 1;
        if (state == 8'd21 && stp2 != 8'd21) blitraw_n    = blitraw_n + 1;
    end

    // NLC-state TRANSITION trace (+debug=1): every FSM state change among the NLC states, with the key regs +
    // decoder internals (hierarchical peek — Verilator resolves u_nlc.*). Catches the park sequence exactly.
    reg [7:0] st_prev = 0;
    always @(posedge clk_sys) if (DEBUG) begin
        st_prev <= state;
        if (state != st_prev && ((state >= 8'd80 && state <= 8'd86) || (st_prev >= 8'd80 && st_prev <= 8'd86)))
            $display("[NST %0d] %0d->%0d busy=%0d ablz4=%0d strm=%0d wrb=%0d writed=%0d sub=%0d ub=%0d lv=%0d done=%0d | dec: cst=%0d ldst=%0d brdy=%b ifcnt=%0d ldlines=%0d ofcnt=%0d",
                cycles, st_prev, state, nlc_busy, auto_blit_lz4, nlc_stream_ok, PoC_subframe_wr_bytes,
                nlc_writed_bytes, PoC_subframe_lz4_ddr_bytes, nlc_uncompressed_bytes, nlc_long_valid, nlc_done,
                u_nlc.cst, u_nlc.ld_st, u_nlc.bank_rdy, u_nlc.if_count, u_nlc.ld_lines, u_nlc.of_count);
    end

    // ================= /46 DECODE PIPELINE PROFILE (measure where the 2.8ms/frame goes) =================
    // Counts cycles WHILE nlc_busy (one frame's decode+FB-write), split by (a) FSM state and (b) decoder
    // controller state cst, plus FIFO-pressure stalls. Reported at end as cycles + %.
    integer pf_frames = 0; reg pf_bd = 0;
    always @(posedge clk_sys) begin pf_bd <= nlc_busy; if (CODEC==2 && !nlc_busy && pf_bd && vga_frame > 3) pf_frames = pf_frames + 1; end
    // FSM-state cycles (during nlc_busy)
    integer c_setup=0, c_prep=0, c_copy=0, c_infl=0, c_flush=0, c_hdrend=0;
    // decoder controller-state cycles (cst), sampled every clk while nlc_busy
    integer cc_wait=0, cc_prime=0, cc_hdr=0, cc_a=0, cc_b=0, cc_eol=0, cc_flush=0, cc_done=0;
    // FIFO pressure while nlc_busy
    integer c_offull=0, c_iflow=0, c_ifempty=0, c_busytot=0;
    always @(posedge clk_sys) if (CODEC==2 && nlc_busy && vga_frame > 3) begin
        c_busytot = c_busytot + 1;
        case (state)
            8'd81: c_setup  = c_setup  + 1;
            8'd82: c_prep   = c_prep   + 1;
            8'd83: c_copy   = c_copy   + 1;
            8'd84: c_infl   = c_infl   + 1;
            8'd86: c_flush  = c_flush  + 1;
            default: c_hdrend = c_hdrend + 1;   // 80 header / 85 end / transitions
        endcase
        case (u_nlc.cst)
            3'd0: cc_wait  = cc_wait  + 1;
            3'd1: cc_prime = cc_prime + 1;
            3'd2: cc_hdr   = cc_hdr   + 1;
            3'd3: cc_a     = cc_a     + 1;
            3'd4: cc_b     = cc_b     + 1;
            3'd5: cc_eol   = cc_eol   + 1;
            3'd6: cc_flush = cc_flush + 1;
            3'd7: cc_done  = cc_done  + 1;
        endcase
        if (u_nlc.of_count >= 8'd118) c_offull  = c_offull  + 1;   // output FIFO ~full -> FB-write/drain backpressure
        if (u_nlc.if_count <  9'd20)  c_iflow   = c_iflow   + 1;   // input FIFO low -> feed can't keep up
        if (u_nlc.if_count == 9'd0)   c_ifempty = c_ifempty + 1;   // input FIFO EMPTY -> decoder starved
    end

    // STAGE A debug: periodic FSM/decoder trace to see where an NLC decode parks.
    integer trc = 0;
    always @(posedge clk_sys) if (DEBUG && CODEC == 2) begin
        trc = trc + 1;
        if (trc % 40000 == 0)
            $display("[TRC %0d] st=%0d done=%0d paused=%0d lv=%0d ordy=%0d busy=%0d fskip=%0d wr=%0d rd=%0d ub=%0d sub=%0d wrb=%0d vrampx=%0d | eng st=%0d busy=%0d fr=%0d fl=%0d pend=%0d act=%0d wm=%0d abrt=%0d",
                cycles, state, nlc_done, nlc_paused, nlc_long_valid, nlc_out_ready, nlc_busy, cmd_fskip,
                nlc_writed_bytes, nlc_readed_bytes, nlc_uncompressed_bytes, PoC_subframe_lz4_ddr_bytes, PoC_subframe_wr_bytes, vram_pixels,
                eng_st_w, eng_busy_w, eng_cur_frame, eng_flushed, nlc_present_pending, nlc_present_active, u_eng.cur_wm, eng_abort_r);
    end

    integer fi, framep; reg [23:0] frnum; integer wcyc; reg FEEDFAST, CLOSEDLOOP;
    initial FEEDFAST = $test$plusargs("feedfast");   // WaitSync-like: feed next frame only after the prev is published
    initial CLOSEDLOOP = $test$plusargs("closedloop");   // api-FAITHFUL sender pacing (WaitSync raster-echo feedback)
    integer EMULMS10;  // sender-side per-blit work (encode etc.) in 0.1ms units (+emulms10=N; HW A9 NLC ~ 350-400)
    initial if (!$value$plusargs("emulms10=%d", EMULMS10)) EMULMS10 = 0;

    // ---- CLOSED-LOOP sender pacing (api/groovymister.cpp WaitSync + DiffTimeRaster, faithfully) -------------
    // The sender sleeps ~frameTime, adjusted by the raster-echo feedback: dif = (vc1 - vc2)/2 lines, where
    // vc1 = (frameEcho-1)*vtotal + vCountEcho (where the raster SHOULD be for our frame counter) and
    // vc2 = fpga_frame*vtotal + fpga_vcount (where it actually is) — all sampled from the blit ACK. If the
    // FPGA's raster lags the sent-frame count (e.g. PARKED by vga_wait_vblank), dif>0 -> the sender SLOWS.
    // This is the feedback loop the open-loop vblank feed never modeled (the suspected /41-/42 limit cycle).
    integer cl_emul_start;                 // cycle when the last WaitSync ended (emulationTime reference)
    integer feed_prev_cyc = 0, feed_per_sum = 0, feed_per_n = 0;   // blit-to-blit period stats (the HW fingerprint)
    task wait_sync_api(input integer sent_frame);
        integer vtotal_l, htot_cyc, frame_cyc, sleep_cyc, emul_cyc, vc1, vc2, dif, elapsed;
        begin
            // modeline geometry in clk_sys cycles (cepix per pixel)
            vtotal_l  = H + VFP + VSv + VBP;
            htot_cyc  = (W + HFP + HSv + HBP) * CEPIX;
            frame_cyc = vtotal_l * htot_cyc;
            emul_cyc  = cycles - cl_emul_start;
            sleep_cyc = frame_cyc - emul_cyc; if (sleep_cyc < 0) sleep_cyc = 0;
            // DiffTimeRaster once per blit, from the ACK-time samples (immediate-ACK model: sampled now)
            vc1 = (sent_frame - 1) * vtotal_l + vga_vcount;
            vc2 = vga_frame * vtotal_l + vga_vcount;
            dif = (vc1 - vc2) / 2;
            sleep_cyc = sleep_cyc + dif * htot_cyc;
            if (sleep_cyc < 0) sleep_cyc = 0;
            if (sleep_cyc > frame_cyc * 8) sleep_cyc = frame_cyc * 8;   // sanity clamp
            repeat (sleep_cyc) @(posedge clk_sys);
            cl_emul_start = cycles;
            // blit period stats
            if (feed_prev_cyc != 0) begin feed_per_sum = feed_per_sum + (cycles - feed_prev_cyc); feed_per_n = feed_per_n + 1; end
            feed_prev_cyc = cycles;
        end
    endtask
    initial begin
        framep = (CADENCE != 0) ? CADENCE : (W+40)*(H+30)*6 + 5000;   // ~one frame period in clk cycles
        repeat (50) @(posedge clk_sys);
        $display("CLEAN-DISP: codec=%0d W=%0d H=%0d interlace=%0d frames=%0d framep=%0d", CODEC, W, H, ILACE, N_FRAMES, framep);
        $display("DDRPARAMS: READ_LAT=%0d WR_OVERHEAD=%0d WR_BEAT=%0d (single-beat write = %0d cyc; bursts declared by ddr_burst)", READ_LAT, WR_OVERHEAD, WR_BEAT, WR_OVERHEAD+WR_BEAT);
        codec_mode = CODEC[1:0];   // 0=raw 1=LZ4 2=NLC (the dispatcher routes cmd_blit_lz4 to NLC when ==2)
        do_switchres;
        $display("[%0d] switchres applied PoC_H=%0d PoC_V=%0d", cycles, PoC_H, PoC_V);
        repeat (2000) @(posedge clk_sys);
        // frame 1 bootstraps the display (no raster yet, so can't wait for vblank); let it come up.
        frnum = 1; if (CODEC == 0) feed_raw(1); else if (CODEC == 1) feed_lz4(1); else feed_nlc(1);
        repeat (framep) @(posedge clk_sys);
        if (DEBUG) dump_fb("/tmp/fb_frame1.bin");   // FB after the first (bootstrap) frame
        if (DEBUG) $display("[NLCDBG] PoC_V=%0d FB_il=%0d vga_pixels=%0d | dec uncompressed_bytes=%0d writed=%0d readed=%0d done=%0d paused=%0d | FSM wr_bytes=%0d sub_lz4_ddr_bytes=%0d",
                            PoC_V, PoC_FB_interlaced, vga_pixels, nlc_uncompressed_bytes, nlc_writed_bytes, nlc_readed_bytes, nlc_done, nlc_paused, PoC_subframe_wr_bytes, PoC_subframe_lz4_ddr_bytes);
        // frames 2+ : VSYNC-ALIGN the feed (like the host's vsync handshake) so the new frame is whole
        // before the next active scan — no mid-display tear from a fixed cadence.
        cl_emul_start = cycles;
        for (fi = 2; fi <= N_FRAMES; fi = fi + 1) begin
            if (CLOSEDLOOP) begin
                repeat (EMULMS10 * 8275) @(posedge clk_sys);   // the sender's per-blit CPU work (ARM encode)
                wait_sync_api(fi - 1);     // pace exactly like the real sender (raster-echo feedback)
            end else if (FEEDFAST) begin
                // WaitSync-like: wait until the PREVIOUS fed frame is published (PoC_frame_vram caught up), or a
                // bounded timeout. The eof-to-eof period then = the FPGA's PROCESSING time (comparable to /41).
                wcyc = 0;
                while (PoC_frame_vram < (fi-1) && wcyc < framep*8) begin @(posedge clk_sys); wcyc = wcyc + 1; end
            end else begin
                @(posedge vblank_core);
                if (ILACE != 0) @(posedge vblank_core);   // interlaced: feed once per FRAME-PAIR, not per field
            end
            frnum = fi;
            if (CODEC == 0) feed_raw(frnum); else if (CODEC == 1) feed_lz4(frnum); else feed_nlc(frnum);
            if (RECONNECT_AFTER > 0 && fi == RECONNECT_AFTER) do_reconnect;
        end
        if (WMRACE && wmrace_pend) begin write_word(DDR_LZ_HEADER, wmrace_hdr); wmrace_pend = 0; end   // let the LAST frame finalize
        repeat (framep*2) @(posedge clk_sys);
        dump_fb("/tmp/fb_final.bin");   // FB (DDR) content after all frames — bisect decode/FB-write vs display
        $display("RESULT: frames_out=%0d vga_frame=%0d PoC_frame_vram=%0d nlc_displayed=%0d (of %0d fed) cepix=%0d WBcost=%0d | FIFO: underrun=%0d vqmin=%0d | WEDGED=%0d BUSWEDGE=%0d FREEZE=%0d ENGWEDGE=%0d engdone=%0d", frames_out, vga_frame, PoC_frame_vram, nlc_displayed, N_FRAMES, CEPIX, WR_OVERHEAD+WR_BEAT, vram_unsync_events, vqmin, wedged, buswedge_logged, dbg_freeze_valid, engwedge_logged, eng_done_total);
        $display("MARGIN: vqmin_active=%0d (queue at an active pixel pop) | pops_under_one_line=%0d of %0d (%0d%%) | PoC_H=%0d | extstalls=%0d",
                 vqmin_act, vq_lt_line, act_px, act_px ? 100*vq_lt_line/act_px : 0, PoC_H, ext_injections);
        $display("MARGIN2: vqmin hit at line %0d | low-queue pops span lines %0d..%0d", vqmin_line, vqlow_first, vqlow_last);
        $display("STARVE: worst frame=%0d px (%0d.%0d lines) | total starved px=%0d | lead budget=%0d px", starve_max, starve_max/W, (starve_max*10/W)%10, starve_px_total, W*16);
        $display("STARVE-MIRROR (as Groovy.sv computes it): syncloss=%0d starve_max=%0d   | GROUND TRUTH: total=%0d max=%0d", m_syncloss, m_starve_max, starve_px_total, starve_max);
        $display("THRUPUT: codec=%0d published=%0d pub_period=%0d.%0dms | NLC_decode_time(nlc_busy) n=%0d avg=%0d.%0d ms (HW NLC ~40ms)", CODEC, eof_frames, pub_period_n?(pub_period_sum/pub_period_n)/82754:0, pub_period_n?((pub_period_sum/pub_period_n)*10/82754)%10:0, nb_n, nb_n?(nb_sum/nb_n)/82754:0, nb_n?((nb_sum/nb_n)*10/82754)%10:0);
        $display("REPEATS: fskip_pulses=%0d auto_first=%0d auto_line=%0d blit_raw=%0d", fsk_pulses, auto_first_n, auto_line_n, blitraw_n);
        if (CLOSEDLOOP && feed_per_n > 0)
            $display("CLOSEDLOOP: blit_period avg = %0d cyc = %0d.%0d ms over %0d blits (HW /42 NLC = 36-41ms; RAW/LZ4 ~15-17ms)",
                     feed_per_sum/feed_per_n, (feed_per_sum/feed_per_n)/82754, ((feed_per_sum/feed_per_n)*10/82754)%10, feed_per_n);
        if (CODEC==2) $display("SCHED: tot=%0d fskip=%0d%% inflate=%0d%% prepare=%0d%% autoblit=%0d%% | FB_writes=%0d FB_changes=%0d | FBmode_cyc=%0d strm_gate_stall_cyc=%0d", tot_cyc, tot_cyc?100*fsk_cyc/tot_cyc:0, tot_cyc?100*inf_cyc/tot_cyc:0, tot_cyc?100*prep_cyc/tot_cyc:0, tot_cyc?100*ablit_cyc/tot_cyc:0, fbw_cnt, fb_changes, fbmode_cyc, strm_stall_cyc);
        if (CODEC==2 && c_busytot>0) begin
            $display("PROFILE nlc_busy(clk_sys @%0dMHz) tot=%0d cyc = %0d.%0d ms/frame | FSM: setup=%0d%% prep=%0d%% copy=%0d%% INFLATE=%0d%% FLUSH=%0d%% hdr/end=%0d%%",
                     72, c_busytot, (c_busytot/pf_frames)/72550, (((c_busytot/pf_frames)*10)/72550)%10,
                     100*c_setup/c_busytot, 100*c_prep/c_busytot, 100*c_copy/c_busytot, 100*c_infl/c_busytot, 100*c_flush/c_busytot, 100*c_hdrend/c_busytot);
            $display("PROFILE decoder-cst: WAIT(feed-starved)=%0d%% PRIME=%0d%% HDR=%0d%% A=%0d%% B=%0d%% EOL=%0d%% cFLUSH=%0d%% DONE=%0d%%  [A+B=MED core work]",
                     100*cc_wait/c_busytot, 100*cc_prime/c_busytot, 100*cc_hdr/c_busytot, 100*cc_a/c_busytot, 100*cc_b/c_busytot, 100*cc_eol/c_busytot, 100*cc_flush/c_busytot, 100*cc_done/c_busytot);
            $display("PROFILE pressure: outFIFO-full(FBwrite-backpressure)=%0d%% inFIFO-low=%0d%% inFIFO-EMPTY(decoder-starved)=%0d%% | frames=%0d",
                     100*c_offull/c_busytot, 100*c_iflow/c_busytot, 100*c_ifempty/c_busytot, pf_frames);
        end
        $finish;
    end

    initial begin #2_000_000_000 $display("CLEAN-DISP TIMEOUT (frames_out=%0d BUSWEDGE=%0d FREEZE=%0d ENGWEDGE=%0d)", frames_out, buswedge_logged, dbg_freeze_valid, engwedge_logged); $finish; end
endmodule
