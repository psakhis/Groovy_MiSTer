
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <time.h>
#include <cstring>
#include <errno.h>

/* UDP server */
#include <sys/socket.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <sys/ioctl.h>
#include <net/if.h>	//ifconfig down/up

#ifdef _AF_XDP
/* AF_XDP server */
#include <xdp/libxdp.h>
#include <bpf/bpf.h>
#include <xdp/xsk.h>
#include <sys/resource.h> //rlimit
#include <assert.h>
#include <netinet/udp.h>
#include <netinet/ip.h>
#include <netinet/ether.h>
#include <linux/if_link.h> //DRV_MODE
#endif

#include "../../hardware.h"
#include "../../shmem.h"
#include "../../spi.h"
#include "../../file_io.h"
#include "../../user_io.h"

#include "logo.h"
#include "pll.h"
#include "utils.h"

// fork (input.cpp): route client-requested rumble to a player's pad (1-based player)
void input_rumble_player(int player, uint16_t rumble_val);

// USER_IO
static constexpr auto SCANDOUBLER_OPT = "[4:3]";
static constexpr auto ASPECT_RATIO_OPT = "[2:1]";
static constexpr auto SCALE_OPT = "[6:5]";
static constexpr auto ORIENTATION_OPT = "[10]";
static constexpr auto CROP_240P_OPT = "[11]";
static constexpr auto CROP_OFFSET_OPT = "[16:12]";
static constexpr auto CRT_H_OFFSET_OPT = "[21:17]";
static constexpr auto CRT_V_OFFSET_OPT = "[26:22]";
static constexpr auto CRT_SCALER_OPT = "[47]";
static constexpr auto CRT_SCALE_FACTOR_OPT = "[51:48]";
static constexpr auto PWM_OPT = "[37]";
static constexpr auto VOLATILE_FB_OPT = "[32]";
static constexpr auto VSYNC_OVERLAY_OPT = "[46]";
static constexpr auto AUDIO_OPT = "[34]";
static constexpr auto DESIRED_BUFFER_OPT = "[36:35]";
static constexpr auto SCREENSAVER_OPT = "[33]";
static constexpr auto ARM_CLOCK_OPT = "[45:44]";
static constexpr auto JUMBO_FRAMES_OPT = "[42]";
static constexpr auto PS2_INPUTS_OPT = "[39:38]";
static constexpr auto JOY_INPUTS_OPT = "[41:40]";
// (no rumble option here: rumble is gated per pad in the Controllers page and globally by
// MiSTer.ini RUMBLE. An OSD option used to live on [42] and silently shared that bit with
// JUMBO_FRAMES_OPT above, so toggling one changed the other.)
static constexpr auto VERBOSE_OPT = "[28:27]";
static constexpr auto BLIT_OPT = "[29]";
static constexpr auto AUDIO_RATE_OPT = "[53:52]";
static constexpr auto AUDIO_CHANNELS_OPT = "[55:54]";
static constexpr auto RGB_MODE_OPT = "[57:56]";
static constexpr auto LZ4_OPT = "[58]";
static constexpr auto SERVER_TYPE_OPT = "[59]";
// Idle timeout: close a session whose client has gone silent (killed/crashed/network drop) so the
// CRT is freed instead of holding the last frame forever. HPS-only option on free bits [8:7]
// (FPGA never wires them). 0=Off preserves the legacy infinite-hold. A client that is alive but
// not blitting holds the session open by sending any datagram, CMD_GET_STATUS being the cheapest.
static constexpr auto IDLE_TIMEOUT_OPT = "[8:7]";

// FPGA SPI commands
#define UIO_GET_GROOVY_STATUS     0xf0
#define UIO_SET_GROOVY_INIT       0xf2
#define UIO_SET_GROOVY_SWITCHRES  0xf3
#define UIO_SET_GROOVY_BLIT       0xf4
#define UIO_SET_GROOVY_LOGO       0xf5
#define UIO_SET_GROOVY_AUDIO      0xf6
#define UIO_SET_GROOVY_BLIT_LZ4   0xf7
#define UIO_SET_GROOVY_BLIT_FIELD_LZ4 0xf8

// FPGA DDR shared
#define BASEADDR 0x30000000 // Standard MiSTer core DDR window, outside Linux RAM.
                                // 0x1C000000 sat inside mem=511M, so kernel pages collided with
                                // the FPGA/app buffer and corrupted it. Must match
                                // rtl/ddram.sv's DDRAM_ADDR prefix (ship RBF+HPS together).
#define HEADER_LEN 0xff
#define CHUNK 7
#define HEADER_OFFSET HEADER_LEN - CHUNK
#define FRAMEBUFFER_SIZE  (720 * 576 * 4 * 2) // RGBA 720x576 with 2 fields
#define AUDIO_SIZE (8192 * 2 * 2)             // 8192 samples with 2 16bit-channels
#define LZ4_SIZE (720 * 576 * 4)              // Estimated LZ4 MAX
#define FIELD_OFFSET 0x195000                 // 0x12fcff position for fpga (after first field)
#define AUDIO_OFFSET 0x32a000                 // 0x25f8ff position for fpga (after framebuffer)
#define LZ4_OFFSET_A 0x332000                 // 0x2678ff position for fpga (after audio)
#define LZ4_OFFSET_B 0x4c7000                 // 0x3974ff position for fpga (after lz4_offset_A)
#define LZ4_OFFSET_C 0x65c000                 // 0x2678ff position for fpga (after lz4_offset_B)
#define LZ4_OFFSET_D 0x7f1000                 // 0x3974ff position for fpga (after lz4_offset_C)
#define BUFFERSIZE FRAMEBUFFER_SIZE + AUDIO_SIZE + LZ4_SIZE + LZ4_SIZE + LZ4_SIZE + LZ4_SIZE + HEADER_LEN

// UDP server
#define UDP_PORT 32100
#define UDP_PORT_INPUTS 32101
#define UDP_PORT_GMC 32105

#ifdef _AF_XDP
// XDP server
#define XDP_BASEADDR 0x15000000
#define XDP_NUM_FRAMES 65536 			     // pot 2 (min.4096)
#define XDP_FRAME_SIZE XSK_UMEM__DEFAULT_FRAME_SIZE
#define RX_BATCH_SIZE 1		     	     
#define INVALID_UMEM_FRAME UINT64_MAX
#endif

// v2: CMD_INIT accepts the optional 6th byte (client caps, CAP_*). Clients
// probe this with CMD_GET_VERSION before sending a len-6 init, because pre-v2
// cores silently discard any CMD_INIT length they don't recognise.
#define GROOVY_VERSION 2

// GroovyMiSTer protocol
#define CMD_CLOSE 1
#define CMD_INIT 2
#define CMD_SWITCHRES 3
#define CMD_AUDIO 4
#define CMD_GET_STATUS 5
#define CMD_BLIT_VSYNC 6
#define CMD_BLIT_FIELD_VSYNC 7
#define CMD_GET_VERSION 8

//https://stackoverflow.com/questions/64318331/how-to-print-logs-on-both-console-and-file-in-c-language
#define LOG_TIMER 25
#define VERBOSE_POLL_TIMER 250   // ms between OSD Verbose re-reads (see groovy_poll)
#define GROOVY_LOG_PATH "/tmp/groovynlc.log"
#define LOGO_TIMER 16
#define KEEP_ALIVE_FRAMES 45 * 60

static struct timespec logTS, logTS_ant, blitStart, blitStop;
static int doVerbose = 0;
static double difMs = 0;
static unsigned long logTime = 0;
static unsigned long verboseTime = 0;
static FILE * fp = NULL;
// Each session starts a fresh log by default, so one capture is one session. Append mode is the
// old behaviour and is still selectable, because a fault that needs several reconnects to
// reproduce loses its evidence if every CMD_INIT truncates the file. Select it with
// GROOVY_LOG_APPEND in the environment, else /media/fat/groovy_log_append.cfg, same shape as
// GROOVY_RECV_MODE.
static uint8_t logAppend = 0;
static uint32_t logSession = 0;

#define LOG(sev,fmt, ...) do {	\
			        if (sev == 0) printf(fmt, __VA_ARGS__);	\
			        if (fp && sev <= doVerbose) { \
			        	clock_gettime(CLOCK_MONOTONIC, &logTS); \
			        	difMs = (difMs != 0) ? diff_in_ms(&logTS_ant, &logTS) : -1; \
					fprintf(fp, "[%06.3f]", difMs); \
					fprintf(fp, fmt, __VA_ARGS__);	\
                                	clock_gettime(CLOCK_MONOTONIC, &logTS_ant); \
                                } \
                           } while (0)

typedef union
{
  struct
  {
    unsigned char bit0 : 1;
    unsigned char bit1 : 1;
    unsigned char bit2 : 1;
    unsigned char bit3 : 1;
    unsigned char bit4 : 1;
    unsigned char bit5 : 1;
    unsigned char bit6 : 1;
    unsigned char bit7 : 1;
  }u;
   uint8_t byte;
} bitByte;


typedef struct {
   //frame sync
   uint32_t PoC_frame_recv;
   uint32_t PoC_frame_ddr;

   //modeline + pll -> burst 3
   uint16_t PoC_H; 	// 08
   uint8_t  PoC_HFP; 	// 10
   uint8_t  PoC_HS; 	// 11
   uint8_t  PoC_HBP; 	// 12
   uint16_t PoC_V; 	// 13
   uint8_t  PoC_VFP; 	// 15
   uint8_t  PoC_VS;     // 16
   uint8_t  PoC_VBP;    // 17

   //pll
   uint8_t  PoC_pll_M0;  // 18 High
   uint8_t  PoC_pll_M1;  // 19 Low
   uint8_t  PoC_pll_C0;  // 20 High
   uint8_t  PoC_pll_C1;  // 21 Low
   uint32_t PoC_pll_K;   // 22
   uint8_t  PoC_ce_pix;  // 26    

   uint8_t  PoC_interlaced;
   uint8_t  PoC_FB_progressive;

   double   PoC_pclock;

   uint32_t PoC_buffer_offset; // FIELD/AUDIO/LZ4 position on DDR

   //framebuffer
   uint32_t PoC_bytes_len;
   uint32_t PoC_pixels_len;
   uint32_t PoC_bytes_recv;
   uint32_t PoC_pixels_ddr;
   uint32_t PoC_field_frame;
   uint8_t  PoC_field;

   double PoC_width_time;
   uint16_t PoC_V_Total;

   //audio
   uint32_t PoC_bytes_audio_len;

   //lz4
   uint32_t PoC_bytes_lz4_len;
   uint32_t PoC_bytes_lz4_ddr;
   uint8_t  PoC_field_lz4;
   uint8_t  PoC_delta_lz4;

   //joystick
   uint32_t  PoC_joystick_keep_alive;
   uint8_t   PoC_joystick_order;
   uint32_t  PoC_joystick_map1;
   uint32_t  PoC_joystick_map2;

   char      PoC_joystick_l_analog_X1;
   char      PoC_joystick_l_analog_Y1;
   char      PoC_joystick_r_analog_X1;
   char      PoC_joystick_r_analog_Y1;

   char      PoC_joystick_l_analog_X2;
   char      PoC_joystick_l_analog_Y2;
   char      PoC_joystick_r_analog_X2;
   char      PoC_joystick_r_analog_Y2;

   uint8_t   PoC_joystick_l_trigger1;   // analog triggers (inputs protocol v2 only)
   uint8_t   PoC_joystick_r_trigger1;
   uint8_t   PoC_joystick_l_trigger2;
   uint8_t   PoC_joystick_r_trigger2;

   //ps2
   uint32_t  PoC_ps2_keep_alive;
   uint8_t   PoC_ps2_order;
   uint8_t   PoC_ps2_keyboard_keys[ARRAY_BIT_SIZE(NUM_SCANCODES)]; //32 bytes
   uint8_t   PoC_ps2_mouse;
   uint8_t   PoC_ps2_mouse_x;
   uint8_t   PoC_ps2_mouse_y;
   uint8_t   PoC_ps2_mouse_z;

} PoC_type;

union {
    double d;
    uint64_t i;
} u;


#ifdef _AF_XDP
/* AF_XDP */
struct xsk_umem_info {
	struct xsk_ring_prod fq;
	struct xsk_ring_cons cq;
	struct xsk_umem *umem;
	void *buffer;
};

struct xsk_socket_info {
	struct xsk_ring_cons rx;
	struct xsk_ring_prod tx;
	struct xsk_umem_info *umem;
	struct xsk_socket *xsk;

	uint64_t umem_frame_addr[XDP_NUM_FRAMES];
	uint32_t umem_frame_free;

	uint32_t outstanding_tx;
};

static struct xsk_umem_info *umem;
static struct xsk_socket_info *xsk_socket;
static int xsk_map_fd;
static int packet_buffer_size;
static void *packet_buffer;
//static struct xdp_program *prog;
#endif

/* General Server variables */
static int groovyServer = 0;
static int sockfd;
static struct sockaddr_in servaddr;
static struct sockaddr_in clientaddr;
static socklen_t clilen = sizeof(struct sockaddr);
static char recvbuf[65536] = { 0 };
static char sendbuf[55] = { 0 };

static int sockfdInputs;
static struct sockaddr_in servaddrInputs;
static struct sockaddr_in clientaddrInputs;
static char sendbufInputs[83] = { 0 };

static int sockfdGMC;
static struct sockaddr_in servaddrGMC;
static struct sockaddr_in clientaddrGMC;
static char sendbufGMC[65536] = { 0 };


#ifdef _AF_XDP
static uint32_t ip_check_1 = 0;
static uint32_t ip_check_13 = 0;
static uint32_t inputs_ip_check_9 = 0;
static uint32_t inputs_ip_check_17 = 0;
static uint32_t inputs_ip_check_13 = 0;
static uint32_t inputs_ip_check_25 = 0;
static uint32_t inputs_ip_check_37 = 0;
static uint32_t inputs_ip_check_41 = 0;

static uint32_t udp_check_1 = 0;
static uint32_t udp_check_13 = 0;
static uint32_t inputs_udp_check_9 = 0;
static uint32_t inputs_udp_check_17 = 0;
static uint32_t inputs_udp_check_13 = 0;
static uint32_t inputs_udp_check_25 = 0;
static uint32_t inputs_udp_check_37 = 0;
static uint32_t inputs_udp_check_41 = 0;
#endif

/* Logo */
static int groovyLogo = 0;
static int logoX = 0;
static int logoY = 0;
static int logoSignX = 0;
static int logoSignY = 0;
static unsigned long logoTime = 0;

static PoC_type *poc;
static uint8_t *map = 0;
static uint8_t* buffer;

static int blitCompression = 0;
static uint8_t codecMode = 0;   // 0=raw 1=LZ4 2=NLC (from CMD_INIT byte[1] bits [1:0])
static uint8_t nlcNear   = 0;   // NLC NEAR level (bits [3:2])
static uint8_t nlcColor  = 1;   // NLC colour: 1=YCoCg (bit [4])
static uint8_t nlcDispMode = 0; // NLC display path: 0=streaming, 2=autonomous engine (bits [6:5])
static uint8_t nlcPack   = 0;   // R3: NLC entropy pack: 1=Golomb-Rice, 0=TILED (CMD_INIT byte[1] bit 7)
static uint8_t audioRate = 0;
static uint8_t audioChannels = 0;
static uint8_t rgbMode = 0;

static int isBlitting = 0;
static int isCorePriority = 0;
static int usingOldBlit = 0;

static uint8_t hpsBlit = 0;
static uint16_t numBlit = 0;

// ---- ingest receive modes ---------------------------------------------------------------------
// The blit hot path historically recvfrom()'d payloads directly into the /dev/mem DDR window,
// which is Device-uncached because shmem.cpp opens /dev/mem O_SYNC. The kernel's copy into
// non-bufferable memory is the measured ~38 MB/s ingest ceiling; at 527KB average frames that
// works out to about 54 fps.
// GROOVY_RECV_MODE env or /media/fat/groovy_recv.cfg (single digit) selects at start:
//   0 = legacy direct recvfrom into the DDR window (A/B baseline)
//   1 = recvfrom into cached scratch + wide-store copy to the window (protocol-identical)
//   2 = recvmmsg batch (up to RECV_BATCH dgrams/syscall) + wide-store copy + ONE FPGA blit
//       notify per batch instead of per chunk. Watermark growth is coarser, which is safe
//       because the engine promotes and finalizes on its own invariant; end-of-frame notify
//       is unchanged.
#define RECV_BATCH 32
static int recvMode = 1;
static uint8_t recvNotifyDefer = 0;              // mode 2 batch loop defers per-chunk ASAP notifies
#ifdef MSG_WAITFORONE
static struct mmsghdr recvMsgs[RECV_BATCH];
static struct iovec recvIovs[RECV_BATCH];
static struct sockaddr_in recvAddrs[RECV_BATCH];
static char recvBatchBuf[RECV_BATCH][2048] __attribute__((aligned(64)));
static uint8_t recvBatchReady = 0;
#endif

// Wide-store copy into the uncached window: on Device memory every store is its own bus beat,
// so store WIDTH is everything (the kernel's alignment-safe path degrades to narrow copies).
// All blit destinations are 8-aligned (HEADER_OFFSET=248, zone offsets 0x...000, 1472-byte
// chunks), so the fast path always hits; anything else falls back to memcpy (already proven
// against this window by the logo and XDP paths).
static void ddr_wide_copy(char *dst, const char *src, int len)
{
	if (((((uintptr_t)dst) | ((uintptr_t)src)) & 7) == 0)
	{
		uint64_t *d = (uint64_t *)dst;
		const uint64_t *s = (const uint64_t *)src;
		while (len >= 64)
		{
			d[0]=s[0]; d[1]=s[1]; d[2]=s[2]; d[3]=s[3];
			d[4]=s[4]; d[5]=s[5]; d[6]=s[6]; d[7]=s[7];
			d += 8; s += 8; len -= 64;
		}
		while (len >= 8) { *d++ = *s++; len -= 8; }
		dst = (char *)d; src = (const char *)s;
	}
	if (len > 0) memcpy(dst, src, len);
}
static uint8_t doScreensaver = 0;
static uint8_t doPs2Inputs = 0;
static uint8_t doJoyInputs = 0;
// CMD_INIT byte[5] capability flags from the client (len-6 init; 0 = older client)
#define CAP_INPUTS_V2 0x01  // 32-bit button masks + analog triggers in the joystick packet
#define CAP_RUMBLE    0x02  // client may send rumble messages on the inputs socket
// Only a client that promises keepalives may be reaped on silence. Absent the bit the
// session is left alone, which is stock Groovy's behaviour, so this is safe by default:
// a client that never opts in can pause indefinitely. The shortest OSD idle timeout is the
// floor such a client must beat (idleSecs below); do not add a shorter option without
// versioning this bit.
#define CAP_KEEPALIVE 0x04  // client sends CMD_GET_STATUS keepalives while idle
static uint8_t clientCaps = 0;
static uint8_t staleCmdLogged = 0;   // one [STALE_CMD] line per closed-session run
static uint8_t doJumboFrames = 0;
#ifdef _AF_XDP
static uint8_t doXDPServer = 1;
#else        
static uint8_t doXDPServer = 0;
#endif
static uint8_t doARMClock = 0;
static uint8_t isConnected = 0;
static uint8_t isConnectedInputs = 0;
static uint8_t isConnectedGMC = 0;
// Idle-timeout state (see IDLE_TIMEOUT_OPT). idleTimeoutMs 0 = disabled. sawActivity is set on
// every received datagram (a single byte store, no clock read, to keep the blit hot-path free);
// the deadline is refreshed / checked once per poll in groovy_poll()'s housekeeping.
static uint32_t idleTimeoutMs = 0;
static unsigned long idleDeadline = 0;
static uint8_t sawActivity = 0;


/* FPGA HPS EXT STATUS */
static uint16_t fpga_vga_vcount = 0;
static uint32_t fpga_vga_frame = 0;
static uint32_t fpga_vram_pixels = 0;
static uint32_t fpga_vram_queue = 0;
static uint8_t  fpga_vram_end_frame = 0;
static uint8_t  fpga_vram_ready = 0;
static uint8_t  fpga_vram_synced = 0;
static uint8_t  fpga_vga_frameskip = 0;
static uint8_t  fpga_vga_vblank = 0;
static uint8_t  fpga_vga_f1 = 0;
static uint8_t  fpga_audio = 0;
static uint8_t  fpga_init = 0;
static uint32_t fpga_lz4_uncompressed = 0;

/* DEBUG */
/*
static uint32_t fpga_lz4_writed = 0;
static uint8_t  fpga_lz4_state = 0;
static uint8_t  fpga_lz4_run = 0;
static uint8_t  fpga_lz4_resume = 0;
static uint8_t  fpga_lz4_test1 = 0;
static uint8_t  fpga_lz4_test2 = 0;
static uint8_t  fpga_lz4_stop= 0;
static uint8_t  fpga_lz4_ABCD = 0;
static uint8_t  fpga_lz4_cmd_fskip = 0;
static uint32_t fpga_lz4_compressed = 0;
static uint32_t fpga_lz4_gravats = 0;
static uint32_t fpga_lz4_llegits = 0;
static uint32_t fpga_lz4_subframe_bytes = 0;
static uint16_t fpga_lz4_subframe_blit = 0;
*/

// Wedge telemetry (GET_GROOVY_STATUS words 10-13)
// word10 (live_a): [7:0] blit FSM state, [11:8] NLC engine state, [13:12] ddr_mux2 grant
//                  (0=M0 1=PEND 2=M1 3=DRAIN), [15:14] ddram state
// word11 (live_b): [0] ddram read_req, [1] eng busy, [2] eng pend_valid, [3] freeze latched,
//                  [7:4] engine wd_fired count (sat), [11:8] ddram read-watchdog count (sat),
//                  [15:12] engine done_stb ROLLING count (publish rate: should tick ~1/poll)
// word12: freeze latched ? freeze-time copy of word10 : engine cur_frame[15:0]
// word13: freeze latched ? {vga_frame[11:0], audio, pend, busy, read_req} at the freeze
//                        : {sync-loss count[7:0], engine FB flushed_bytes[11:4]}
// word14: longest starved-pixel run of the session (the red run length on screen)
static uint16_t fpga_dbg_live_a = 0;
static uint16_t fpga_dbg_live_b = 0;
static uint16_t fpga_dbg_frz_a = 0;   // word12
static uint16_t fpga_dbg_frz_b = 0;   // word13
static uint16_t fpga_dbg_w14 = 0;     // word14
static uint8_t  dbgFreezeLogged = 0;

// Sync-loss watch. The core counts VRAM underruns (Groovy.sv dbg_syncloss_cnt, word13[15:12]
// while no freeze is latched) and ddram read-watchdog fires (word11[11:8]), but the per-blit
// vramSynced bit cannot see either: the condition self-clears within about one raster line, so a
// once-per-frame sample almost always lands outside it. Sample the DBG words every blit and print
// only when a counter moves. Steady state then costs no file I/O, which matters because per-blit
// logging is itself HPS traffic inside the window being measured.
static uint8_t  dbgSyncLossPrev = 0xff;   // 0xff = not yet primed
static uint8_t  dbgDdrWdPrev = 0xff;
static double   lastIngestMs = 0.0;       // previous frame's header-to-last-byte ingest
static uint32_t lastIngestBytes = 0;

// Housekeeping-gap probe. groovy_poll spins on the receive loop for a whole frame's ingest
// (the isCorePriority do/while) and only then returns to the MiSTer main loop, so every deferred
// piece of work lands in one burst right after the last payload byte. HPS and FPGA reach DDR
// through the same hard memory controller, so that burst competes with the display refill, which
// itself runs on about one raster line of slack. This measures the gap between leaving
// groovy_poll and re-entering it, and where the raster was when it ended.
static struct timespec pollExitTS = {0, 0};
static double  hkGapMaxMs = 0.0;
static unsigned long hkDumpTime = 0;
// Every gap is bucketed and the distribution dumped periodically. Reporting new maxima alone is
// not enough: one early spike raises the bar for the rest of the session, and a quiet window then
// looks the same as a window where the probe stopped reporting.
#define HK_BUCKETS  8
#define HK_DUMP_MS  10000
static uint32_t hkBucket[HK_BUCKETS] = {0};
static uint16_t hkMaxVc = 0;   // raster line when the worst gap ended

static inline int hk_bucket(double ms)
{
	if (ms < 0.05) return 0;
	if (ms < 0.10) return 1;
	if (ms < 0.20) return 2;
	if (ms < 0.50) return 3;
	if (ms < 1.00) return 4;
	if (ms < 2.00) return 5;
	if (ms < 5.00) return 6;
	return 7;
}



static inline void initDDR()
{
	memset(&buffer[0],0x00,0xff);
}


static void openVerboseFile(uint8_t sessionStart)
{
	// Only a session start may truncate. Every other caller is idempotent and can never discard a
	// capture mid-run: that covers server start, and the probes, which open the file themselves so
	// they still work with Verbose off. In append mode nothing truncates after the first open,
	// giving the old behaviour of one file per boot that survives reconnects.
	if (fp)
	{
		if (!sessionStart || logAppend) return;
		fclose(fp);
		fp = NULL;
	}
	fp = fopen(GROOVY_LOG_PATH, "wt");
	if (!fp)
	{
		// Must not LOG() here - LOG writes to fp, and every path below this point
		// (fstat(fileno(fp)), setvbuf) would dereference NULL too.
		printf("%s open error: %s\n", GROOVY_LOG_PATH, strerror(errno));
		return;
	}
	struct stat stats;
    	if (fstat(fileno(fp), &stats) == -1)
    	{
        	LOG(0, "groovy.log stats %s\n", "error");
    	}
    	if (setvbuf(fp, NULL, _IOFBF, stats.st_blksize) != 0)
    	{
        	LOG(0, "setvbuf failed %s \n", "error");
    	}
    	logTime = GetTimer(1000);

}

static void groovy_FPGA_hps()
{	                   
    doVerbose = (uint8_t) user_io_status_get(VERBOSE_OPT);        
    openVerboseFile(0);
    
    hpsBlit = (uint8_t) user_io_status_get(BLIT_OPT); 
    doScreensaver = (uint8_t) !user_io_status_get(SCREENSAVER_OPT); 
    doPs2Inputs = (uint8_t) user_io_status_get(PS2_INPUTS_OPT);  
    doJoyInputs = (uint8_t) user_io_status_get(JOY_INPUTS_OPT);      
    doJumboFrames = (uint8_t) user_io_status_get(JUMBO_FRAMES_OPT);
    doARMClock = (uint8_t) user_io_status_get(ARM_CLOCK_OPT);

    static const uint16_t idleSecs[4] = {5, 10, 15, 0};   // OSD order: 5s,10s,15s,Off (index 3 -> disabled)
    idleTimeoutMs = (uint32_t) idleSecs[user_io_status_get(IDLE_TIMEOUT_OPT) & 3] * 1000u;

    LOG(0, "[HPS][doVerbose=%d hpsBlit=%d doScreenSaver=%d doPs2Inputs=%d doJoyInputs=%d doJumboFrames=%d doXDPServer=%d doARMClock=%d idleTimeoutMs=%u]\n", doVerbose, hpsBlit, doScreensaver, doPs2Inputs, doJoyInputs, doJumboFrames, doXDPServer, doARMClock, idleTimeoutMs);
    
    user_io_status_set(AUDIO_RATE_OPT, (uint32_t)0);
    user_io_status_set(AUDIO_CHANNELS_OPT, (uint32_t)0);
    user_io_status_set(RGB_MODE_OPT, (uint32_t)0);
    user_io_status_set(LZ4_OPT, (uint32_t)0);
}

static void groovy_FPGA_status(uint8_t isACK)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_GET_GROOVY_STATUS);
    } while (req == 0);

    fpga_vga_frame   = spi_w(0) | spi_w(0) << 16;
    fpga_vga_vcount  = spi_w(0);
    uint16_t word16  = spi_w(0);
    uint8_t word8_l  = (uint8_t)(word16 & 0x00FF);

    bitByte bits;
    bits.byte = word8_l;
    fpga_vram_ready     = bits.u.bit0;
    fpga_vram_end_frame = bits.u.bit1;
    fpga_vram_synced    = bits.u.bit2;
    fpga_vga_frameskip  = bits.u.bit3;
    fpga_vga_vblank     = bits.u.bit4;
    fpga_vga_f1         = bits.u.bit5;
    fpga_audio          = bits.u.bit6;
    fpga_init           = bits.u.bit7;

    uint8_t word8_h = (uint8_t)((word16 & 0xFF00) >> 8);
    fpga_vram_queue = word8_h; // 8b

    if (fpga_vga_vcount <= poc->PoC_interlaced) //end line
    {
	if (poc->PoC_interlaced)
	{
		if (!fpga_vga_vcount) //based on field
		{
			fpga_vga_vcount = (fpga_vga_vblank) ? poc->PoC_V_Total : 1;
		}
		else
		{
			fpga_vga_vcount = (fpga_vga_vblank) ? poc->PoC_V_Total - 1 : 2;
		}
	}
	else
	{
		fpga_vga_vcount = (fpga_vga_vblank) ? poc->PoC_V_Total : 1;
	}
    }

    if (!isACK)
    {
    	fpga_vram_queue |= spi_w(0) << 8; //24b
    	fpga_vram_pixels = spi_w(0) | spi_w(0) << 16;

	if (blitCompression || doVerbose == 3)
	{
		fpga_lz4_uncompressed  = spi_w(0) | spi_w(0) << 16;

		// wedge telemetry (must mirror hps_ext.v words 10-13 exactly)
		fpga_dbg_live_a = spi_w(0);
		fpga_dbg_live_b = spi_w(0);
		fpga_dbg_frz_a  = spi_w(0);
		fpga_dbg_frz_b  = spi_w(0);
		fpga_dbg_w14    = spi_w(0);

		if ((fpga_dbg_live_b & 0x0008) && !dbgFreezeLogged)
		{
			dbgFreezeLogged = 1;
			LOG(0, "[FREEZE_LATCH][fsm=%u eng=%u grant=%u ddram=%u rdreq=%u][eng_busy=%u pend=%u audio=%u vf=%u][live a=%04x b=%04x]\n",
				fpga_dbg_frz_a & 0xff, (fpga_dbg_frz_a >> 8) & 0xf, (fpga_dbg_frz_a >> 12) & 0x3, (fpga_dbg_frz_a >> 14) & 0x3,
				fpga_dbg_frz_b & 0x1, (fpga_dbg_frz_b >> 1) & 0x1, (fpga_dbg_frz_b >> 2) & 0x1, (fpga_dbg_frz_b >> 3) & 0x1,
				(fpga_dbg_frz_b >> 4) & 0xfff, fpga_dbg_live_a, fpga_dbg_live_b);
		}
	}

		// DEBUG 
		/*
			fpga_lz4_state = spi_w(0);
			fpga_lz4_writed = spi_w(0) | spi_w(0) << 16;

			uint16_t wordlz4 = spi_w(0);

			bits.byte = (uint8_t) wordlz4;
			fpga_lz4_cmd_fskip = bits.u.bit7;
			fpga_lz4_ABCD = (bits.u.bit5 == 0 && bits.u.bit6 == 0) ? 0 : (bits.u.bit5 == 1 && bits.u.bit6 == 0) ? 1 : (bits.u.bit5 == 0 && bits.u.bit6 == 1) ? 2 : 3;
			fpga_lz4_stop = bits.u.bit4;
			fpga_lz4_test2 = bits.u.bit3;
			fpga_lz4_test1 = bits.u.bit2;
			fpga_lz4_resume = bits.u.bit1;
                	fpga_lz4_run = bits.u.bit0;

			fpga_lz4_compressed =  spi_w(0) | spi_w(0) << 16;
			fpga_lz4_gravats = spi_w(0) | spi_w(0) << 16;
			fpga_lz4_llegits = spi_w(0) | spi_w(0) << 16;
			fpga_lz4_subframe_bytes = spi_w(0) | spi_w(0) << 16;
			fpga_lz4_subframe_blit = spi_w(0);
		*/	
	       
    }
    DisableIO();
}

static void groovy_FPGA_switchres()
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_SET_GROOVY_SWITCHRES);
    } while (req == 0);   
    spi_w((uint16_t) poc->PoC_frame_ddr);
    spi_w((uint16_t) (poc->PoC_frame_ddr >> 16));
    DisableIO();
}

static void groovy_FPGA_blit()
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_SET_GROOVY_BLIT);
    } while (req == 0);
    spi_w(1);
    DisableIO();
}

static void groovy_FPGA_blit_field_lz4(uint32_t compressed_bytes, uint16_t field, uint8_t delta_frame)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
 	req = fpga_spi_fast(UIO_SET_GROOVY_BLIT_FIELD_LZ4);
    } while (req == 0);
    bitByte bits;   
    uint8_t lz4_zone = (poc->PoC_field_lz4 == 0) ? 3 : poc->PoC_field_lz4 - 1;   
    bits.byte = lz4_zone;
    bits.u.bit2 = (field == 1) ? 1 : 0;
    bits.u.bit3 = (field == 2) ? 1 : 0;
    bits.u.bit4 = delta_frame;
    spi_w((uint16_t) bits.byte);
    spi_w((uint16_t) compressed_bytes);
    spi_w((uint16_t) (compressed_bytes >> 16));  
    DisableIO();
}

static void groovy_FPGA_init(uint8_t cmd, uint8_t audio_rate, uint8_t audio_chan, uint8_t rgb_mode)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_SET_GROOVY_INIT);
    } while (req == 0);
    // cmd word = hps_ext SET_INIT m_temp: [0]=init, [2:1]=codec_mode, [4:3]=nlc_near, [5]=nlc_color.
    uint16_t cmd_word = cmd;
    if (cmd == 1) {
        cmd_word |= (uint16_t)(codecMode & 0x3) << 1;
        cmd_word |= (uint16_t)(nlcNear   & 0x3) << 3;
        cmd_word |= (uint16_t)(nlcColor  & 0x1) << 5;
        cmd_word |= (uint16_t)(nlcDispMode & 0x3) << 6;   // hps_ext decodes m_temp[7:6] = nlc_disp_mode
        cmd_word |= (uint16_t)(nlcPack   & 0x1) << 8;     // hps_ext m_temp[8] = nlc_rice (Golomb-Rice pack)
    }
    spi_w(cmd_word);
    bitByte bits;
    bits.byte = audio_rate;
    bits.u.bit2 = (audio_chan == 1) ? 1 : 0;
    bits.u.bit3 = (audio_chan == 2) ? 1 : 0;
    bits.u.bit4 = (rgb_mode == 1) ? 1 : 0;
    bits.u.bit5 = (rgb_mode == 2) ? 1 : 0;
    spi_w((uint16_t) bits.byte);
    DisableIO();
}

static void groovy_FPGA_logo(uint8_t cmd)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_SET_GROOVY_LOGO);
    } while (req == 0);
    spi_w(cmd);
    DisableIO();
}

static void groovy_FPGA_audio(uint16_t samples)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_SET_GROOVY_AUDIO);
    } while (req == 0);
    spi_w(samples);
    DisableIO();
}

static void loadLogo(int logoStart)
{
	if (!doScreensaver)
	{
		return;
	}

	if (logoStart)
	{
		do
		{
			groovy_FPGA_status(0);
		}  while (fpga_init != 0);


		buffer[0] = (1) & 0xff;
	 	buffer[1] = (1 >> 8) & 0xff;
	     	buffer[2] = (1 >> 16) & 0xff;
	  	buffer[3] = (61440) & 0xff;
	   	buffer[4] = (61440 >> 8) & 0xff;
	 	buffer[5] = (61440 >> 16) & 0xff;
		buffer[6] = (1) & 0xff;
		buffer[7] = (1 >> 8) & 0xff;

		logoTime = GetTimer(LOGO_TIMER);
	}

	if (CheckTimer(logoTime))
	{
		groovy_FPGA_status(0);
		if (fpga_vga_vcount == 241)
		{
			memset(&buffer[HEADER_OFFSET], 0x00, 184320);
		       	int z=0;
		       	int offset = (256 * logoY * 3) + (logoX * 3);
		       	for (int i=0; i<64; i++)
		       	{
		       		memcpy(&buffer[HEADER_OFFSET+offset], (char*)&logoImage[z], 192);
		       		offset += 256 * 3;
		       		z += 64 * 3;
		       	}
		       	logoTime = GetTimer(LOGO_TIMER);

		       	logoX = (logoSignX) ? logoX - 1 : logoX + 1;
		       	logoY = (logoSignY) ? logoY - 2 : logoY + 2;

		       	if (logoX >= 192 && !logoSignX)
		       	{
		       		logoSignX = !logoSignX;
		       	}

		       	if (logoY >= 176 && !logoSignY)
		       	{
		       		logoSignY = !logoSignY;
		       	}

		       	if (logoX <= 0 && logoSignX)
		       	{
		       		logoSignX = !logoSignX;
		       	}

		       	if (logoY <= 0 && logoSignY)
		       	{
		       		logoSignY = !logoSignY;
		       	}
		}
	}
}

static void groovy_FPGA_blit(uint32_t bytes, uint16_t numBlit)
{
    poc->PoC_pixels_ddr = (rgbMode == 1) ? bytes >> 2 : (rgbMode == 2) ? bytes >> 1 : bytes / 3;

    buffer[3] = (poc->PoC_pixels_ddr) & 0xff;
    buffer[4] = (poc->PoC_pixels_ddr >> 8) & 0xff;
    buffer[5] = (poc->PoC_pixels_ddr >> 16) & 0xff;

    buffer[6] = (numBlit) & 0xff;
    buffer[7] = (numBlit >> 8) & 0xff;
       
    if (poc->PoC_frame_ddr != poc->PoC_frame_recv)
    {
    	poc->PoC_frame_ddr  = poc->PoC_frame_recv;

    	buffer[0] = (poc->PoC_frame_ddr) & 0xff;
    	buffer[1] = (poc->PoC_frame_ddr >> 8) & 0xff;
    	buffer[2] = (poc->PoC_frame_ddr >> 16) & 0xff;

    	groovy_FPGA_blit();    	
    }
}

static void groovy_FPGA_blit_lz4(uint32_t bytes, uint16_t numBlit)
{
    poc->PoC_bytes_lz4_ddr = bytes;
    buffer[35] = (poc->PoC_bytes_lz4_ddr) & 0xff;
    buffer[36] = (poc->PoC_bytes_lz4_ddr >> 8) & 0xff;
    buffer[37] = (poc->PoC_bytes_lz4_ddr >> 16) & 0xff;

    buffer[38] = (numBlit) & 0xff;
    buffer[39] = (numBlit >> 8) & 0xff;

    if (poc->PoC_frame_ddr != poc->PoC_frame_recv)
    {
    	poc->PoC_frame_ddr  = poc->PoC_frame_recv;

    	buffer[32] = (poc->PoC_frame_ddr) & 0xff;
    	buffer[33] = (poc->PoC_frame_ddr >> 8) & 0xff;
    	buffer[34] = (poc->PoC_frame_ddr >> 16) & 0xff;

    	groovy_FPGA_blit_field_lz4(poc->PoC_bytes_lz4_len, poc->PoC_field, poc->PoC_delta_lz4);    
    }

}

static void setSwitchres(char *recvbuf)
{
    //modeline
    uint64_t udp_pclock_bits;
    uint16_t udp_hactive;
    uint16_t udp_hbegin;
    uint16_t udp_hend;
    uint16_t udp_htotal;
    uint16_t udp_vactive;
    uint16_t udp_vbegin;
    uint16_t udp_vend;
    uint16_t udp_vtotal;
    uint8_t  udp_interlace;

    memcpy(&udp_pclock_bits,&recvbuf[1],8);
    memcpy(&udp_hactive,&recvbuf[9],2);
    memcpy(&udp_hbegin,&recvbuf[11],2);
    memcpy(&udp_hend,&recvbuf[13],2);
    memcpy(&udp_htotal,&recvbuf[15],2);
    memcpy(&udp_vactive,&recvbuf[17],2);
    memcpy(&udp_vbegin,&recvbuf[19],2);
    memcpy(&udp_vend,&recvbuf[21],2);
    memcpy(&udp_vtotal,&recvbuf[23],2);
    memcpy(&udp_interlace,&recvbuf[25],1);

    u.i = udp_pclock_bits;
    double udp_pclock = u.d;

    poc->PoC_width_time = (double) udp_htotal * (1 / (udp_pclock * 1000)); //in ms, time to raster 1 line
    poc->PoC_V_Total = udp_vtotal;    

    poc->PoC_pixels_ddr = 0;
    poc->PoC_H = udp_hactive;
    poc->PoC_HFP = udp_hbegin - udp_hactive;
    poc->PoC_HS = udp_hend - udp_hbegin;
    poc->PoC_HBP = udp_htotal - udp_hend;
    poc->PoC_V = udp_vactive;
    poc->PoC_VFP = udp_vbegin - udp_vactive;
    poc->PoC_VS = udp_vend - udp_vbegin;
    poc->PoC_VBP = udp_vtotal - udp_vend;
    
    // ce_pix chooser: clk_sys = pclock * ce_pix. clk_sys is bounded to ~83MHz because the FPGA's timing is
    // analyzed at the PLL's configured 82.75MHz, the runtime PLL reconfig being invisible to STA. The old
    // unbounded ladder produced 100.7MHz at 25.175MHz (31kHz 480p), a 22% overclock that gave no sync at all,
    // and 87.9MHz at 14.655MHz (480i).
    // Keep >=40MHz for the vga scaler; the NLC decoder needs >= ~2.1*pclock (ce_pix>=3 always satisfies it).
    poc->PoC_ce_pix = (udp_pclock * 16 < 84) ? 16 : (udp_pclock * 12 < 84) ? 12 : (udp_pclock * 8 < 84) ? 8 : (udp_pclock * 6 < 84) ? 6 : (udp_pclock * 4 < 84) ? 4 : (udp_pclock * 3 < 84) ? 3 : 2;
    poc->PoC_interlaced = (udp_interlace >= 1) ? 1 : 0;
    poc->PoC_FB_progressive = (udp_interlace == 0 || udp_interlace == 2) ? 1 : 0;
    
    if (usingOldBlit && !poc->PoC_FB_progressive) //old blit depends match field if fskip is activated
    {
    	groovy_FPGA_status(1);
    	poc->PoC_field_frame = poc->PoC_frame_ddr >= fpga_vga_frame ? poc->PoC_frame_ddr + 1 : fpga_vga_frame + 1;
    }
    else
    {
    	poc->PoC_field_frame = poc->PoC_frame_ddr + 1;
    }
    
    poc->PoC_field = 0;

    int M=0;
    int C=0;
    int K=0;
       
    getMCK_PLL_Fractional(udp_pclock * poc->PoC_ce_pix, M, C, K);
    poc->PoC_pll_M0 = (M % 2 == 0) ? M >> 1 : (M >> 1) + 1;
    poc->PoC_pll_M1 = M >> 1;
    poc->PoC_pll_C0 = (C % 2 == 0) ? C >> 1 : (C >> 1) + 1;
    poc->PoC_pll_C1 = C >> 1;
    poc->PoC_pll_K = K;    
    
    poc->PoC_pixels_len = poc->PoC_H * poc->PoC_V;

    if (poc->PoC_interlaced && !poc->PoC_FB_progressive)
    {
    	poc->PoC_pixels_len = poc->PoC_pixels_len >> 1;
    }

    poc->PoC_bytes_len = (rgbMode == 1) ? poc->PoC_pixels_len << 2 : (rgbMode == 2) ? poc->PoC_pixels_len << 1 : poc->PoC_pixels_len * 3;
    poc->PoC_bytes_recv = 0;
    poc->PoC_buffer_offset = 0;
    
    LOG(1,"[MODELINE][%f %d %d %d %d %d %d %d %d %s(%d)][FPGA %d %d %d %d %d %d %d %d]\n",udp_pclock,udp_hactive,udp_hbegin,udp_hend,udp_htotal,udp_vactive,udp_vbegin,udp_vend,udp_vtotal,udp_interlace?"interlace":"progressive",udp_interlace, poc->PoC_H,poc->PoC_HFP, poc->PoC_HS,poc->PoC_HBP,poc->PoC_V,poc->PoC_VFP, poc->PoC_VS,poc->PoC_VBP);
    LOG(1,"[PLL][ce_pix=%d M0=%d M1=%d C0=%d C1=%d K=%d]\n", poc->PoC_ce_pix,poc->PoC_pll_M0,poc->PoC_pll_M1,poc->PoC_pll_C0,poc->PoC_pll_C1,poc->PoC_pll_K);    
     
    //clean pixels on ddr (auto_blit)
    buffer[4] = 0x00;
    buffer[5] = 0x00;
    buffer[6] = 0x00;
    buffer[7] = 0x00;

    //modeline + pll -> burst 3
    buffer[8]  =  poc->PoC_H & 0xff;
    buffer[9]  = (poc->PoC_H >> 8);
    buffer[10] =  poc->PoC_HFP;
    buffer[11] =  poc->PoC_HS;
    buffer[12] =  poc->PoC_HBP;
    buffer[13] =  poc->PoC_V & 0xff;
    buffer[14] = (poc->PoC_V >> 8);
    buffer[15] =  poc->PoC_VFP;
    buffer[16] =  poc->PoC_VS;
    buffer[17] =  poc->PoC_VBP;

    //pll
    buffer[18] =  poc->PoC_pll_M0;
    buffer[19] =  poc->PoC_pll_M1;
    buffer[20] =  poc->PoC_pll_C0;
    buffer[21] =  poc->PoC_pll_C1;
    buffer[22] = (poc->PoC_pll_K) & 0xff;
    buffer[23] = (poc->PoC_pll_K >> 8) & 0xff;
    buffer[24] = (poc->PoC_pll_K >> 16) & 0xff;
    buffer[25] = (poc->PoC_pll_K >> 24) & 0xff;
    buffer[26] =  poc->PoC_ce_pix;
    buffer[27] =  udp_interlace;

    groovy_FPGA_switchres();
}


static void setClose()
{
	groovy_FPGA_init(0, 0, 0, 0);
	isBlitting = 0;
	isCorePriority = 0;   // defensive: a mid-blit caller (idle timeout) leaves this 1; the poll loop would spin
	usingOldBlit = 0;
	numBlit = 0;
	blitCompression = 0;
	// poc is NOT freed here. It is allocated once in groovy_map_ddr() and lives for the process.
	// Freeing it left a dangling pointer that the logo path (loadLogo -> groovy_FPGA_status) and
	// every late packet from a client that had not noticed the close went on dereferencing - which
	// is how a torn-down session's frames ended up written over the logo framebuffer. Zeroing also
	// clears PoC_bytes_len, so any stray payload takes the "no modeline" path instead of blitting.
	memset(poc, 0, sizeof(PoC_type));
	staleCmdLogged = 0;   // arm the one-shot stale-command log for this closed period
	initDDR();
	isConnected = 0;
	isConnectedInputs = 0;
	clientCaps = 0;
	// halt any active rumble effect (uploaded effects run for up to 32s)
	input_rumble_player(1, 0);
	input_rumble_player(2, 0);

	// load LOGO
	if (doScreensaver)
	{
		loadLogo(1);
		groovy_FPGA_init(1, 0, 0, 0);
		groovy_FPGA_blit();
		groovy_FPGA_logo(1);
		groovyLogo = 1;
	}
	
	user_io_status_set(AUDIO_RATE_OPT, (uint32_t)0);
 	user_io_status_set(AUDIO_CHANNELS_OPT, (uint32_t)0);
 	user_io_status_set(RGB_MODE_OPT, (uint32_t)0);
 	user_io_status_set(LZ4_OPT, (uint32_t)0); 	
}

#ifdef _AF_XDP
static void complete_tx(struct xsk_socket_info *xsk)
{
	unsigned int completed;
	uint32_t idx_cq;

	if (!xsk->outstanding_tx)
		return;

  	//if (xsk_ring_prod__needs_wakeup(&xsk->tx))
  	{
		sendto(sockfd, NULL, 0, MSG_DONTWAIT, NULL, 0);
	}

	// Try to free n (batch_size) frames on the completetion ring.
	completed = xsk_ring_cons__peek(&xsk->umem->cq, 1, &idx_cq);

	if (completed > 0)
	{
		xsk_ring_cons__release(&xsk->umem->cq, completed);
		xsk->outstanding_tx -= completed;
	}
}
#endif

static void groovy_send_joysticks()
{
	char* sendbufPtr = (doXDPServer) ? (char*) &sendbufInputs[42] : (char*) &sendbufInputs[0];
	int len;
	sendbufPtr[0] = poc->PoC_frame_ddr & 0xff;
	sendbufPtr[1] = poc->PoC_frame_ddr >> 8;
	sendbufPtr[2] = poc->PoC_frame_ddr >> 16;
	sendbufPtr[3] = poc->PoC_frame_ddr >> 24;
	sendbufPtr[4] = poc->PoC_joystick_order;
	if (clientCaps & CAP_INPUTS_V2)
	{
		// v2: 32-bit masks (buttons 16-31 headroom) + analog triggers; len 13/25
		sendbufPtr[5]  = poc->PoC_joystick_map1 & 0xff;
		sendbufPtr[6]  = poc->PoC_joystick_map1 >> 8;
		sendbufPtr[7]  = poc->PoC_joystick_map1 >> 16;
		sendbufPtr[8]  = poc->PoC_joystick_map1 >> 24;
		sendbufPtr[9]  = poc->PoC_joystick_map2 & 0xff;
		sendbufPtr[10] = poc->PoC_joystick_map2 >> 8;
		sendbufPtr[11] = poc->PoC_joystick_map2 >> 16;
		sendbufPtr[12] = poc->PoC_joystick_map2 >> 24;
		len = 13;
		if (doJoyInputs == 2)
		{
			sendbufPtr[13] = poc->PoC_joystick_l_analog_X1;
			sendbufPtr[14] = poc->PoC_joystick_l_analog_Y1;
			sendbufPtr[15] = poc->PoC_joystick_r_analog_X1;
			sendbufPtr[16] = poc->PoC_joystick_r_analog_Y1;
			sendbufPtr[17] = poc->PoC_joystick_l_analog_X2;
			sendbufPtr[18] = poc->PoC_joystick_l_analog_Y2;
			sendbufPtr[19] = poc->PoC_joystick_r_analog_X2;
			sendbufPtr[20] = poc->PoC_joystick_r_analog_Y2;
			sendbufPtr[21] = poc->PoC_joystick_l_trigger1;
			sendbufPtr[22] = poc->PoC_joystick_r_trigger1;
			sendbufPtr[23] = poc->PoC_joystick_l_trigger2;
			sendbufPtr[24] = poc->PoC_joystick_r_trigger2;
			len = 25;
		}
	}
	else
	{
		len = 9;
		sendbufPtr[5] = poc->PoC_joystick_map1 & 0xff;
		sendbufPtr[6] = poc->PoC_joystick_map1 >> 8;
		sendbufPtr[7] = poc->PoC_joystick_map2 & 0xff;
		sendbufPtr[8] = poc->PoC_joystick_map2 >> 8;
		if (doJoyInputs == 2)
		{
			sendbufPtr[9]  = poc->PoC_joystick_l_analog_X1;
			sendbufPtr[10] = poc->PoC_joystick_l_analog_Y1;
			sendbufPtr[11] = poc->PoC_joystick_r_analog_X1;
			sendbufPtr[12] = poc->PoC_joystick_r_analog_Y1;
			sendbufPtr[13] = poc->PoC_joystick_l_analog_X2;
			sendbufPtr[14] = poc->PoC_joystick_l_analog_Y2;
			sendbufPtr[15] = poc->PoC_joystick_r_analog_X2;
			sendbufPtr[16] = poc->PoC_joystick_r_analog_Y2;
			len += 8;
		}
	}
	poc->PoC_joystick_keep_alive = 0;
	if (!doXDPServer)
	{
		sendto(sockfdInputs, sendbufPtr, len, MSG_CONFIRM, (struct sockaddr *)&clientaddrInputs, clilen);
	}
#ifdef _AF_XDP
	else
	{
		//struct ethhdr *eth = (struct ethhdr *)(sendbufInputs);
		struct iphdr *iph = (struct iphdr *)(sendbufInputs + sizeof(struct ethhdr));
		struct udphdr *udph = (struct udphdr *)(sendbufInputs + sizeof(struct ethhdr) + (iph->ihl * 4));
		int ret = 0;
		uint32_t tx_idx = 0;
		uint64_t addr = 0;
		ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
		if (ret != 1) {
			// No more transmit slots, drop the packet
			LOG(0, "[ACK_%s][Failed]\n", "STATUS");
			return;
		}
		udph->len = htons(len + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + len);
		if (len == 9)
		{
			iph->check = inputs_ip_check_9;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_9);	
		}
		else if (len == 13)
		{
			iph->check = inputs_ip_check_13;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_13);
		}
		else if (len == 25)
		{
			iph->check = inputs_ip_check_25;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_25);
		}
		else
		{
			iph->check = inputs_ip_check_17;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_17);
		}		 				
		addr = xsk_socket->umem_frame_addr[xsk_socket->outstanding_tx];
		memcpy(xsk_umem__get_data(xsk_socket->umem->buffer, addr), sendbufInputs, len + 42);
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->addr = addr;
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->len = len + 42;
		xsk_ring_prod__submit(&xsk_socket->tx, 1);
		xsk_socket->outstanding_tx++;

		complete_tx(xsk_socket);
	}
#endif

}

static void groovy_send_ps2()
{
	char* sendbufPtr = (doXDPServer) ? (char*) &sendbufInputs[42] : (char*) &sendbufInputs[0];
	int len = 37;
	sendbufPtr[0] = poc->PoC_frame_ddr & 0xff;
	sendbufPtr[1] = poc->PoC_frame_ddr >> 8;
	sendbufPtr[2] = poc->PoC_frame_ddr >> 16;
	sendbufPtr[3] = poc->PoC_frame_ddr >> 24;
	sendbufPtr[4] = poc->PoC_ps2_order;
	memcpy(&sendbufPtr[5], &poc->PoC_ps2_keyboard_keys, 32);
	if (doPs2Inputs == 2)
	{
		sendbufPtr[37] = poc->PoC_ps2_mouse;
		sendbufPtr[38] = poc->PoC_ps2_mouse_x;
		sendbufPtr[39] = poc->PoC_ps2_mouse_y;
		sendbufPtr[40] = poc->PoC_ps2_mouse_z;
		len += 4;
	}
	poc->PoC_ps2_keep_alive = 0;
	if (!doXDPServer)
	{
		sendto(sockfdInputs, sendbufPtr, len, MSG_CONFIRM, (struct sockaddr *)&clientaddrInputs, clilen);
	}
#ifdef _AF_XDP
	else
	{
		//struct ethhdr *eth = (struct ethhdr *)(sendbufInputs);
		struct iphdr *iph = (struct iphdr *)(sendbufInputs + sizeof(struct ethhdr));
		struct udphdr *udph = (struct udphdr *)(sendbufInputs + sizeof(struct ethhdr) + (iph->ihl * 4));
		int ret = 0;
		uint32_t tx_idx = 0;
		uint64_t addr = 0;
		ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
		if (ret != 1) {
			// No more transmit slots, drop the packet
			LOG(0, "[ACK_%s][Failed]\n", "STATUS");
			return;
		}
		udph->len = htons(len + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + len);
		if (len == 37)
		{
			iph->check = inputs_ip_check_37;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_37);	
		}
		else
		{
			iph->check = inputs_ip_check_41;
			compute_udp_checksum((unsigned short *)udph, inputs_udp_check_41);
		}				
		addr = xsk_socket->umem_frame_addr[xsk_socket->outstanding_tx];
		memcpy(xsk_umem__get_data(xsk_socket->umem->buffer, addr), sendbufInputs, len + 42);
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->addr = addr;
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->len = len + 42;
		xsk_ring_prod__submit(&xsk_socket->tx, 1);
		xsk_socket->outstanding_tx++;

		complete_tx(xsk_socket);
	}
#endif
}

static void sendVersion()
{	
	char* sendbufPtr = (doXDPServer) ? (char*) &sendbuf[42] : (char*) &sendbuf[0];
	int flags = 0;
	flags |= MSG_CONFIRM;	
	sendbufPtr[0] = (uint8_t) GROOVY_VERSION;				
		
	if (!doXDPServer)
	{
		sendto(sockfd, sendbufPtr, 1, flags, (struct sockaddr *)&clientaddr, clilen);
	}
#ifdef _AF_XDP
	else
	{			 								
		//struct ethhdr *eth = (struct ethhdr *)(sendbuf);
		struct iphdr *iph = (struct iphdr *)(sendbuf + sizeof(struct ethhdr));
		struct udphdr *udph = (struct udphdr *)(sendbuf + sizeof(struct ethhdr) + (iph->ihl * 4));
		int ret = 0;
		uint32_t tx_idx = 0;
		uint64_t addr = 0;
		ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
		if (ret != 1) {
			// No more transmit slots, drop the packet
			LOG(0, "[VERSION_%s][Failed]\n", "STATUS");
			return;
		}
		iph->check = ip_check_1;
		udph->len = htons(1 + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 1);
		compute_udp_checksum((unsigned short *)udph, udp_check_1); 		
		addr = xsk_socket->umem_frame_addr[xsk_socket->outstanding_tx];
		memcpy(xsk_umem__get_data(xsk_socket->umem->buffer, addr), sendbuf, 43);
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->addr = addr;
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->len = 43;
		xsk_ring_prod__submit(&xsk_socket->tx, 1);
		xsk_socket->outstanding_tx++;

		complete_tx(xsk_socket);
	}
#endif
}

static void sendACK(uint32_t udp_frame, uint16_t udp_vsync)
{
	LOG(2, "[ACK_%s]\n", "STATUS");

	char* sendbufPtr = (doXDPServer) ? (char*) &sendbuf[42] : (char*) &sendbuf[0];
	int flags = 0;
	flags |= MSG_CONFIRM;
	//echo
	sendbufPtr[0] = udp_frame & 0xff;
	sendbufPtr[1] = udp_frame >> 8;
	sendbufPtr[2] = udp_frame >> 16;
	sendbufPtr[3] = udp_frame >> 24;
	sendbufPtr[4] = udp_vsync & 0xff;
	sendbufPtr[5] = udp_vsync >> 8;
	//gpu
	sendbufPtr[6] = fpga_vga_frame  & 0xff;
	sendbufPtr[7] = fpga_vga_frame  >> 8;
	sendbufPtr[8] = fpga_vga_frame  >> 16;
	sendbufPtr[9] = fpga_vga_frame  >> 24;
	sendbufPtr[10] = fpga_vga_vcount & 0xff;
	sendbufPtr[11] = fpga_vga_vcount >> 8;
	//debug bits
	bitByte bits;
	bits.byte = 0;
	bits.u.bit0 = fpga_vram_ready;
	bits.u.bit1 = fpga_vram_end_frame;
	bits.u.bit2 = fpga_vram_synced;
	bits.u.bit3 = fpga_vga_frameskip;
	bits.u.bit4 = fpga_vga_vblank;
	bits.u.bit5 = fpga_vga_f1;
	bits.u.bit6 = fpga_audio;
	bits.u.bit7 = (fpga_vram_queue > 0) ? 1 : 0;
	sendbufPtr[12] = bits.byte;


	if (!doXDPServer)
	{
		sendto(sockfd, sendbufPtr, 13, flags, (struct sockaddr *)&clientaddr, clilen);
	}
#ifdef _AF_XDP
	else
	{
		//struct ethhdr *eth = (struct ethhdr *)(sendbuf);
		struct iphdr *iph = (struct iphdr *)(sendbuf + sizeof(struct ethhdr));
		struct udphdr *udph = (struct udphdr *)(sendbuf + sizeof(struct ethhdr) + (iph->ihl * 4));
		int ret = 0;
		uint32_t tx_idx = 0;
		uint64_t addr = 0;
		ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
		if (ret != 1) {
			// No more transmit slots, drop the packet
			LOG(0, "[ACK_%s][Failed]\n", "STATUS");
			return;
		}		
		iph->check = ip_check_13;
		udph->len = htons(13 + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 13);		
		compute_udp_checksum((unsigned short *)udph, udp_check_13); 						
		addr = xsk_socket->umem_frame_addr[xsk_socket->outstanding_tx];
		memcpy(xsk_umem__get_data(xsk_socket->umem->buffer, addr), sendbuf, 55);
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->addr = addr;
		xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->len = 55;
		xsk_ring_prod__submit(&xsk_socket->tx, 1);
		xsk_socket->outstanding_tx++;

		complete_tx(xsk_socket);
	}
#endif
	if (poc->PoC_joystick_keep_alive >= KEEP_ALIVE_FRAMES)
	{
		LOG(2, "[JOY_ACK][%s]\n", "KEEP_ALIVE");
		groovy_send_joysticks();
	}

	if (poc->PoC_ps2_keep_alive >= KEEP_ALIVE_FRAMES)
	{
		LOG(2, "[KBD_ACK][%s]\n", "KEEP_ALIVE");
		groovy_send_ps2();
	}
}

static void setInit(uint8_t compression, uint8_t audio_rate, uint8_t audio_chan, uint8_t rgb_mode)
{
	difMs = 0;
	fpga_lz4_uncompressed = 0;
	dbgFreezeLogged = 0;   // re-arm the one-shot FREEZE_LATCH log per session
	// CMD_INIT byte[1] packs codec + NLC params: [1:0]=codec (0=raw,1=LZ4,2=NLC) [3:2]=NEAR [4]=colour(1=YCoCg)
	// [6:5]=dispMode [7]=RICE pack.
	codecMode       = compression & 0x3;
	nlcNear         = (compression >> 2) & 0x3;
	nlcColor        = (compression >> 4) & 0x1;
	nlcDispMode     = (compression >> 5) & 0x3;   // NLC display mode -> FPGA init word [7:6]
	nlcPack         = (compression >> 7) & 0x1;   // entropy pack -> FPGA init word [8]
	if (codecMode > 2) codecMode = 0;
	blitCompression = (codecMode >= 1) ? 1 : 0;   // LZ4 AND NLC use the LZ DDR zones + compressed blit path
	audioRate = (audio_rate <= 3) ? audio_rate : 0;
	audioChannels = (audio_chan <= 2) ? audio_chan : 0;
	rgbMode = (rgb_mode <= 2) ? rgb_mode : 0;
	memset(poc, 0, sizeof(PoC_type));   // allocated once in groovy_map_ddr(), never freed (see setClose)
	staleCmdLogged = 0;
	initDDR();
	isBlitting = 0;
	usingOldBlit = 0;
	numBlit = 0;
	idleDeadline = GetTimer(idleTimeoutMs);   // arm the idle timeout for this session (harmless if disabled)
	sawActivity = 0;


	char hoststr[NI_MAXHOST];
	char portstr[NI_MAXSERV];

	// Force a genuine cmd_init edge on EVERY (re)connect, unconditionally - not just when
	// doScreensaver is on. A reconnect's CMD_CLOSE is a single best-effort UDP datagram (see
	// the auto-reconnect watchdog in api/groovymister.cpp); if it's lost (a real network drop,
	// or an HPS-thread stall e.g. from USB hotplug rescanning /dev/input starving groovy_poll())
	// setClose() never runs, so cmd_init never drops on its own. Without this, the FPGA's
	// blit-FSM state never revisits S_Idle, so PoC_frame_lz4 (and sibling frame counters) never
	// re-zero - every future frame from this fresh, low-numbered session then fails the core's
	// strict-monotonic frame-adoption gate (Groovy.sv: S_Blit_Header_NLC/S_Blit_Setup_NLC,
	// `new_frame > PoC_frame_lz4`) for the rest of the session: corrupted/frozen video that
	// only a full core reset clears. This pulse must happen BEFORE the fpga_init poll below
	// (fpga_init mirrors "FSM state != S_Idle", rtl/hps_ext.v GET_GROOVY_STATUS byte 4) - a
	// stale cmd_init would otherwise spin that poll forever instead of just this one frame.
	groovy_FPGA_init(0, 0, 0, 0);

	// load LOGO
	if (doScreensaver)
	{
		groovy_FPGA_logo(0);
		groovyLogo = 0;
	}

	if (!isConnected)
	{
		getnameinfo((struct sockaddr *)&clientaddr, clilen, hoststr, sizeof(hoststr), portstr, sizeof(portstr), NI_NUMERICHOST | NI_NUMERICSERV);
		LOG(1,"[Connected][%s][%s:%s]\n", (doXDPServer) ? "XDP" : "UDP", hoststr, portstr);
		isConnected = 1;
	}

	if (doPs2Inputs || doJoyInputs)
  	{
  		int len = 0;
  		if (!doXDPServer)
  		{
			// drain ALL queued subscribe datagrams and keep the LAST one's
			// source address: a reconnecting client (new ephemeral port) may
			// sit behind stale subscribes from an earlier session. Reading
			// just one latched a dead address and streamed joysticks nowhere
			// from the second launch onwards.
			int l;
			while ((l = recvfrom(sockfdInputs, recvbuf, 1, 0, (struct sockaddr *)&clientaddrInputs, &clilen)) > 0)
			{
				len = l;
			}
  		}

  		if (len > 0 || isConnectedInputs)
  		{
			getnameinfo((struct sockaddr *)&clientaddrInputs, clilen, hoststr, sizeof(hoststr), portstr, sizeof(portstr), NI_NUMERICHOST | NI_NUMERICSERV);
			LOG(1,"[Inputs][%s:%s]\n", hoststr, portstr);
  			isConnectedInputs = 1;
  		} 		
  	}

	do
	{
		groovy_FPGA_status(0);
	} while (fpga_init != 0);

 	user_io_status_set(AUDIO_RATE_OPT, (uint32_t)audioRate);
 	user_io_status_set(AUDIO_CHANNELS_OPT, (uint32_t)audioChannels);
 	user_io_status_set(RGB_MODE_OPT, (uint32_t)rgbMode);
 	user_io_status_set(LZ4_OPT, (uint32_t)blitCompression);
 	
	groovy_FPGA_init(1, audioRate, audioChannels, rgbMode);

	dbgSyncLossPrev = 0xff;   // core clears its counters on CMD_INIT; re-prime the watch
	dbgDdrWdPrev = 0xff;
	hkGapMaxMs = 0.0;         // report a fresh worst case per session, not per boot
	memset(hkBucket, 0, sizeof(hkBucket));
	hkDumpTime = GetTimer(HK_DUMP_MS);
}

static void setBlit(uint32_t udp_frame, uint8_t udp_field, uint32_t udp_lz4_size, uint8_t udp_frame_delta)
{
	poc->PoC_frame_recv = udp_frame;
	poc->PoC_bytes_recv = (!blitCompression && udp_frame_delta) ? poc->PoC_bytes_len : 0; //on raw, only duplicated frame supported
	poc->PoC_bytes_lz4_ddr = 0;
	poc->PoC_bytes_lz4_len = (blitCompression) ? udp_lz4_size : 0;	
	if (udp_field == 2)
	{
		poc->PoC_field = (!poc->PoC_FB_progressive) ? (poc->PoC_frame_recv + poc->PoC_field_frame) % 2 : 0;	
	}
	else
	{
		poc->PoC_field = (!udp_field && !poc->PoC_FB_progressive) ? 1 : 0;
	}

	if (blitCompression)
	{
		poc->PoC_buffer_offset = (poc->PoC_field_lz4 == 3) ? LZ4_OFFSET_D : (poc->PoC_field_lz4 == 2) ? LZ4_OFFSET_C : (poc->PoC_field_lz4 == 1) ? LZ4_OFFSET_B : LZ4_OFFSET_A;  
		poc->PoC_field_lz4 = (poc->PoC_field_lz4 == 3) ? 0 : poc->PoC_field_lz4 + 1;
		poc->PoC_delta_lz4 = udp_frame_delta;
	}
	else
	{
		poc->PoC_buffer_offset = (!poc->PoC_FB_progressive && poc->PoC_field) ? FIELD_OFFSET : 0;
		poc->PoC_field_lz4 = 0;
	}
	
	poc->PoC_joystick_order = 0;
	poc->PoC_ps2_order = 0;

	if (isConnectedInputs && doJoyInputs)
	{
		poc->PoC_joystick_keep_alive++;
	}

	if (isConnectedInputs && doPs2Inputs)
	{
		poc->PoC_ps2_keep_alive++;
	}

	
	isBlitting = (!blitCompression && udp_frame_delta) ? 0 : 1;
	isCorePriority =  (!blitCompression && udp_frame_delta) ? 0 : 1;
	numBlit = (!blitCompression && udp_frame_delta) ? 1 : 0;
			
	if (!hpsBlit || (!blitCompression && udp_frame_delta)) //ASAP fpga starts to poll ddr
	{
		if (blitCompression)
		{
			groovy_FPGA_blit_lz4(0, 0);
		}
		else
		{
			groovy_FPGA_blit(poc->PoC_bytes_recv, numBlit);
		}
	}
	else
	{
		poc->PoC_pixels_ddr = 0;
		poc->PoC_bytes_lz4_ddr = 0;
	}		

	uint8_t dbgRead = 0;
	if (doVerbose > 0 && doVerbose < 3)
	{
		groovy_FPGA_status(0);
		dbgRead = 1;
		LOG(1, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][AUDIO=%d][LZ4 inf=%d][DBG %04x %04x %04x %04x]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_audio, fpga_lz4_uncompressed, fpga_dbg_live_a, fpga_dbg_live_b, fpga_dbg_frz_a, fpga_dbg_frz_b);
	}
	else if (blitCompression)
	{
		groovy_FPGA_status(0);   // DBG words sit past the ACK-sized read; needed by the watch below
		dbgRead = 1;
	}

	if (!doVerbose && !fpga_vram_synced)
 	{
 		if (!dbgRead) groovy_FPGA_status(0);
 		LOG(0, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][AUDIO=%d][LZ4 inf=%d][DBG %04x %04x %04x %04x]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_audio, fpga_lz4_uncompressed, fpga_dbg_live_a, fpga_dbg_live_b, fpga_dbg_frz_a, fpga_dbg_frz_b);
 	}	
 	
	if (dbgRead)
	{
		uint8_t frozen = (fpga_dbg_live_b >> 3) & 0x1;             // freeze latched -> word13 is the freeze context
		uint8_t sl     = frozen ? dbgSyncLossPrev : (uint8_t)((fpga_dbg_frz_b >> 8) & 0xff);
		uint8_t wd     = (uint8_t)((fpga_dbg_live_b >> 8) & 0xf);
		if (dbgSyncLossPrev == 0xff)
		{
			dbgSyncLossPrev = sl;
			dbgDdrWdPrev = wd;
		}
		else if (sl != dbgSyncLossPrev || wd != dbgDdrWdPrev)
		{
			openVerboseFile(0);
			// starve_px is the worst frame's starved-pixel count, which is the red run length on
			// screen and therefore the stall duration in pixel clocks. It converts straight into
			// the stall the display suffered:
			//     stall in lines = AUTOBLIT_LEAD + starve_px / active_width
			// A starve_px of 0 means the lead absorbed the whole stall; a large value says by how
			// much the lead would have to be raised to absorb it.
			LOG(0, "[SYNCLOSS][syncloss=%u(+%d) ddrwd=%u][starve_px=%u][GPU fr=%u vc=%u vb=%u fskip=%u][prev ingest=%06.3fms csize=%u]\n",
			    sl, (int) sl - (int) dbgSyncLossPrev, wd, fpga_dbg_w14,
			    fpga_vga_frame, fpga_vga_vcount, fpga_vga_vblank, fpga_vga_frameskip,
			    lastIngestMs, lastIngestBytes);
			if (sl == 0xff) LOG(0, "[SYNCLOSS][counter SATURATED, further events are not counted]%s\n", "");
			dbgSyncLossPrev = sl;
			dbgDdrWdPrev = wd;
		}
	}

 	if (!poc->PoC_bytes_recv)
 	{
 		clock_gettime(CLOCK_MONOTONIC, &blitStart);
 	}		
}

static void setBlitAudio(uint16_t udp_bytes_samples)
{
	poc->PoC_bytes_audio_len = udp_bytes_samples;
	poc->PoC_buffer_offset = AUDIO_OFFSET;
	poc->PoC_bytes_recv = 0;

	isBlitting = 2;
	isCorePriority = 1;
}

static void setBlitRawAudio(uint16_t len)
{
	poc->PoC_bytes_recv += len;
	isBlitting = (poc->PoC_bytes_recv >= poc->PoC_bytes_audio_len) ? 0 : 2;

	LOG(2, "[DDR_AUDIO][%d/%d]\n", poc->PoC_bytes_recv, poc->PoC_bytes_audio_len);

	if (isBlitting == 0)
	{
		uint16_t sound_samples = (audioChannels == 0) ? 0 : (audioChannels == 1) ? poc->PoC_bytes_audio_len >> 1 : poc->PoC_bytes_audio_len >> 2;
		groovy_FPGA_audio(sound_samples);
		poc->PoC_buffer_offset = 0;
		isCorePriority = 0;
	}
}

static void setBlitRaw(uint16_t len)
{
	poc->PoC_bytes_recv += len;
	isBlitting = (poc->PoC_bytes_recv >= poc->PoC_bytes_len) ? 0 : 1;

       	if (!hpsBlit && !recvNotifyDefer) //ASAP (mode 2 notifies once per recv batch instead)
       	{
       		numBlit++;
		groovy_FPGA_blit(poc->PoC_bytes_recv, numBlit);
		LOG(2, "[ACK_BLIT][(%d) px=%d/%d %d/%d]\n", numBlit, poc->PoC_pixels_ddr, poc->PoC_pixels_len, poc->PoC_bytes_recv, poc->PoC_bytes_len);
		//groovy_FPGA_status(0);
       		//LOG(1, "[ACK_STATUS][DDR fr=%d bl=%d][GPU vc=%d fr=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 state_1=%d inf=%d wr=%d, run=%d resume=%d t1=%d t2=%d cmd_fskip=%d stop=%d AB=%d com=%d grav=%d lleg=%d, sub=%d blit=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_state, fpga_lz4_uncompressed, fpga_lz4_writed, fpga_lz4_run, fpga_lz4_resume, fpga_lz4_test1, fpga_lz4_test2, fpga_lz4_cmd_fskip, fpga_lz4_stop, fpga_lz4_ABCD, fpga_lz4_compressed, fpga_lz4_gravats, fpga_lz4_llegits, fpga_lz4_subframe_bytes, fpga_lz4_subframe_blit);
       	}
       	else
       	{
       		LOG(2, "[DDR_BLIT][%d/%d]\n", poc->PoC_bytes_recv, poc->PoC_bytes_len);
       	}

        if (isBlitting == 0)
        {
        	isCorePriority = 0;
        	if (poc->PoC_pixels_ddr < poc->PoC_pixels_len)
        	{
        		numBlit++;
			groovy_FPGA_blit(poc->PoC_bytes_recv, numBlit);
			LOG(2, "[ACK_BLIT][(%d) px=%d/%d %d/%d]\n", numBlit, poc->PoC_pixels_ddr, poc->PoC_pixels_len, poc->PoC_bytes_recv, poc->PoC_bytes_len);
        	}
        	poc->PoC_buffer_offset = 0;		
		clock_gettime(CLOCK_MONOTONIC, &blitStop);        	
        	double difBlit = diff_in_ms(&blitStart, &blitStop);
        	LOG(1, "[DDR_BLIT][TOTAL %06.3f][(%d) Bytes=%d]\n", difBlit, numBlit, poc->PoC_bytes_len);
        }
}

static void setBlitLZ4(uint16_t len)
{
	poc->PoC_bytes_recv += len;
	isBlitting = (poc->PoC_bytes_recv >= poc->PoC_bytes_lz4_len) ? 0 : 1;

	if (!hpsBlit && !recvNotifyDefer) //ASAP (mode 2 notifies once per recv batch instead)
       	{
       		numBlit++;
		groovy_FPGA_blit_lz4(poc->PoC_bytes_recv, numBlit);
		LOG(2, "[ACK_BLIT][(%d) %d/%d]\n", numBlit, poc->PoC_bytes_recv, poc->PoC_bytes_lz4_len);
       	}
       	else
       	{
       		LOG(2, "[LZ4_BLIT][%d/%d]\n", poc->PoC_bytes_recv, poc->PoC_bytes_lz4_len);
       	}

	if (isBlitting == 0)
        {
        	isCorePriority = 0;
        	if (poc->PoC_bytes_lz4_ddr < poc->PoC_bytes_lz4_len)
        	{
        		numBlit++;
			groovy_FPGA_blit_lz4(poc->PoC_bytes_recv, numBlit);
			LOG(2, "[ACK_BLIT][(%d) %d/%d]\n", numBlit, poc->PoC_bytes_recv, poc->PoC_bytes_lz4_len);
        	}
        	poc->PoC_buffer_offset = 0;		
		clock_gettime(CLOCK_MONOTONIC, &blitStop);        	
        	double difBlit = diff_in_ms(&blitStart, &blitStop);
		lastIngestMs    = difBlit;                       // paired with the next blit's sync-loss check
		lastIngestBytes = (uint32_t) poc->PoC_bytes_lz4_len;
		LOG(1, "[LZ4_BLIT][TOTAL %06.3f][(%d) Bytes=%d]\n", difBlit, numBlit, poc->PoC_bytes_lz4_len);
        }
}

static void groovy_map_ddr()
{
    	int pagesize = sysconf(_SC_PAGE_SIZE);
    	if (pagesize==0) pagesize=4096;
    	int offset = BASEADDR;
    	int map_start = offset & ~(pagesize - 1);
    	int map_off = offset - map_start;
    	int num_bytes=BUFFERSIZE;

    	map = (uint8_t*)shmem_map(map_start, num_bytes+map_off);
    	buffer = map + map_off;

    	initDDR();
    	poc = (PoC_type *) calloc(1, sizeof(PoC_type));

    	isCorePriority = 0;
    	isBlitting = 0;

	// One-shot diagnostic: raw store bandwidth into the uncached window (the
	// platform ceiling the recv modes work against). 256KB of 8-byte stores into LZ4 zone D
	// (init-time scratch; real sessions overwrite it).
	{
		struct timespec bt0, bt1;
		volatile uint64_t *bw = (volatile uint64_t *)(buffer + HEADER_OFFSET + LZ4_OFFSET_D);
		clock_gettime(CLOCK_MONOTONIC, &bt0);
		for (int i = 0; i < 32768; i++) bw[i] = 0xA5A5A5A5A5A5A5A5ULL;
		clock_gettime(CLOCK_MONOTONIC, &bt1);
		double bms = diff_in_ms(&bt0, &bt1);
		printf("Groovy DDR window u64-store bench: 256KB in %.2f ms = %.1f MB/s\n", bms, (bms > 0.0) ? 256.0 / 1024.0 / (bms / 1000.0) : 0.0);
	}
}

#ifdef _AF_XDP
static struct xsk_umem_info *configure_xsk_umem(void *buffer, uint64_t size)
{
	struct xsk_umem_info *umem;
	int ret;

	umem = (xsk_umem_info*) calloc(1, sizeof(*umem));
	if (!umem)
	{
		LOG(0, "[XDP][configure_xsk_umem:calloc][%s]\n", "error");
		return NULL;
	}

	ret = xsk_umem__create(&umem->umem, buffer, size, &umem->fq, &umem->cq, NULL);
	if (ret)
	{
		LOG(0, "[XDP][configure_xsk_umem:xsk_umem__create][%s]\n", "error");
		return NULL;
	}
	umem->buffer = buffer;
	return umem;
}

static inline void xsk_free_umem_frame(struct xsk_socket_info *xsk, uint64_t frame)
{
	assert(xsk->umem_frame_free < XDP_NUM_FRAMES);

	xsk->umem_frame_addr[xsk->umem_frame_free++] = frame;
}

static inline uint64_t xsk_umem_free_frames(struct xsk_socket_info *xsk)
{
	return xsk->umem_frame_free;
}

static uint64_t xsk_alloc_umem_frame(struct xsk_socket_info *xsk)
{
	uint64_t frame;
	if (xsk->umem_frame_free == 0)
	{
		return INVALID_UMEM_FRAME;
	}

	frame = xsk->umem_frame_addr[--xsk->umem_frame_free];
	xsk->umem_frame_addr[xsk->umem_frame_free] = INVALID_UMEM_FRAME;
	return frame;
}

static struct xsk_socket_info *xsk_configure_socket(struct xsk_umem_info *umem)
{
	struct xsk_socket_config xsk_cfg;
	struct xsk_socket_info *xsk_info;
	uint32_t idx;
	int i;
	int ret;
//	int sock_opt;

	xsk_info = (xsk_socket_info*) calloc(1, sizeof(*xsk_info));
	if (!xsk_info)
	{
		LOG(0,"[XDP][xsk_info][%s]\n", "error");
		goto xsk_socket_error;
	}
	xsk_info->umem = umem;
	xsk_cfg.rx_size = XSK_RING_CONS__DEFAULT_NUM_DESCS;	//best value				
	xsk_cfg.tx_size = XSK_RING_PROD__DEFAULT_NUM_DESCS;	//best value
	
	xsk_cfg.xdp_flags = XDP_FLAGS_DRV_MODE;		
	//xsk_cfg.bind_flags = XDP_USE_NEED_WAKEUP | XDP_ZEROCOPY; ////zc + recvfrom/sendto UNSTABLE			
	//xsk_cfg.bind_flags &= ~XDP_USE_NEED_WAKEUP;		
	xsk_cfg.bind_flags = XDP_COPY;     		
	xsk_cfg.bind_flags |= XDP_USE_NEED_WAKEUP;
	xsk_cfg.libbpf_flags = XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD;
	ret = xsk_socket__create(&xsk_info->xsk, "eth0", 0, umem->umem, &xsk_info->rx, &xsk_info->tx, &xsk_cfg);
	if (ret)
	{
		LOG(0,"[XDP][xsk_socket__create][error %d]\n", ret);
		goto xsk_socket_error;
	}

	ret = xsk_socket__update_xskmap(xsk_info->xsk, xsk_map_fd);
	if (ret)
	{
		LOG(0,"[XDP][xsk_socket__update_xskmap][error %d]\n", ret);
		goto xsk_socket_error;
	}

	/* Initialize umem frame allocation */
	for (i = 0; i < XDP_NUM_FRAMES; i++)
	{
		xsk_info->umem_frame_addr[i] = i * XDP_FRAME_SIZE;
	}
	xsk_info->umem_frame_free = XDP_NUM_FRAMES;

	/* Stuff the receive path with buffers, we assume we have enough */
	ret = xsk_ring_prod__reserve(&xsk_info->umem->fq, XSK_RING_PROD__DEFAULT_NUM_DESCS, &idx);

	if (ret != XSK_RING_PROD__DEFAULT_NUM_DESCS)
	{
		LOG(0,"[XDP][XSK_RING_PROD__DEFAULT_NUM_DESCS][error %d]\n", ret);
		goto xsk_socket_error;
	}

	for (i = 0; i < XSK_RING_PROD__DEFAULT_NUM_DESCS; i++)
	{
		*xsk_ring_prod__fill_addr(&xsk_info->umem->fq, idx++) = xsk_alloc_umem_frame(xsk_info);
	}
	xsk_ring_prod__submit(&xsk_info->umem->fq, XSK_RING_PROD__DEFAULT_NUM_DESCS);


	// Set socket options (busy poll) Warning: fails sends with XDP_COPY?
	sockfd = xsk_socket__fd(xsk_info->xsk);
/*       
	sock_opt = 20;
        ret = setsockopt(sockfd, SOL_SOCKET, SO_BUSY_POLL, (void *)&sock_opt, sizeof(sock_opt));
        if (ret < 0)
        {
          	LOG(0,"[XDP][SO_BUSY_POLL][error %d]\n", ret);
          	goto xsk_socket_error;
        }
       	sock_opt = 1;
	ret = setsockopt(sockfd, SOL_SOCKET, SO_PREFER_BUSY_POLL, (void *)&sock_opt, sizeof(sock_opt));
        if (ret < 0)
        {
           	LOG(0,"[XDP][SO_PREFER_BUSY_POLL][error %d]\n", ret);
		goto xsk_socket_error;
        }

        sock_opt = 256;
        ret = setsockopt(sockfd, SOL_SOCKET, SO_BUSY_POLL_BUDGET, (void *)&sock_opt, sizeof(sock_opt));
        if (ret < 0)
        {
          	LOG(0,"[XDP][SO_BUSY_POLL_BUDGET][error %d]\n", ret);
           	goto xsk_socket_error;
        }
*/			
	
	return xsk_info;

xsk_socket_error:
	return NULL;
}
#endif

static int setMTU()
{
	int err = 0;
	char *net = getNet(1);
	if (net)
	{
		LOG(1, "[ETH][START %s]\n", net);
	}
	else
	{
		net = getNet(2);
		if (net)
		{
			LOG(1, "[ETH][START %s]\n", net);
		}
		else
		{
			goto mtu_error;
		}
	}
		
	sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    	if (sockfd < 0)
    	{
    		LOG(0, "[ETH]][error %d]\n", sockfd);
    		goto mtu_error;
    	}

	struct ifreq ifr;
        memset(&ifr, 0, sizeof(ifr));
        strncpy((char *)ifr.ifr_name, "eth0", IFNAMSIZ);
        err = ioctl (sockfd, SIOCGIFMTU, &ifr);
	if (err < 0)
    	{
    		LOG(0, "[ETH0][SIOCGIFMTU mtu][error %d]\n", err);
    		goto mtu_error;
	}
	if ((doJumboFrames && ifr.ifr_mtu == 1500) || (!doJumboFrames && ifr.ifr_mtu != 1500)) // kernel 5.13 stmmac needs stop eth for change mtu (fixed on new kernels)
	{
		ifr.ifr_flags = 1 & ~IFF_UP;
		err = ioctl(sockfd, SIOCSIFFLAGS, &ifr);
		if (err < 0)
    		{
    			LOG(0, "[ETH0][SIOCSIFFLAGS down][error %d]\n", err);
    			goto mtu_error;
		}
		LOG(1, "[ETH0][%s]\n", "DOWN");
		ifr.ifr_mtu = doJumboFrames ? 3800 : 1500;
		if (ioctl(sockfd, SIOCSIFMTU, (caddr_t)&ifr) < 0)
		{
			ifr.ifr_mtu = 1500;
			doJumboFrames = 0;
		}
		LOG(1, "[ETH][MTU 1500 -> %d]\n", ifr.ifr_mtu);
		ifr.ifr_flags = 1 | IFF_UP;
		err = ioctl(sockfd, SIOCSIFFLAGS, &ifr);
		if (err < 0)
    		{
    			LOG(0, "[ETH0][SIOCSIFFLAGS up][error %d]\n", err);
    			goto mtu_error;
		}
		LOG(1, "[ETH0][%s]\n", "UP");	
		close(sockfd);
		goto mtu_error;	
	}
	close(sockfd);	
	return 0;
	
mtu_error: return -1;
}

#ifdef _AF_XDP
static void groovy_xdp_server_init()
{		
	int err = 0;	
	int pagesize, map_start, map_off;
	struct bpf_map *map;
	struct rlimit rlim = {RLIM_INFINITY, RLIM_INFINITY};	
	struct bpf_object *obj;
	int prog_fd;
	struct bpf_prog_load_attr prog_load_attr;
	//struct xdp_multiprog *mp = NULL;	

	if (setMTU() < 0)
	{
		goto init_error_xdp;	
	}	
	
	setRXAffinity(0);

	// load ebpf program and attach to kernel eth0
	memset(&prog_load_attr, 0, sizeof(struct bpf_prog_load_attr));
	prog_load_attr.prog_type = BPF_PROG_TYPE_XDP;
	prog_load_attr.file = "/usr/lib/arm-linux-gnueabihf/bpf/groovy_xdp_kern.o";
	if (bpf_prog_load_xattr(&prog_load_attr, &obj, &prog_fd))
	{
		LOG(0, "[XDP][bpf_prog_load_xattr][%s]\n", "error");
		goto init_error_xdp;
	}
	if (prog_fd < 0) {
		LOG(0, "[XDP][bpf_prog_load_xattr][%d]\n", prog_fd);
		goto init_error_xdp;
	}
	err = bpf_set_link_xdp_fd(if_nametoindex("eth0"), prog_fd, XDP_FLAGS_DRV_MODE);
	//err = bpf_set_link_xdp_fd(if_nametoindex("eth0"), prog_fd, XDP_FLAGS_SKB_MODE);
	
	if (err < 0)
	{
		LOG(0, "[XDP][bpf_set_link_xdp_fd][error %d]\n", err);
		goto init_error_xdp;
	}
	map = bpf_object__find_map_by_name(obj, "xsks_map");

	// with dispatcher
	/*
	prog = xdp_program__open_file("/usr/lib/arm-linux-gnueabihf/bpf/groovy_xdp_kern.o", "xdp_groovymister", NULL);
	err = libxdp_get_error(prog);
	if (err)
	{
		LOG(0, "[XDP][xdp_program__open_file][error %d]\n", err);
		goto init_error_xdp;
	}
	// attach using native mode driver stmmac
	err = xdp_program__attach(prog, if_nametoindex("eth0"), XDP_MODE_NATIVE, 0);
	if (err)
	{
		if (err != -16) //prev.attached
		{
			LOG(0, "[XDP][xdp_program__attach][error %d]\n", err);
			goto init_error_xdp;
		}
		else
		{
			LOG(0, "[XDP][xdp_program__attach][%s]\n", "skip");
		}
	}
	// load maps
	map = bpf_object__find_map_by_name(xdp_program__bpf_obj(prog), "xsks_map");
	*/
	xsk_map_fd = bpf_map__fd(map);
	if (xsk_map_fd < 0)
	{
		LOG(0, "[XDP][bpf_map__fd[error %d]\n", xsk_map_fd);
		goto init_error_xdp;
	}
	// no limit memory alloc
	err = setrlimit(RLIMIT_MEMLOCK, &rlim);
	if (err)
	{
		LOG(0, "[XDP][setrlimit][error %d]\n", err);
		goto init_error_xdp;
	}
	// allocate map for umem
	pagesize = sysconf(_SC_PAGE_SIZE);
    	if (pagesize==0) pagesize=4096;
    	map_start = XDP_BASEADDR & ~(pagesize - 1);
    	map_off = XDP_BASEADDR - map_start;
    	packet_buffer_size = (XDP_NUM_FRAMES * XDP_FRAME_SIZE) + map_off;
    	packet_buffer = shmem_map_private(map_start, packet_buffer_size);
    	if (packet_buffer == (void *)-1)
    	{
    		LOG(0, "[XDP][mmap umem][%s]\n", "error");
    		goto init_error_xdp;
    	}
    	// Initialize shared packet_buffer for umem usage
	umem = configure_xsk_umem(packet_buffer, packet_buffer_size);
	if (umem == NULL)
	{
		LOG(0, "[XDP][configure_xsk_umem][%s]\n", "error");
		goto init_error_xdp;
	}
	// Open and configure the AF_XDP (xsk) socket
	xsk_socket = xsk_configure_socket(umem);
	if (xsk_socket == NULL)
	{
		LOG(0, "[XDP][xsk_configure_socket][%s]\n", "error");
		goto init_error_xdp;
	}

	LOG(0, "[XDP][STARTED][%d]\n", GROOVY_VERSION);

	groovyServer = 2;
	return;

init_error_xdp:
	groovyServer = 1;
}
#endif

static void groovy_udp_server_init()
{
	int ret = 0;
	int flags, size, beTrueAddr;		
	
	if (setMTU() < 0)
	{
		goto init_error_udp;	
	}
	
	setRXAffinity(0);
	
	sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    	if (sockfd < 0)
    	{
    		LOG(0, "[UDP][socket error %d]\n", sockfd);
    		goto init_error_udp;
    	}
    	
    	memset(&servaddr, 0, sizeof(servaddr));
    	servaddr.sin_family = AF_INET;
    	servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    	servaddr.sin_port = htons(UDP_PORT);

        // Non blocking socket
    	flags = fcntl(sockfd, F_GETFD, 0);
    	if (flags < 0)
    	{
      		LOG(0, "[UDP][get falg][error %d]\n", flags);
      		goto init_error_udp;
    	}
    	flags |= O_NONBLOCK;
    	ret = fcntl(sockfd, F_SETFL, flags);
    	if (ret < 0)
    	{
    		LOG(0, "[UDP][set nonblock fail][error %d]\n", ret);
       		goto init_error_udp;
    	}

	// Settings
	size = 2 * 1024 * 1024;
	ret = setsockopt(sockfd, SOL_SOCKET, SO_RCVBUFFORCE, (void*)&size, sizeof(size));
        if (ret < 0)
        {
        	LOG(0, "[UDP][SO_RCVBUFFORCE][error %d]\n", ret);
        	goto init_error_udp;
        }
	beTrueAddr = 1;
	ret = setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, (void*)&beTrueAddr,sizeof(beTrueAddr));
	if (ret < 0)
	{
        	LOG(0, "[UDP][SO_REUSEADDR][error %d]\n", ret);
        	goto init_error_udp;
        }
        ret = setsockopt(sockfd, IPPROTO_IP, IP_TOS, (char*)&beTrueAddr,sizeof(beTrueAddr));
        if (ret < 0)
	{
        	LOG(0, "[UDP][IP_TOS][error %d]\n", ret);
        	goto init_error_udp;
        }
        /*
        beTrueAddr = 20;
        ret = setsockopt(sockfd, SOL_SOCKET, SO_BUSY_POLL, (void *)&beTrueAddr, sizeof(beTrueAddr));
        if (ret < 0)
        {
          	LOG(0,"[XDP][SO_BUSY_POLL][error %d]\n", ret);
          	goto init_error_udp;
        }
        beTrueAddr = 256;
        ret = setsockopt(sockfd, SOL_SOCKET, SO_BUSY_POLL_BUDGET, (void *)&beTrueAddr, sizeof(beTrueAddr));
        if (ret < 0)
        {
          	LOG(0,"[XDP][SO_BUSY_POLL_BUDGET][error %d]\n", ret);
           	goto init_error_udp;
        }
        */
        ret = bind(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr));
    	if (ret < 0)
    	{
    		LOG(0, "[UDP][bind][error %d]\n", ret);
    		goto init_error_udp;
    	}

	LOG(0, "[UDP][STARTED][%d]\n", GROOVY_VERSION);
	groovyServer = 2;
	return;

init_error_udp:
	groovyServer = 1;

}

static void groovy_udp_server_init_inputs()
{
	int ret = 0;
	int flags, beTrueAddr;
	sockfdInputs = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    	if (sockfdInputs < 0)
    	{
    		LOG(0, "[UDP][socketInputs][error %d]\n", sockfdInputs);
    		goto inputs_error;
    	}

    	memset(&servaddrInputs, 0, sizeof(servaddrInputs));
    	servaddrInputs.sin_family = AF_INET;
    	servaddrInputs.sin_addr.s_addr = htonl(INADDR_ANY);
    	servaddrInputs.sin_port = htons(UDP_PORT_INPUTS);

        // Non blocking socket
    	flags = fcntl(sockfdInputs, F_GETFD, 0);
    	if (flags < 0)
    	{
      		LOG(0, "[UDP][get falg inputs][error %d]\n", flags);
      		goto inputs_error;
    	}
    	flags |= O_NONBLOCK;
    	ret = fcntl(sockfdInputs, F_SETFL, flags);
    	if (ret < 0)
    	{
       		LOG(0, "[UDP][set nonblock inputs fail][error %d]\n", ret);
       		goto inputs_error;
    	}

	beTrueAddr = 1;
	ret = setsockopt(sockfdInputs, SOL_SOCKET, SO_REUSEADDR, (void*)&beTrueAddr,sizeof(beTrueAddr));
	if (ret < 0)
	{
        	LOG(0, "[UDP][SO_REUSEADDR inputs][error %d]\n", ret);
        	goto inputs_error;
        }
        ret = setsockopt(sockfdInputs, IPPROTO_IP, IP_TOS, (char*)&beTrueAddr,sizeof(beTrueAddr));
        if (ret < 0)
	{
        	LOG(0, "[UDP][IP_TOS inputs][error %d]\n", ret);
        	goto inputs_error;
        }
        ret = bind(sockfdInputs, (struct sockaddr *)&servaddrInputs, sizeof(servaddrInputs));
    	if (ret < 0)
    	{
    		LOG(0, "[UDP][bind inputs][error %d]\n", ret);
    		goto inputs_error;
    	}

inputs_error:
    	isConnectedInputs = 0;
}

static void groovy_udp_server_init_gmc()
{
	int ret = 0;
	int flags, beTrueAddr;
	sockfdGMC = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    	if (sockfdGMC < 0)
    	{
    		LOG(0, "[UDP][socketGMC][error %d]\n", sockfdGMC);
    		goto gmc_error;
    	}

    	memset(&servaddrGMC, 0, sizeof(servaddrGMC));
    	servaddrGMC.sin_family = AF_INET;
    	servaddrGMC.sin_addr.s_addr = htonl(INADDR_ANY);
    	servaddrGMC.sin_port = htons(UDP_PORT_GMC);

        // Non blocking socket
    	flags = fcntl(sockfdGMC, F_GETFD, 0);
    	if (flags < 0)
    	{
      		LOG(0, "[UDP][get falg GMC][error %d]\n", flags);
      		goto gmc_error;
    	}
    	flags |= O_NONBLOCK;
    	ret = fcntl(sockfdGMC, F_SETFL, flags);
    	if (ret < 0)
    	{
       		LOG(0, "[UDP][set nonblock GMC fail][error %d]\n", ret);
       		goto gmc_error;
    	}

	beTrueAddr = 1;
	ret = setsockopt(sockfdGMC, SOL_SOCKET, SO_REUSEADDR, (void*)&beTrueAddr,sizeof(beTrueAddr));
	if (ret < 0)
	{
        	LOG(0, "[UDP][SO_REUSEADDR GMC][error %d]\n", ret);
        	goto gmc_error;
        }
        ret = setsockopt(sockfdGMC, IPPROTO_IP, IP_TOS, (char*)&beTrueAddr,sizeof(beTrueAddr));
        if (ret < 0)
	{
        	LOG(0, "[UDP][IP_TOS GMC][error %d]\n", ret);
        	goto gmc_error;
        }
        ret = bind(sockfdGMC, (struct sockaddr *)&servaddrGMC, sizeof(servaddrGMC));
    	if (ret < 0)
    	{
    		LOG(0, "[UDP][bind GMC][error %d]\n", ret);
    		goto gmc_error;
    	}
		
gmc_error:
    	isConnectedGMC = 0;
}

static inline void process_packet(char *recvbufPtr, int len)
{
	if (len > 0)
	{
		sawActivity = 1;   // idle-timeout liveness: any datagram (blit chunk, audio, CMD_GET_STATUS
		                   // keepalive, ...) counts. Single byte store only - the deadline math runs
		                   // once per poll in groovy_poll(), never in this per-chunk path.
		if (isBlitting)
		{
			//udp error lost detection (jumbo to do)
			if (len > 0 && len < 1472)
			{
				int prev_len = len;
				int tota_len = 0;
				if (isBlitting == 1 && !blitCompression && poc->PoC_bytes_recv + len != poc->PoC_bytes_len) // raw rgb
				{
					if (!hpsBlit)
					{
						groovy_FPGA_blit(poc->PoC_bytes_len, 65535);
					}
					isBlitting = 0;
					prev_len = poc->PoC_bytes_len % 1472;
					tota_len = poc->PoC_bytes_len;
				}
				if (isBlitting == 1 && blitCompression && poc->PoC_bytes_recv + len != poc->PoC_bytes_lz4_len) // lz4 rgb
				{
					if (!hpsBlit)
					{
						groovy_FPGA_blit_lz4(poc->PoC_bytes_lz4_len, 65535);
					}
					isBlitting = 0;
					prev_len = poc->PoC_bytes_lz4_len % 1472;
					tota_len = poc->PoC_bytes_lz4_len;
				}
				if (isBlitting == 2 && poc->PoC_bytes_recv + len != poc->PoC_bytes_audio_len) // audio
				{
					isBlitting = 0;
					prev_len = poc->PoC_bytes_audio_len % 1472;
					tota_len = poc->PoC_bytes_audio_len;
				}
				if (!isBlitting)
				{
					isCorePriority = 0;
					if (len != prev_len && len <= 26)
					{
						memcpy((char *) &recvbuf[0], recvbufPtr, len);
						recvbufPtr = (char *) &recvbuf[0];
						LOG(0,"[UDP_ERROR][RECONFIG fr=%d recv=%d/%d prev_len=%d len=%d]\n", poc->PoC_frame_ddr, poc->PoC_bytes_recv, tota_len, prev_len, len);
					}
					else
					{
						LOG(0,"[UDP_ERROR][fr=%d recv=%d/%d len=%d]\n", poc->PoC_frame_ddr, poc->PoC_bytes_recv, tota_len, len);
						len = -1;
					}
				}
			}
		}

		if (!isBlitting)
		{
			// No session: the client is never told when one ends, so after setClose() (idle timeout,
			// or a CMD_CLOSE) it may still be streaming. Running the blit path on those packets drove
			// the FPGA and the DDR write pointer from torn-down state. Only these three commands mean
			// anything without a session.
			if (!isConnected && recvbufPtr[0] != CMD_INIT && recvbufPtr[0] != CMD_GET_VERSION && recvbufPtr[0] != CMD_CLOSE)
			{
				if (!staleCmdLogged)
				{
					staleCmdLogged = 1;
					LOG(0, "[STALE_CMD][cmd=%d len=%d][no session, ignoring until CMD_INIT]\n", recvbufPtr[0], len);
				}
				return;
			}
    			switch (recvbufPtr[0])
    			{
    				case CMD_GET_VERSION:
				{
					if (len == 1)
					{						
						LOG(1, "[CMD_GET_VERSION][%d][ver=%d]\n", recvbufPtr[0], GROOVY_VERSION);
						sendVersion();
					}
				}; break;
				
	    			case CMD_CLOSE:
				{
					if (len == 1 && isConnected)   // ignore duplicate/stale closes: re-running teardown
					{                              // on an already-closed core double-freed poc (now NULLed too)
						LOG(1, "[CMD_CLOSE][%d]\n", recvbufPtr[0]);
						setClose();
					}
				}; break;

				case CMD_INIT:
				{
					if (len == 4 || len == 5 || len == 6)
					{
						openVerboseFile(1);   // session start: truncates unless append is on
						logSession++;
						LOG(0, "[SESSION][%u][verbose=%d append=%d]\n", logSession, doVerbose, logAppend);
						uint8_t compression = recvbufPtr[1];
						uint8_t audio_rate = recvbufPtr[2];
						uint8_t audio_channels = recvbufPtr[3];
						uint8_t rgb_mode = (len >= 5) ? recvbufPtr[4] : 0;
						clientCaps = (len >= 6) ? (uint8_t)recvbufPtr[5] : 0;
						if (clientCaps) LOG(1, "[CMD_INIT][caps=0x%02x]\n", clientCaps);
						LOG(1, "[CMD_INIT][%d][LZ4=%d][Audio rate=%d chan=%d][%s][ver=%d]\n", recvbufPtr[0], compression, audio_rate, audio_channels, (rgb_mode == 1) ? "RGBA888" : (rgb_mode == 2) ? "RGB565" : "RGB888", GROOVY_VERSION);
						LOG(1, "[RECV_MODE][%d]\n", recvMode);
						setInit(compression, audio_rate, audio_channels, rgb_mode);
						sendACK(0, 0);						
					}
				}; break;

				case CMD_SWITCHRES:
				{
					if (len == 26)
					{
						LOG(1, "[CMD_SWITCHRES][%d]\n", recvbufPtr[0]);
			       			setSwitchres(&recvbufPtr[0]);
			       			sendACK(0, 0); // CmdSwitchres now waits for this + retries (see api/groovymister.cpp);
			       			                // previously unacknowledged, so a lost packet on reconnect left
			       			                // PoC_bytes_len at 0 forever (silent "no modeline" packet drops).
			       		}
				}; break;

				case CMD_AUDIO:
				{
					if (len == 3)
					{
						uint16_t udp_bytes_samples = ((uint16_t) recvbufPtr[2]  << 8) | recvbufPtr[1];
						LOG(1, "[CMD_AUDIO][%d][Bytes=%d]\n", recvbufPtr[0], udp_bytes_samples);
						setBlitAudio(udp_bytes_samples);						
					}
				}; break;

				case CMD_GET_STATUS:
				{
					if (len == 1)
					{
						groovy_FPGA_status(1);
						sendACK(0, 0);
			       			LOG(1, "[CMD_GET_STATUS][%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][AUDIO=%d][LZ4 inf=%d]\n", recvbufPtr[0], fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_audio, fpga_lz4_uncompressed);

					}
				}; break;

				case CMD_BLIT_VSYNC: //deprecated
				{
					if (len == 7 || len == 11)
					{
						uint32_t udp_lz4_size = 0;																							
						uint32_t udp_frame = ((uint32_t) recvbufPtr[4]  << 24) | ((uint32_t)recvbufPtr[3]  << 16) | ((uint32_t)recvbufPtr[2]  << 8) | recvbufPtr[1];								
						uint8_t udp_field = (poc->PoC_FB_progressive) ? 0 : 2;	
						uint16_t udp_vsync = ((uint16_t) recvbufPtr[6]  << 8) | recvbufPtr[5];						
						if (len == 11 && blitCompression)
						{
							udp_lz4_size = ((uint32_t) recvbufPtr[10]  << 24) | ((uint32_t)recvbufPtr[9]  << 16) | ((uint32_t)recvbufPtr[8]  << 8) | recvbufPtr[7];								
							LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d][CSize=%d]\n", recvbufPtr[0], udp_frame, udp_vsync, udp_lz4_size);
						}
						else
						{
							LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d]\n", recvbufPtr[0], udp_frame, udp_vsync);
						}																	
				       		setBlit(udp_frame, udp_field, udp_lz4_size, 0);
				       		groovy_FPGA_status(1);
				       		//LOG(1, "[GET_STATUS][DDR fr=%d bl=%d][GPU vc=%d fr=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 state_1=%d inf=%d wr=%d, run=%d resume=%d t1=%d t2=%d cmd_fskip=%d stop=%d AB=%d com=%d grav=%d lleg=%d, sub=%d blit=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_state, fpga_lz4_uncompressed, fpga_lz4_writed, fpga_lz4_run, fpga_lz4_resume, fpga_lz4_test1, fpga_lz4_test2, fpga_lz4_cmd_fskip, fpga_lz4_stop, fpga_lz4_ABCD, fpga_lz4_compressed, fpga_lz4_gravats, fpga_lz4_llegits, fpga_lz4_subframe_bytes, fpga_lz4_subframe_blit);
				       		sendACK(udp_frame, udp_vsync);	
				       		usingOldBlit = 1;			       		
				       	}
				}; break;
				
				case CMD_BLIT_FIELD_VSYNC:
				{
					if (len == 8 || len == 12 || len == 9 || len == 13)
					{
						uint32_t udp_lz4_size = 0;
						uint8_t udp_frame_delta = 0;
						uint32_t udp_frame = ((uint32_t) recvbufPtr[4]  << 24) | ((uint32_t)recvbufPtr[3]  << 16) | ((uint32_t)recvbufPtr[2]  << 8) | recvbufPtr[1];
						uint8_t udp_field = (poc->PoC_FB_progressive) ? 0 : (uint8_t) recvbufPtr[5];
						uint16_t udp_vsync = ((uint16_t) recvbufPtr[7]  << 8) | recvbufPtr[6];	
						if (len == 9 && !blitCompression)
						{
							udp_frame_delta = recvbufPtr[8]; 
						}		
						if (len == 13 && blitCompression)
						{
							udp_frame_delta = recvbufPtr[12];
						}			
						if ((len == 12 || len == 13) && blitCompression)
						{
							udp_lz4_size = ((uint32_t) recvbufPtr[11]  << 24) | ((uint32_t)recvbufPtr[10]  << 16) | ((uint32_t)recvbufPtr[9]  << 8) | recvbufPtr[8];								
							LOG(1, "[CMD_BLIT][%d][Frame=%d(%d)][Vsync=%d][CSize=%d][Delta=%d]\n", recvbufPtr[0], udp_frame, udp_field, udp_vsync, udp_lz4_size, udp_frame_delta);							
						}
						else							
						{
							LOG(1, "[CMD_BLIT][%d][Frame=%d(%d)][Vsync=%d][Dup=%d]\n", recvbufPtr[0], udp_frame, udp_field, udp_vsync, udp_frame_delta);
						}				       																
				       		setBlit(udp_frame, udp_field, udp_lz4_size, udp_frame_delta);
				       		groovy_FPGA_status(1);
				       		//LOG(1, "[GET_STATUS][DDR fr=%d bl=%d][GPU vc=%d fr=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 state_1=%d inf=%d wr=%d, run=%d resume=%d t1=%d t2=%d cmd_fskip=%d stop=%d AB=%d com=%d grav=%d lleg=%d, sub=%d blit=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_state, fpga_lz4_uncompressed, fpga_lz4_writed, fpga_lz4_run, fpga_lz4_resume, fpga_lz4_test1, fpga_lz4_test2, fpga_lz4_cmd_fskip, fpga_lz4_stop, fpga_lz4_ABCD, fpga_lz4_compressed, fpga_lz4_gravats, fpga_lz4_llegits, fpga_lz4_subframe_bytes, fpga_lz4_subframe_blit);
				       		sendACK(udp_frame, udp_vsync);
				       	}
				}; break;

				default:
				{
					// Fires for every ordinary blit-continuation payload packet while !isBlitting
					// (i.e. essentially every packet, in normal operation) - pure noise at doVerbose=1,
					// where it dwarfs every other line in the file. Bumped to severity 2 so it's
					// filtered out at the verbosity level actually used for diagnosis; the real error
					// signal (UDP_ERROR/RECONFIG) is severity 0 and always logged regardless.
					LOG(2,"command: %i (len=%d)\n", recvbufPtr[0], len);
				}
			}
		}
		else
		{
			if (poc->PoC_bytes_len > 0) // modeline?
			{
				if (isBlitting == 1)
				{
					if (blitCompression)
					{
						setBlitLZ4(len);
					}
					else
					{
						setBlitRaw(len);
					}
				}
				else
				{
					setBlitRawAudio(len);
				}
			}
			else
			{
				LOG(1, "[UDP_BLIT][%d bytes][Skipped no modeline]\n", len);
				isBlitting = 0;
				isCorePriority = 0;
			}
		}
	}
}


#ifdef _AF_XDP
static inline int process_packet_eth(struct xsk_socket_info *xsk, uint64_t addr, uint32_t len)
{
	if (!len)
	{
		return 0;
	}
	
	uint8_t tmp_mac[ETH_ALEN];
	struct in_addr tmp_ip;
	struct ethhdr *eth = (struct ethhdr *) xsk_umem__get_data(xsk->umem->buffer, addr);
	struct iphdr *ip = (struct iphdr *) ((uint8_t *) eth + ETH_HLEN); //14 + 20
	struct udphdr *udp = (struct udphdr *) (((char *)ip ) + sizeof(iphdr)); //34 + 8
	int udp_len;
	char* data_pointer = (char*)eth;
	udp_len = ntohs(udp->len) - sizeof(struct udphdr);

	//set headers preparing send acks
	if (!isConnected && ntohs(udp->dest) == UDP_PORT)
	{
		ip->tos = 7 << 5; //max priority
		
		memset(&clientaddr, 0, sizeof (clientaddr));
 		clientaddr.sin_family = AF_INET;
		clientaddr.sin_addr.s_addr = ip->saddr;
		clientaddr.sin_port = udp->source;

		memcpy(tmp_mac, eth->h_dest, ETH_ALEN);
		memcpy(eth->h_dest, eth->h_source, ETH_ALEN);
		memcpy(eth->h_source, tmp_mac, ETH_ALEN);

		memcpy(&tmp_ip, &ip->saddr, sizeof(tmp_ip));
		memcpy(&ip->saddr, &ip->daddr, sizeof(tmp_ip));
		memcpy(&ip->daddr, &tmp_ip, sizeof(tmp_ip));

		memcpy(&udp->dest,&udp->source, sizeof(udp->dest));
		udp->source = htons(UDP_PORT);				
		
		//precalculate ip checksum header	
		udp->check = 0;
		ip->check = 0;	
		udp->len = htons(13 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 13);
		update_iph_checksum(ip);
		ip_check_13 = ip->check;		
		udp_check_13 = sum_udp_checksum(ip, udp->len); 
				
		udp->check = 0;
		ip->check = 0;	
		udp->len = htons(1 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 1);
		update_iph_checksum(ip);
		ip_check_1 = ip->check;		
		udp_check_1 = sum_udp_checksum(ip, udp->len); 						
				
		memcpy(&sendbuf[0], &data_pointer[0], 42);
	}

	//set headers preparing send inputs
	if (ntohs(udp->dest) == UDP_PORT_INPUTS && (doPs2Inputs || doJoyInputs))
	{
		ip->tos = 7 << 5; //max priority
		
		memset(&clientaddrInputs, 0, sizeof (clientaddrInputs));
 		clientaddrInputs.sin_family = AF_INET;
		clientaddrInputs.sin_addr.s_addr = ip->saddr;
		clientaddrInputs.sin_port = udp->source;

		memcpy(tmp_mac, eth->h_dest, ETH_ALEN);
		memcpy(eth->h_dest, eth->h_source, ETH_ALEN);
		memcpy(eth->h_source, tmp_mac, ETH_ALEN);

		memcpy(&tmp_ip, &ip->saddr, sizeof(tmp_ip));
		memcpy(&ip->saddr, &ip->daddr, sizeof(tmp_ip));
		memcpy(&ip->daddr, &tmp_ip, sizeof(tmp_ip));

		memcpy(&udp->dest,&udp->source, sizeof(udp->dest));
		udp->source = htons(UDP_PORT_INPUTS);		
		
		//precalculate ip checksum headers
		udp->check = 0;
		ip->check = 0;
		udp->len = htons(9 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 9);
		update_iph_checksum(ip);
		inputs_ip_check_9 = ip->check;
		inputs_udp_check_9 = sum_udp_checksum(ip, udp->len); 

		udp->check = 0;
		ip->check = 0;
		udp->len = htons(17 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 17);
		update_iph_checksum(ip);
		inputs_ip_check_17 = ip->check;
		inputs_udp_check_17 = sum_udp_checksum(ip, udp->len); 

		udp->check = 0;
		ip->check = 0;
		udp->len = htons(13 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 13);
		update_iph_checksum(ip);
		inputs_ip_check_13 = ip->check;
		inputs_udp_check_13 = sum_udp_checksum(ip, udp->len);

		udp->check = 0;
		ip->check = 0;
		udp->len = htons(25 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 25);
		update_iph_checksum(ip);
		inputs_ip_check_25 = ip->check;
		inputs_udp_check_25 = sum_udp_checksum(ip, udp->len);

		udp->check = 0;
		ip->check = 0;
		udp->len = htons(37 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 37);
		update_iph_checksum(ip);
		inputs_ip_check_37 = ip->check;
		inputs_udp_check_37 = sum_udp_checksum(ip, udp->len); 

		udp->check = 0;
		ip->check = 0;
		udp->len = htons(41 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 41);
		update_iph_checksum(ip);
		inputs_ip_check_41 = ip->check;
		inputs_udp_check_41 = sum_udp_checksum(ip, udp->len); 

		memcpy(&sendbufInputs[0], &data_pointer[0], 42);
		isConnectedInputs = 1;
		
		return udp_len;
	}
	
	//set headers preparing send gmc
	if (ntohs(udp->dest) == UDP_PORT_GMC)
	{
		ip->tos = 7 << 5; //max priority
		
		memset(&clientaddrGMC, 0, sizeof (clientaddrGMC));
 		clientaddrGMC.sin_family = AF_INET;
		clientaddrGMC.sin_addr.s_addr = ip->saddr;
		clientaddrGMC.sin_port = udp->source;

		memcpy(tmp_mac, eth->h_dest, ETH_ALEN);
		memcpy(eth->h_dest, eth->h_source, ETH_ALEN);
		memcpy(eth->h_source, tmp_mac, ETH_ALEN);

		memcpy(&tmp_ip, &ip->saddr, sizeof(tmp_ip));
		memcpy(&ip->saddr, &ip->daddr, sizeof(tmp_ip));
		memcpy(&ip->daddr, &tmp_ip, sizeof(tmp_ip));

		memcpy(&udp->dest,&udp->source, sizeof(udp->dest));
		udp->source = htons(UDP_PORT_GMC);
				
		udp->check = 0;						
		memcpy(&sendbufGMC[0], &data_pointer[0], 42);
		isConnectedGMC = 1;							
		
		return udp_len;
	}

	if (isBlitting)
	{
		memcpy((char *) (buffer + HEADER_OFFSET + poc->PoC_buffer_offset + poc->PoC_bytes_recv), &data_pointer[42], udp_len);
		process_packet(&data_pointer[42], udp_len);
	}
	else
	{
		process_packet(&data_pointer[42], udp_len);
	}

	return udp_len;
}

static inline void handle_receive_packets(struct xsk_socket_info *xsk)
{
	int rcvd, stock_frames, i;
	uint32_t idx_rx = 0, idx_fq = 0;
	int ret = 0;	
	 	
	//recvfrom(xsk_socket__fd(xsk->xsk), NULL, 0, MSG_DONTWAIT, NULL, NULL);
	rcvd = xsk_ring_cons__peek(&xsk->rx, RX_BATCH_SIZE, &idx_rx);
	
	if (!rcvd)	
	{	
		/*
		if (xsk_ring_prod__needs_wakeup(&xsk->umem->fq))
		{ 				 
			recvfrom(sockfd, NULL, 0, MSG_DONTWAIT, NULL, NULL);			
		}				
		*/
		return;
	}
		
	//Stuff the ring with as much frames as possible when not blitting
	//stock_frames = xsk_prod_nb_free(&xsk->umem->fq, xsk_umem_free_frames(xsk));	
	stock_frames = rcvd;		
	if (stock_frames > 0)
	{ 
		ret = xsk_ring_prod__reserve(&xsk->umem->fq, stock_frames, &idx_fq);				
		// This should not happen, but just in case
		while (ret != stock_frames)
		{
			/*
			if (xsk_ring_prod__needs_wakeup(&xsk->umem->fq))
			{
				recvfrom(xsk_socket__fd(xsk->xsk), NULL, 0, MSG_DONTWAIT, NULL, NULL);
			}
			*/
			ret = xsk_ring_prod__reserve(&xsk->umem->fq, rcvd, &idx_fq);
		}
		for (i = 0; i < stock_frames; i++)
		{
			*xsk_ring_prod__fill_addr(&xsk->umem->fq, idx_fq++) = xsk_alloc_umem_frame(xsk);
		}
		xsk_ring_prod__submit(&xsk->umem->fq, stock_frames);
	}	
		
	// Process received packets
	for (i = 0; i < rcvd; i++)
	{		
		uint64_t addr = xsk_ring_cons__rx_desc(&xsk->rx, idx_rx)->addr;
		uint32_t len = xsk_ring_cons__rx_desc(&xsk->rx, idx_rx++)->len;	
		process_packet_eth(xsk, addr, len);	
		xsk_free_umem_frame(xsk, addr);
	}
			
	xsk_ring_cons__release(&xsk->rx, rcvd);	
}
#endif

static void groovy_start()
{
	if (!groovyServer)
	{
		printf("Groovy-Server %d starting\n", GROOVY_VERSION);

		// get HPS Server Settings
		groovy_FPGA_hps();

		// ingest receive mode (env overrides the cfg file; default 1 = cached bounce)
		{
			const char *rm = getenv("GROOVY_RECV_MODE");
			char rmbuf[8] = {0};
			if (!rm)
			{
				FILE *rf = fopen("/media/fat/groovy_recv.cfg", "r");
				if (rf)
				{
					if (fgets(rmbuf, sizeof(rmbuf), rf)) rm = rmbuf;
					fclose(rf);
				}
			}
			if (rm && rm[0] >= '0' && rm[0] <= '2') recvMode = rm[0] - '0';
#ifndef MSG_WAITFORONE
			if (recvMode == 2) recvMode = 1;         // no recvmmsg on this libc: degrade to bounce
#endif
			printf("Groovy recv mode %d\n", recvMode);

			const char *la = getenv("GROOVY_LOG_APPEND");
			char labuf[8] = {0};
			if (!la)
			{
				FILE *lf = fopen("/media/fat/groovy_log_append.cfg", "r");
				if (lf)
				{
					if (fgets(labuf, sizeof(labuf), lf)) la = labuf;
					fclose(lf);
				}
			}
			if (la && la[0] == '1') logAppend = 1;
			printf("Groovy log append %d\n", logAppend);
		}
#ifdef MSG_WAITFORONE
		if (!recvBatchReady)
		{
			for (int i = 0; i < RECV_BATCH; i++)
			{
				recvIovs[i].iov_base           = recvBatchBuf[i];
				recvIovs[i].iov_len            = sizeof(recvBatchBuf[i]);
				recvMsgs[i].msg_hdr.msg_name   = &recvAddrs[i];
				recvMsgs[i].msg_hdr.msg_namelen = sizeof(recvAddrs[i]);
				recvMsgs[i].msg_hdr.msg_iov    = &recvIovs[i];
				recvMsgs[i].msg_hdr.msg_iovlen = 1;
			}
			recvBatchReady = 1;
		}
#endif

		// arm clock
		if (doARMClock)
		{
			setARMClock(doARMClock);
		}

		// reset fpga
    		groovy_FPGA_init(0, 0, 0, 0);

		// map DDR
		groovy_map_ddr();

		groovyServer = 1;
	}


    	// UDP Server
    	if (!doXDPServer)
    	{
		groovy_udp_server_init();
	}
#ifdef _AF_XDP	
	else
	{
		groovy_xdp_server_init();
	}
#endif
	if (groovyServer != 2)
	{
		goto start_error;
	}

	if (!doXDPServer && (doPs2Inputs || doJoyInputs))
	{
		groovy_udp_server_init_inputs();
	}		
	
	if (!doXDPServer)
	{
		groovy_udp_server_init_gmc();
	}	
	
	user_io_status_set(SERVER_TYPE_OPT, (uint32_t)doXDPServer);
		
	// load LOGO
	if (doScreensaver)
	{
		loadLogo(1);
		groovy_FPGA_init(1, 0, 0, 0);
		groovy_FPGA_blit();
		groovy_FPGA_logo(1);
		groovyLogo = 1;
	}

    	printf("Groovy-Server %d started\n", GROOVY_VERSION);

start_error:
    	{}
}

void groovy_stop()
{
	if (doARMClock)
	{
		setARMClock(0);
	}

	if (groovyServer == 2)
	{
		if (!doXDPServer)
		{
			LOG(0, "[UDP][%s]\n", "Closing");
			close(sockfd);
		}
#ifdef _AF_XDP
		else
		{
		
			LOG(0, "[XDP][%s]\n", "Closing");
			if (xsk_socket->xsk != NULL)
			{
				xsk_socket__delete(xsk_socket->xsk);
				LOG(0, "[XDP][%s]\n", "Closing socket");
			}
			if (umem->umem != NULL)
			{
				xsk_umem__delete(umem->umem);
				shmem_unmap(packet_buffer, packet_buffer_size);
				LOG(0, "[XDP][%s]\n", "Unmap umem");
			}
			bpf_set_link_xdp_fd(if_nametoindex("eth0"), -1, XDP_FLAGS_DRV_MODE);
			LOG(0, "[XDP][%s]\n", "Unloading xdp eth0");
			//bpf_set_link_xdp_fd(if_nametoindex("eth0"), -1, XDP_FLAGS_SKB_MODE);			
			 
		}
#endif		
		if (sockfdInputs)
		{
			LOG(0, "[UDP][%s]\n", "Closing inputs");
			close(sockfdInputs);
		}
		sockfd = 0;
		sockfdInputs = 0;		
	}
	// stop any active rumble when leaving Groovy so it can't linger on the pad
	input_rumble_player(1, 0);
	input_rumble_player(2, 0);
	printf("Groovy-Server %d stopped\n", GROOVY_VERSION);
	groovyServer = 0;
}

void groovy_poll()
{
	if (groovyServer != 2)
	{
		groovy_start();
		return;
	}

	if (isConnected && pollExitTS.tv_sec)
	{
		struct timespec hkNow;
		clock_gettime(CLOCK_MONOTONIC, &hkNow);
		double hkGapMs = diff_in_ms(&pollExitTS, &hkNow);
		hkBucket[hk_bucket(hkGapMs)]++;
		if (hkGapMs > hkGapMaxMs)
		{
			hkGapMaxMs = hkGapMs;
			groovy_FPGA_status(1);   // 4-word read, and only on a new worst case
			hkMaxVc = fpga_vga_vcount;
		}
		if (CheckTimer(hkDumpTime))
		{
			openVerboseFile(0);   // capture without turning on per-blit verbose logging
			// verbose= is the live OSD Verbose level. Only level 0 gives an undisturbed measurement:
			// at level 1 the per-blit GET_STATUS logging adds thousands of writes inside the window
			// being measured. Stamping the level into the line makes each log say for itself whether
			// the capture was clean.
			LOG(0, "[HKGAP][verbose=%d][poll-gap ms over %us][max=%06.3fms at vc=%u][<.05=%u .05-.1=%u .1-.2=%u .2-.5=%u .5-1=%u 1-2=%u 2-5=%u >=5=%u]\n",
			    doVerbose, HK_DUMP_MS / 1000, hkGapMaxMs, hkMaxVc,
			    hkBucket[0], hkBucket[1], hkBucket[2], hkBucket[3],
			    hkBucket[4], hkBucket[5], hkBucket[6], hkBucket[7]);
			memset(hkBucket, 0, sizeof(hkBucket));
			hkDumpTime = GetTimer(HK_DUMP_MS);
		}
	}


	// Verbose is the one OSD option honoured live. The rest stay latched at server start
	// (the "Save and reload to apply!" line in CONF_STR) because they gate socket creation,
	// but logging has to be switchable while a fault is actually happening. Rate-limited
	// because user_io_status_get() sscanf()s the bit spec, and this loop is hot.
	if (CheckTimer(verboseTime))
	{
		doVerbose = (int) user_io_status_get(VERBOSE_OPT);
		verboseTime = GetTimer(VERBOSE_POLL_TIMER);
	}

	// client->server traffic on the inputs socket, one non-blocking sweep per
	// poll. Address-aware: len==1 is an input (re)subscribe, which refreshes
	// the stored client address so the joystick and ps2 streams always follow
	// the current client. A reconnecting client with a fresh source port was
	// previously stuck behind the one-shot CMD_INIT read, and the old
	// rumble-only sweep consumed re-subscribes without updating the address.
	// len==4 is rumble, CAP_RUMBLE sessions only.
	if (isConnected && (doJoyInputs || doPs2Inputs) && !doXDPServer)
	{
		// Caps is the only session-level gate: per-pad enable lives in the
		// Controllers page (input.cpp groovy_get_prumble, default on) and the
		// global kill switch is MiSTer.ini RUMBLE, both applied downstream in
		// input_rumble_player().
		const uint8_t rumbleOff = (clientCaps & CAP_RUMBLE) ? 0 : 1;
		unsigned char rbuf[8];
		int rlen;
		struct sockaddr_in fromInputs;
		socklen_t fromLen;
		for (;;)
		{
			fromLen = sizeof(fromInputs);
			rlen = (int) recvfrom(sockfdInputs, (char *) rbuf, sizeof(rbuf), MSG_DONTWAIT, (struct sockaddr *)&fromInputs, &fromLen);
			if (rlen <= 0)
			{
				break;
			}
			if (rlen == 1)
			{
				memcpy(&clientaddrInputs, &fromInputs, sizeof(clientaddrInputs));
				isConnectedInputs = 1;
			}
			else if (rlen == 4 && !rumbleOff)
			{
				// [0]=player(0/1) [1]=strong [2]=weak [3]=reserved
				input_rumble_player(rbuf[0] + 1, (uint16_t)((rbuf[1] << 8) | rbuf[2]));
				LOG(2, "[RUMBLE][%d][strong=%d weak=%d]\n", rbuf[0], rbuf[1], rbuf[2]);
			}
		}
	}

	do
	{
		uint8_t gotData = 0;   // idle-timeout: did THIS iteration receive a datagram? (UDP path)
		if (doVerbose == 3 && isConnected && poc->PoC_bytes_len > 0)
		{
			groovy_FPGA_status(0);
			//LOG(3, "[GET_STATUS][DDR fr=%d bl=%d][GPU vc=%d fr=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 state_1=%d inf=%d wr=%d, run=%d resume=%d t1=%d t2=%d cmd_fskip=%d stop=%d AB=%d com=%d grav=%d lleg=%d, sub=%d blit=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_state, fpga_lz4_uncompressed, fpga_lz4_writed, fpga_lz4_run, fpga_lz4_resume, fpga_lz4_test1, fpga_lz4_test2, fpga_lz4_cmd_fskip, fpga_lz4_stop, fpga_lz4_ABCD, fpga_lz4_compressed, fpga_lz4_gravats, fpga_lz4_llegits, fpga_lz4_subframe_bytes, fpga_lz4_subframe_blit);
			LOG(3, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 un=%d][DBG %04x %04x %04x %04x]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_uncompressed, fpga_dbg_live_a, fpga_dbg_live_b, fpga_dbg_frz_a, fpga_dbg_frz_b);
		}

		if (!doXDPServer)
		{
#ifdef MSG_WAITFORONE
			if (recvMode == 2)
			{
				// mode 2: drain everything queued in one syscall. Per-message processing keeps
				// the exact legacy ordering and semantics, with commands, ACKs and completion
				// notifies running inline; only the per-chunk watermark notify is deferred to
				// one per batch.
				for (int i = 0; i < RECV_BATCH; i++) recvMsgs[i].msg_hdr.msg_namelen = sizeof(recvAddrs[i]);
				int n = recvmmsg(sockfd, recvMsgs, RECV_BATCH, MSG_WAITFORONE, NULL);
				if (n > 0) gotData = 1;
				uint8_t gotPayload = 0;
				recvNotifyDefer = 1;
				for (int i = 0; i < n; i++)
				{
					int mlen = (int) recvMsgs[i].msg_len;
					char *mptr = recvBatchBuf[i];
					memcpy(&clientaddr, &recvAddrs[i], sizeof(clientaddr));   // legacy: peer refreshed per packet (ACK dest)
					if (isBlitting && mlen > 0)
					{
						ddr_wide_copy((char *) (buffer + HEADER_OFFSET + poc->PoC_buffer_offset + poc->PoC_bytes_recv), mptr, mlen);
						gotPayload = 1;
					}
					process_packet(mptr, mlen);
				}
				recvNotifyDefer = 0;
				if (gotPayload && isBlitting == 1 && !hpsBlit)
				{
					// one ASAP watermark notify per batch (mid-frame only; the exact final
					// watermark still goes out inline from setBlit*'s completion path)
					numBlit++;
					if (blitCompression) groovy_FPGA_blit_lz4(poc->PoC_bytes_recv, numBlit);
					else                 groovy_FPGA_blit(poc->PoC_bytes_recv, numBlit);
				}
			}
			else
#endif
			if (recvMode == 1 && isBlitting)
			{
				// mode 1: cached bounce plus wide-store copy. Protocol-identical to mode 0,
				// with the same per-chunk notifies; only the payload's route into the window changes.
				int len = recvfrom(sockfd, (char *) &recvbuf[0], 65536, 0, (struct sockaddr *)&clientaddr, &clilen);
				if (len > 0) gotData = 1;
				if (len > 0)
					ddr_wide_copy((char *) (buffer + HEADER_OFFSET + poc->PoC_buffer_offset + poc->PoC_bytes_recv), (char *) &recvbuf[0], len);
				process_packet((char *) &recvbuf[0], len);
			}
			else
			{
				// mode 0 / idle: the legacy path (commands always land in recvbuf)
				char* recvbufPtr = (isBlitting) ? (char *) (buffer + HEADER_OFFSET + poc->PoC_buffer_offset + poc->PoC_bytes_recv) : (char *) &recvbuf[0];
				int len = recvfrom(sockfd, recvbufPtr, 65536, 0, (struct sockaddr *)&clientaddr, &clilen);
				if (len > 0) gotData = 1;
				process_packet(recvbufPtr, len);
			}
		}
#ifdef _AF_XDP
		else
		{
			handle_receive_packets(xsk_socket);
			gotData = 1;   // XDP: leave the idle close to the once-per-poll housekeeping check (see R7)
		}
#endif
		// Mid-blit spin escape: a client that dies part-way through a frame leaves isCorePriority
		// set and this non-blocking loop spins hot. Abandon the partial frame and leave the loop.
		// It deliberately does NOT close the session - doing that here is what let a merely paused
		// client come back to a torn-down session and drive the blit path from its stale state.
		// gotData excludes a healthy inter-chunk gap; isBlitting keeps this to the case it is for.
		if (!gotData && isBlitting && idleTimeoutMs && isConnected && CheckTimer(idleDeadline))
		{
			LOG(0, "[BLIT_ABANDON][no client activity %ums][isBlitting=%d isCorePriority=%d]\n", idleTimeoutMs, isBlitting, isCorePriority);
			if (fp) fflush(fp);   // flush the diagnostic before unwinding, the end-of-poll flush may not run
			isBlitting     = 0;   // drop the incomplete frame; the session stays up
			isCorePriority = 0;
			break;
		}
	} while (isCorePriority);

	if (doScreensaver && groovyLogo)
	{
		loadLogo(0);
	}

	// idle timeout (once per poll). Two separate jobs, and they are NOT gated alike:
	//   * the deadline refresh runs for EVERY client. idleDeadline is written only here and in
	//     setInit(), and the mid-blit escape above reads it, so a client whose deadline stops
	//     advancing sits permanently expired and has every frame abandoned part-way through.
	//   * the close is licensed by CAP_KEEPALIVE alone: only a client that promised keepalives
	//     may be reaped for going quiet. GroovyMAME sends no caps byte and has no keepalive, so
	//     it can sit paused indefinitely, which is what stock Groovy does for every client.
	// A client that is alive but not blitting refreshes the deadline with any datagram.
	if (isConnected && idleTimeoutMs)
	{
		if (sawActivity)
		{
			idleDeadline = GetTimer(idleTimeoutMs);
			sawActivity = 0;
		}
		else if ((clientCaps & CAP_KEEPALIVE) && CheckTimer(idleDeadline))
		{
			LOG(0, "[TIMEOUT][no client activity %ums][isBlitting=%d isCorePriority=%d][housekeeping]\n", idleTimeoutMs, isBlitting, isCorePriority);
			if (fp) fflush(fp);
			setClose();
		}
	}

	clock_gettime(CLOCK_MONOTONIC, &pollExitTS);   // start of the housekeeping gap

	// Flush whenever the file is open, not only when verbose is on. The probes open it
	// themselves so they work with Verbose off, and at that level they write a few KB across a
	// whole run, under the stdio buffer threshold, so nothing ever reached disk and the log was
	// empty when the process was killed.
	if (fp && CheckTimer(logTime))
   	{
		fflush(fp);
		logTime = GetTimer(LOG_TIMER);
   	}

}

void groovy_send_joystick(unsigned char joystick, uint32_t map)
{
	poc->PoC_joystick_order++;
	if (joystick == 0)
	{
		poc->PoC_joystick_map1 = map;
	}
	if (joystick == 1)
	{
		poc->PoC_joystick_map2 = map;
	}

	if (isConnectedInputs && doJoyInputs)
	{
		groovy_send_joysticks();
		LOG(2, "[JOY_ACK][%d][map=%d]\n", joystick, map);
	}
	else
	{
		LOG(2, "[JOY][%d][map=%d]\n", joystick, map);
	}
}

void groovy_send_analog(unsigned char joystick, unsigned char analog, char valueX, char valueY)
{
	poc->PoC_joystick_order++;
	if (joystick == 0)
	{
		if (analog == 0)
		{
			poc->PoC_joystick_l_analog_X1 = valueX;
			poc->PoC_joystick_l_analog_Y1 = valueY;
		}
		else
		{
			poc->PoC_joystick_r_analog_X1 = valueX;
			poc->PoC_joystick_r_analog_Y1 = valueY;
		}
	}
	if (joystick == 1)
	{
		if (analog == 0)
		{
			poc->PoC_joystick_l_analog_X2 = valueX;
			poc->PoC_joystick_l_analog_Y2 = valueY;
		}
		else
		{
			poc->PoC_joystick_r_analog_X2 = valueX;
			poc->PoC_joystick_r_analog_Y2 = valueY;
		}
	}

	if (isConnectedInputs && doJoyInputs == 2)
	{
		groovy_send_joysticks();
		LOG(2, "[JOY_%s_ACK][%d][x=%d,y=%d]\n", (analog) ? "R" : "L", joystick, valueX, valueY);
	}
	else
	{
		LOG(2, "[JOY_%s][%d][x=%d,y=%d]\n", (analog) ? "R" : "L", joystick, valueX, valueY);
	}
}

void groovy_send_trigger(unsigned char joystick, unsigned char right, unsigned char value)
{
	poc->PoC_joystick_order++;
	if (joystick == 0)
	{
		if (right) poc->PoC_joystick_r_trigger1 = value;
		else       poc->PoC_joystick_l_trigger1 = value;
	}
	if (joystick == 1)
	{
		if (right) poc->PoC_joystick_r_trigger2 = value;
		else       poc->PoC_joystick_l_trigger2 = value;
	}

	if (isConnectedInputs && doJoyInputs == 2 && (clientCaps & CAP_INPUTS_V2))
	{
		groovy_send_joysticks();
		LOG(2, "[JOY_T%s_ACK][%d][v=%d]\n", (right) ? "R" : "L", joystick, value);
	}
	else
	{
		LOG(2, "[JOY_T%s][%d][v=%d]\n", (right) ? "R" : "L", joystick, value);
	}
}

void groovy_send_keyboard(uint16_t key, int press)
{
	poc->PoC_ps2_order++;
	int index = key2sdl[key];
	int bit = 1 & (poc->PoC_ps2_keyboard_keys[index / 8] >> (index % 8));
	if (bit)
	{
		if (!press)
		{
			poc->PoC_ps2_keyboard_keys[index / 8] ^= 1 << (index % 8);
		}
	}
	else
	{
		if (press)
		{
			poc->PoC_ps2_keyboard_keys[index / 8] ^= 1 << (index % 8);
		}
	}

	if (isConnectedInputs && doPs2Inputs)
	{
		groovy_send_ps2();
		LOG(2, "[KBD_ACK][key=%d sdl=%d (%d->%d)]\n", key, index, bit, press);
	}
	else
	{
		LOG(2, "[KBD][key=%d sdl=%d (%d->%d)]\n", key, index, bit, press);
	}
}

void groovy_send_mouse(unsigned char ps2, unsigned char x, unsigned char y, unsigned char z)
{
	bitByte bits;
	bits.byte = ps2;
	poc->PoC_ps2_order++;
	poc->PoC_ps2_mouse = ps2;
	poc->PoC_ps2_mouse_x = x;
	poc->PoC_ps2_mouse_y = y;
	poc->PoC_ps2_mouse_z = z;
	if (isConnectedInputs && doPs2Inputs == 2)
	{
		groovy_send_ps2();
		LOG(2, "[MIC_ACK][yo=%d,xo=%d,ys=%d,xs=%d,1=%d,bm=%d,br=%d,bl=%d][x=%d,y=%d,z=%d]\n", bits.u.bit7, bits.u.bit6, bits.u.bit5, bits.u.bit4, bits.u.bit3, bits.u.bit2, bits.u.bit1, bits.u.bit0, x , y , z);
	}
	else
	{
		LOG(2, "[MIC][yo=%d,xo=%d,ys=%d,xs=%d,1=%d,bm=%d,br=%d,bl=%d][x=%d,y=%d,z=%d]\n", bits.u.bit7, bits.u.bit6, bits.u.bit5, bits.u.bit4, bits.u.bit3, bits.u.bit2, bits.u.bit1, bits.u.bit0, x , y , z);
	}
}

void groovy_user_io_file_gmc(const char* name)
{		
#ifndef _AF_XDP		
	if (!isConnectedGMC)
	{					
		int len = recvfrom(sockfdGMC, recvbuf, 1, 0, (struct sockaddr *)&clientaddrGMC, &clilen);
		if (len > 0)
		{
			char hoststr[NI_MAXHOST];
			char portstr[NI_MAXSERV];			
			getnameinfo((struct sockaddr *)&clientaddrGMC, clilen, hoststr, sizeof(hoststr), portstr, sizeof(portstr), NI_NUMERICHOST | NI_NUMERICSERV);
			LOG(1,"[GMC][%s:%s]\n", hoststr, portstr);  			
			isConnectedGMC = 1;
		}					
	}
#endif	
	LOG(0,"[GMC][%s]\n", name); 
	size_t fSize = 0;
	char* sendbufPtr = (doXDPServer) ? (char*) &sendbufGMC[42] : (char*) &sendbufGMC[0];
	fSize = FileLoad(name, sendbufPtr, 65536);	

    	if (isConnectedGMC)
    	{
    		LOG(2, "[GMC][Send]%s\n", sendbufPtr);
    		if (!doXDPServer)
    		{
    			sendto(sockfdGMC, sendbufPtr, fSize, 0, (struct sockaddr *)&clientaddrGMC, clilen);
    		}	
#ifdef _AF_XDP
		else
		{
			//struct ethhdr *eth = (struct ethhdr *)(sendbufInputs);
			struct iphdr *iph = (struct iphdr *)(sendbufGMC + sizeof(struct ethhdr));
			struct udphdr *udph = (struct udphdr *)(sendbufGMC + sizeof(struct ethhdr) + (iph->ihl * 4));
			int ret = 0;
			uint32_t tx_idx = 0;
			uint64_t addr = 0;
			ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
			if (ret != 1) {
				// No more transmit slots, drop the packet
				LOG(0, "[ACK_%s][Failed]\n", "STATUS");
				return;
			}	
			iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + fSize);
			update_iph_checksum(iph);
			udph->check = 0;
			udph->len = htons(fSize + sizeof(struct udphdr));
			uint32_t udph_sum = sum_udp_checksum(iph, udph->len); 						
			compute_udp_checksum((unsigned short *)udph, udph_sum);																				
			addr = xsk_socket->umem_frame_addr[xsk_socket->outstanding_tx];
			memcpy(xsk_umem__get_data(xsk_socket->umem->buffer, addr), sendbufGMC, 42 + fSize);
			xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->addr = addr;
			xsk_ring_prod__tx_desc(&xsk_socket->tx, tx_idx)->len = 42 + fSize;
			xsk_ring_prod__submit(&xsk_socket->tx, 1);
			xsk_socket->outstanding_tx++;
	
			complete_tx(xsk_socket);			
		}
#endif    		
    	}
    	else
    	{
    		LOG(2, "[GMC][Read]%s\n", sendbufPtr);
    	}
    	
}




     