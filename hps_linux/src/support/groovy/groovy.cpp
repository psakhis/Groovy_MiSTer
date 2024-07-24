
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <time.h>
#include <cstring>

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
#include <sched.h>
#include <netinet/udp.h>
#include <netinet/ip.h>
#include <netinet/ether.h>
#include <linux/if_link.h> //DRV_MODE
#endif

#include "../../hardware.h"
#include "../../shmem.h"
#include "../../spi.h"

#include "logo.h"
#include "pll.h"
#include "utils.h"

// FPGA SPI commands
#define UIO_GET_GROOVY_STATUS     0xf0
#define UIO_GET_GROOVY_HPS        0xf1
#define UIO_SET_GROOVY_INIT       0xf2
#define UIO_SET_GROOVY_SWITCHRES  0xf3
#define UIO_SET_GROOVY_BLIT       0xf4
#define UIO_SET_GROOVY_LOGO       0xf5
#define UIO_SET_GROOVY_AUDIO      0xf6
#define UIO_SET_GROOVY_BLIT_LZ4   0xf7

// FPGA DDR shared
#define BASEADDR 0x1C000000
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
#define BUFFERSIZE FRAMEBUFFER_SIZE + AUDIO_SIZE + LZ4_SIZE + LZ4_SIZE + HEADER_LEN

// UDP server
#define UDP_PORT 32100
#define UDP_PORT_INPUTS 32101

#ifdef _AF_XDP
// XDP server
#define XDP_BASEADDR 0x15000000
#define XDP_NUM_FRAMES 65536 			     // pot 2 (min.4096)
#define XDP_FRAME_SIZE XSK_UMEM__DEFAULT_FRAME_SIZE
#define RX_BATCH_SIZE 64		     	     
#define INVALID_UMEM_FRAME UINT64_MAX
#endif

// GroovyMiSTer protocol
#define CMD_CLOSE 1
#define CMD_INIT 2
#define CMD_SWITCHRES 3
#define CMD_AUDIO 4
#define CMD_GET_STATUS 5
#define CMD_BLIT_VSYNC 6



//https://stackoverflow.com/questions/64318331/how-to-print-logs-on-both-console-and-file-in-c-language
#define LOG_TIMER 25
#define LOGO_TIMER 16
#define KEEP_ALIVE_FRAMES 45 * 60

static struct timespec logTS, logTS_ant, blitStart, blitStop;
static int doVerbose = 0;
static double difMs = 0;
static unsigned long logTime = 0;
static FILE * fp = NULL;

#define LOG(sev,fmt, ...) do {	\
			        if (sev == 0) printf(fmt, __VA_ARGS__);	\
			        if (sev <= doVerbose) { \
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

#ifdef _AF_XDP
static uint32_t inputs_ip_check_9 = 0;
static uint32_t inputs_ip_check_17 = 0;
static uint32_t inputs_ip_check_37 = 0;
static uint32_t inputs_ip_check_41 = 0;
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
static uint8_t audioRate = 0;
static uint8_t audioChannels = 0;
static uint8_t rgbMode = 0;

static int isBlitting = 0;
static int isCorePriority = 0;

static uint8_t hpsBlit = 0;
static uint16_t numBlit = 0;
static uint8_t doScreensaver = 0;
static uint8_t doPs2Inputs = 0;
static uint8_t doJoyInputs = 0;
static uint8_t doJumboFrames = 0;
static uint8_t doXDPServer = 0;
static uint8_t doARMClock = 0;
static uint8_t isConnected = 0;
static uint8_t isConnectedInputs = 0;


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
static uint8_t  fpga_lz4_AB = 0;
static uint8_t  fpga_lz4_cmd_fskip = 0;
static uint32_t fpga_lz4_compressed = 0;
static uint32_t fpga_lz4_gravats = 0;
static uint32_t fpga_lz4_llegits = 0;
static uint32_t fpga_lz4_subframe_bytes = 0;
static uint16_t fpga_lz4_subframe_blit = 0;
*/

static inline void initDDR()
{
	memset(&buffer[0],0x00,0xff);
}


static void initVerboseFile()
{
	fp = fopen("/tmp/groovy.log", "wt");
	if (!fp)
	{
		LOG(0, "groovy.log %s\n", "error");
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
    uint16_t req = 0;
    EnableIO();
    do
    {
    	req = fpga_spi_fast(UIO_GET_GROOVY_HPS);
    } while (req == 0);
    uint16_t hps = spi_w(0);
    DisableIO();
    bitByte bits;
    bits.byte = (uint8_t) hps;

    if (bits.u.bit0 == 1 && bits.u.bit1 == 0) doVerbose = 1;
    else if (bits.u.bit0 == 0 && bits.u.bit1 == 1) doVerbose = 2;
    else if (bits.u.bit0 == 1 && bits.u.bit1 == 1) doVerbose = 3;
    else doVerbose = 0;

    initVerboseFile();
    hpsBlit = bits.u.bit2;
    doScreensaver = !bits.u.bit3;

    if (bits.u.bit4 == 1 && bits.u.bit5 == 0) doPs2Inputs = 1;
    else if (bits.u.bit4 == 0 && bits.u.bit5 == 1) doPs2Inputs = 2;
    else doPs2Inputs = 0;

    if (bits.u.bit6 == 1 && bits.u.bit7 == 0) doJoyInputs = 1;
    else if (bits.u.bit6 == 0 && bits.u.bit7 == 1) doJoyInputs = 2;
    else doJoyInputs = 0;

    bits.byte = (uint8_t) ((hps & 0xFF00) >> 8);
    doJumboFrames = bits.u.bit0;
    doXDPServer = bits.u.bit1;
    doARMClock = (bits.u.bit2) ? 1 : (bits.u.bit3) ? 2 : 0;

    LOG(0, "[HPS][doVerbose=%d hpsBlit=%d doScreenSaver=%d doPs2Inputs=%d doJoyInputs=%d doJumboFrames=%d doXDPServer=%d doARMClock=%d]\n", doVerbose, hpsBlit, doScreensaver, doPs2Inputs, doJoyInputs, doJumboFrames, doXDPServer, doARMClock);
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
			fpga_vga_vcount = poc->PoC_V_Total;
		}
		else
		{
			fpga_vga_vcount = poc->PoC_V_Total - 1;
		}
	}
	else
	{
		fpga_vga_vcount = poc->PoC_V_Total;
	}
    }

    if (!isACK)
    {
    	fpga_vram_queue |= spi_w(0) << 8; //24b
    	fpga_vram_pixels = spi_w(0) | spi_w(0) << 16;

	if (blitCompression)
	{
		fpga_lz4_uncompressed  = spi_w(0) | spi_w(0) << 16;
	}

		/* DEBUG
			fpga_lz4_state = spi_w(0);
			fpga_lz4_writed = spi_w(0) | spi_w(0) << 16;

			uint16_t wordlz4 = spi_w(0);

			bits.byte = (uint8_t) wordlz4;
			fpga_lz4_cmd_fskip = bits.u.bit6;
			fpga_lz4_AB = bits.u.bit5;
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
    spi_w(1);
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

static void groovy_FPGA_blit_lz4(uint32_t compressed_bytes)
{
    uint16_t req = 0;
    EnableIO();
    do
    {
 	req = fpga_spi_fast(UIO_SET_GROOVY_BLIT_LZ4);
    } while (req == 0);
    uint16_t lz4_zone = (poc->PoC_field_lz4) ? 0 : 1;
    spi_w(lz4_zone);
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
    spi_w(cmd);
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

    	groovy_FPGA_blit_lz4(poc->PoC_bytes_lz4_len);
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

    LOG(1,"[Modeline] %f %d %d %d %d %d %d %d %d %s(%d)\n",udp_pclock,udp_hactive,udp_hbegin,udp_hend,udp_htotal,udp_vactive,udp_vbegin,udp_vend,udp_vtotal,udp_interlace?"interlace":"progressive",udp_interlace);

    poc->PoC_pixels_ddr = 0;
    poc->PoC_H = udp_hactive;
    poc->PoC_HFP = udp_hbegin - udp_hactive;
    poc->PoC_HS = udp_hend - udp_hbegin;
    poc->PoC_HBP = udp_htotal - udp_hend;
    poc->PoC_V = udp_vactive;
    poc->PoC_VFP = udp_vbegin - udp_vactive;
    poc->PoC_VS = udp_vend - udp_vbegin;
    poc->PoC_VBP = udp_vtotal - udp_vend;

    poc->PoC_ce_pix = (udp_pclock * 16 < 90) ? 16 : (udp_pclock * 12 < 90) ? 12 : (udp_pclock * 8 < 90) ? 8 : (udp_pclock * 6 < 90) ? 6 : 4;	// we want at least 40Mhz clksys for vga scaler

    poc->PoC_interlaced = (udp_interlace >= 1) ? 1 : 0;
    poc->PoC_FB_progressive = (udp_interlace == 0 || udp_interlace == 2) ? 1 : 0;

    poc->PoC_field_frame = poc->PoC_frame_ddr + 1;
    poc->PoC_field = 0;

    int M=0;
    int C=0;
    int K=0;

    getMCK_PLL_Fractional(udp_pclock*poc->PoC_ce_pix,M,C,K);
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

    LOG(1,"[FPGA header] %d %d %d %d %d %d %d %d ce_pix=%d PLL(M0=%d,M1=%d,C0=%d,C1=%d,K=%d) \n",poc->PoC_H,poc->PoC_HFP, poc->PoC_HS,poc->PoC_HBP,poc->PoC_V,poc->PoC_VFP, poc->PoC_VS,poc->PoC_VBP,poc->PoC_ce_pix,poc->PoC_pll_M0,poc->PoC_pll_M1,poc->PoC_pll_C0,poc->PoC_pll_C1,poc->PoC_pll_K);

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
	numBlit = 0;
	blitCompression = 0;
	free(poc);
	initDDR();
	isConnected = 0;
	isConnectedInputs = 0;

	// load LOGO
	if (doScreensaver)
	{
		loadLogo(1);
		groovy_FPGA_init(1, 0, 0, 0);
		groovy_FPGA_blit();
		groovy_FPGA_logo(1);
		groovyLogo = 1;
	}

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
	int len = 9;
	sendbufPtr[0] = poc->PoC_frame_ddr & 0xff;
	sendbufPtr[1] = poc->PoC_frame_ddr >> 8;
	sendbufPtr[2] = poc->PoC_frame_ddr >> 16;
	sendbufPtr[3] = poc->PoC_frame_ddr >> 24;
	sendbufPtr[4] = poc->PoC_joystick_order;
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
		iph->check = (len == 9) ? inputs_ip_check_9 : inputs_ip_check_17;
		udph->len = htons(len + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + len);
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
		iph->check = (len == 37) ? inputs_ip_check_37 : inputs_ip_check_41;
		udph->len = htons(len + sizeof(struct udphdr));
		iph->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + len);
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
		//struct iphdr *iph = (struct iphdr *)(sendbuf + sizeof(struct ethhdr));
		//struct udphdr *udph = (struct udphdr *)(sendbuf + sizeof(struct ethhdr) + (iph->ihl * 4));
		int ret = 0;
		uint32_t tx_idx = 0;
		uint64_t addr = 0;
		ret = xsk_ring_prod__reserve(&xsk_socket->tx, 1, &tx_idx);
		if (ret != 1) {
			// No more transmit slots, drop the packet
			LOG(0, "[ACK_%s][Failed]\n", "STATUS");
			return;
		}
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
	blitCompression = (compression <= 1) ? compression : 0;
	audioRate = (audio_rate <= 3) ? audio_rate : 0;
	audioChannels = (audio_chan <= 2) ? audio_chan : 0;
	rgbMode = (rgb_mode <= 2) ? rgb_mode : 0;
	poc = (PoC_type *) calloc(1, sizeof(PoC_type));
	initDDR();
	isBlitting = 0;
	numBlit = 0;


	char hoststr[NI_MAXHOST];
	char portstr[NI_MAXSERV];
	// load LOGO
	if (doScreensaver)
	{
		groovy_FPGA_init(0, 0, 0, 0);
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
  			len = recvfrom(sockfdInputs, recvbuf, 1, 0, (struct sockaddr *)&clientaddrInputs, &clilen);
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

	groovy_FPGA_init(1, audioRate, audioChannels, rgbMode);
}

static void setBlit(uint32_t udp_frame, uint32_t udp_lz4_size)
{
	poc->PoC_frame_recv = udp_frame;
	poc->PoC_bytes_recv = 0;
	poc->PoC_bytes_lz4_ddr = 0;
	poc->PoC_bytes_lz4_len = (blitCompression) ? udp_lz4_size : 0;
	poc->PoC_field = (!poc->PoC_FB_progressive) ? (poc->PoC_frame_recv + poc->PoC_field_frame) % 2 : 0;
	poc->PoC_buffer_offset = (blitCompression) ? (poc->PoC_field_lz4) ? LZ4_OFFSET_B : LZ4_OFFSET_A : (!poc->PoC_FB_progressive && poc->PoC_field) ? FIELD_OFFSET : 0;
	poc->PoC_field_lz4 = (blitCompression) ? !poc->PoC_field_lz4 : 0;
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

	isBlitting = 1;
	isCorePriority = 1;
	numBlit = 0;

	if (!hpsBlit) //ASAP fpga starts to poll ddr
	{
		if (blitCompression)
		{
			groovy_FPGA_blit_lz4(0, 0);
		}
		else
		{
			groovy_FPGA_blit(0, 0);
		}
	}
	else
	{
		poc->PoC_pixels_ddr = 0;
		poc->PoC_bytes_lz4_ddr = 0;
	}

	if (doVerbose > 0 && doVerbose < 3)
	{
		groovy_FPGA_status(0);
		LOG(1, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][AUDIO=%d][LZ4 inf=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_audio, fpga_lz4_uncompressed);
	}

	if (!doVerbose && !fpga_vram_synced)
 	{
 		groovy_FPGA_status(0);
 		LOG(0, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][AUDIO=%d][LZ4 inf=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_audio, fpga_lz4_uncompressed);
 	}	
	clock_gettime(CLOCK_MONOTONIC, &blitStart);
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

       	if (!hpsBlit) //ASAP
       	{
       		numBlit++;
		groovy_FPGA_blit(poc->PoC_bytes_recv, numBlit);
		LOG(2, "[ACK_BLIT][(%d) px=%d/%d %d/%d]\n", numBlit, poc->PoC_pixels_ddr, poc->PoC_pixels_len, poc->PoC_bytes_recv, poc->PoC_bytes_len);
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

	if (!hpsBlit) //ASAP
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
}

#ifdef _AF_XDP
static struct xsk_umem_info *configure_xsk_umem(void *buffer, uint64_t size)
{
	struct xsk_umem_info *umem;
	int ret;

	umem = (xsk_umem_info*) calloc(1, sizeof(*umem));
	if (!umem)
	{
		LOG(0, "[XPD][configure_xsk_umem:calloc][%s]\n", "error");
		return NULL;
	}

	ret = xsk_umem__create(&umem->umem, buffer, size, &umem->fq, &umem->cq, NULL);
	if (ret)
	{
		LOG(0, "[XPD][configure_xsk_umem:xsk_umem__create][%s]\n", "error");
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
	//int sock_opt;

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
	//xsk_cfg.bind_flags = XDP_USE_NEED_WAKEUP | XDP_ZEROCOPY; ////zc + recvfrom/sendto to wakeup and avoid softirqs UNSTABLE		
	xsk_cfg.bind_flags = XDP_COPY;

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

        sock_opt = 64;
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
	int packet_buffer_size, pagesize, map_start, map_off;
	void *packet_buffer;
	struct bpf_map *map;
	struct rlimit rlim = {RLIM_INFINITY, RLIM_INFINITY};	
	struct bpf_object *obj;
	int prog_fd;
	struct bpf_prog_load_attr prog_load_attr;
//	struct xdp_multiprog *mp = NULL;	

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
    	packet_buffer_size = XDP_NUM_FRAMES * XDP_FRAME_SIZE;
    	packet_buffer = shmem_map_private(map_start, packet_buffer_size+map_off);
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

	LOG(0, "[XDP][STARTED][%s]\n", "0.4");

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

	LOG(0, "[UDP][STARTED][%s]\n", "0.4");
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

static inline void process_packet(char *recvbufPtr, int len)
{
	if (len > 0)
	{
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
    			switch (recvbufPtr[0])
    			{
	    			case CMD_CLOSE:
				{
					if (len == 1)
					{
						LOG(1, "[CMD_CLOSE][%d]\n", recvbufPtr[0]);
						setClose();
					}
				}; break;

				case CMD_INIT:
				{
					if (len == 4 || len == 5)
					{
						if (doVerbose)
						{
							initVerboseFile();
						}
						uint8_t compression = recvbufPtr[1];
						uint8_t audio_rate = recvbufPtr[2];
						uint8_t audio_channels = recvbufPtr[3];
						uint8_t rgb_mode = (len == 5) ? recvbufPtr[4] : 0;
						setInit(compression, audio_rate, audio_channels, rgb_mode);
						sendACK(0, 0);
						LOG(1, "[CMD_INIT][%d][LZ4=%d][Audio rate=%d chan=%d][%s]\n", recvbufPtr[0], compression, audio_rate, audio_channels, (rgb_mode == 1) ? "RGBA888" : (rgb_mode == 2) ? "RGB565" : "RGB888");
					}
				}; break;

				case CMD_SWITCHRES:
				{
					if (len == 26)
					{
			       			setSwitchres(&recvbufPtr[0]);
			       			LOG(1, "[CMD_SWITCHRES][%d]\n", recvbufPtr[0]);
			       		}
				}; break;

				case CMD_AUDIO:
				{
					if (len == 3)
					{
						uint16_t udp_bytes_samples = ((uint16_t) recvbufPtr[2]  << 8) | recvbufPtr[1];
						setBlitAudio(udp_bytes_samples);
						LOG(1, "[CMD_AUDIO][%d][Bytes=%d]\n", recvbufPtr[0], udp_bytes_samples);
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

				case CMD_BLIT_VSYNC:
				{
					if (len == 7 || len == 11 || len == 9)
					{
						uint32_t udp_lz4_size = 0;
						uint32_t udp_frame = ((uint32_t) recvbufPtr[4]  << 24) | ((uint32_t)recvbufPtr[3]  << 16) | ((uint32_t)recvbufPtr[2]  << 8) | recvbufPtr[1];
						uint16_t udp_vsync = ((uint16_t) recvbufPtr[6]  << 8) | recvbufPtr[5];
						if (!blitCompression)
						{
							LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d]\n", recvbufPtr[0], udp_frame, udp_vsync);
						}
				       		else if (len == 11 && blitCompression)
						{
							udp_lz4_size = ((uint32_t) recvbufPtr[10]  << 24) | ((uint32_t)recvbufPtr[9]  << 16) | ((uint32_t)recvbufPtr[8]  << 8) | recvbufPtr[7];
							LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d][CSize=%d]\n", recvbufPtr[0], udp_frame, udp_vsync, udp_lz4_size);
						}
				       		setBlit(udp_frame, udp_lz4_size);
				       		groovy_FPGA_status(1);
				       		sendACK(udp_frame, udp_vsync);
				       	}
				}; break;

				default:
				{
					LOG(1,"command: %i (len=%d)\n", recvbufPtr[0], len);
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
		udp->len = htons(13 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 13);
		update_iph_checksum(ip);

		memcpy(&sendbuf[0], &data_pointer[0], 42);
	}

	//set headers preparing send inputs
	if (!isConnectedInputs && ntohs(udp->dest) == UDP_PORT_INPUTS && (doPs2Inputs || doJoyInputs))
	{
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

		udp->dest = udp->source;
		udp->source = htons(UDP_PORT_INPUTS);

		udp->check = 0;
		
		//precalculate ip checksum headers
		udp->len = htons(9 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 9);
		update_iph_checksum(ip);
		inputs_ip_check_9 = ip->check;

		udp->len = htons(17 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 17);
		update_iph_checksum(ip);
		inputs_ip_check_17 = ip->check;

		udp->len = htons(37 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 37);
		update_iph_checksum(ip);
		inputs_ip_check_37 = ip->check;

		udp->len = htons(41 + sizeof(struct udphdr));
		ip->tot_len = htons(sizeof(iphdr) + sizeof(struct udphdr) + 41);
		update_iph_checksum(ip);
		inputs_ip_check_41 = ip->check;

		memcpy(&sendbufInputs[0], &data_pointer[0], 42);
		isConnectedInputs = 1;
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
	int ret;		
	
	rcvd = xsk_ring_cons__peek(&xsk->rx, RX_BATCH_SIZE, &idx_rx);
	if (!rcvd)
	{	//kick softirqs away (need_wakeup)
		//if (xsk_ring_prod__needs_wakeup(&xsk->umem->fq))
		//{
			//recvfrom(xsk_socket__fd(xsk->xsk), NULL, 0, MSG_DONTWAIT, NULL, NULL);			
		//}
		return;
	}
	// Stuff the ring with as much frames as possible
	stock_frames = xsk_prod_nb_free(&xsk->umem->fq, xsk_umem_free_frames(xsk));
	if (stock_frames > 0)
	{
		ret = xsk_ring_prod__reserve(&xsk->umem->fq, stock_frames, &idx_fq);

		// This should not happen, but just in case
		while (ret != stock_frames)
		{
			//if (xsk_ring_prod__needs_wakeup(&xsk->umem->fq))
			//{
				//recvfrom(xsk_socket__fd(xsk->xsk), NULL, 0, MSG_DONTWAIT, NULL, NULL);
			//}
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
		printf("Groovy-Server 0.4 starting\n");

		// get HPS Server Settings
		groovy_FPGA_hps();

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

#ifdef _AF_XDP
    	// UDP Server
    	if (!doXDPServer)
    	{
		groovy_udp_server_init();
	}
	else
	{
		groovy_xdp_server_init();
	}
#else
	doXDPServer = 0;
	groovy_udp_server_init();	
#endif
	if (groovyServer != 2)
	{
		goto start_error;
	}

	if (!doXDPServer && (doPs2Inputs || doJoyInputs))
	{
		groovy_udp_server_init_inputs();
	}

	// load LOGO
	if (doScreensaver)
	{
		loadLogo(1);
		groovy_FPGA_init(1, 0, 0, 0);
		groovy_FPGA_blit();
		groovy_FPGA_logo(1);
		groovyLogo = 1;
	}

    	printf("Groovy-Server 0.4 started\n");

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
			}
			if (umem->umem != NULL)
			{
				xsk_umem__delete(umem->umem);
			}
			bpf_set_link_xdp_fd(if_nametoindex("eth0"), -1, XDP_FLAGS_DRV_MODE);
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
	printf("Groovy-Server 0.4 stopped\n");
	groovyServer = 0;
}

void groovy_poll()
{
	if (groovyServer != 2)
	{
		groovy_start();
		return;
	}

	do
	{
		if (doVerbose == 3 && isConnected)
		{
			groovy_FPGA_status(0);
			//LOG(3, "[GET_STATUS][DDR fr=%d bl=%d][GPU vc=%d fr=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 state_1=%d inf=%d wr=%d, run=%d resume=%d t1=%d t2=%d cmd_fskip=%d stop=%d AB=%d com=%d grav=%d lleg=%d, sub=%d blit=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_state, fpga_lz4_uncompressed, fpga_lz4_writed, fpga_lz4_run, fpga_lz4_resume, fpga_lz4_test1, fpga_lz4_test2, fpga_lz4_cmd_fskip, fpga_lz4_stop, fpga_lz4_AB, fpga_lz4_compressed, fpga_lz4_gravats, fpga_lz4_llegits, fpga_lz4_subframe_bytes, fpga_lz4_subframe_blit);
			LOG(3, "[GET_STATUS][DDR fr=%d bl=%d][GPU fr=%d vc=%d fskip=%d vb=%d fd=%d][VRAM px=%d queue=%d sync=%d free=%d eof=%d][LZ4 un=%d]\n", poc->PoC_frame_ddr, numBlit, fpga_vga_frame, fpga_vga_vcount, fpga_vga_frameskip, fpga_vga_vblank, fpga_vga_f1, fpga_vram_pixels, fpga_vram_queue, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame, fpga_lz4_uncompressed);
		}

		if (!doXDPServer)
		{
			char* recvbufPtr = (isBlitting) ? (char *) (buffer + HEADER_OFFSET + poc->PoC_buffer_offset + poc->PoC_bytes_recv) : (char *) &recvbuf[0];
			int len = recvfrom(sockfd, recvbufPtr, 65536, 0, (struct sockaddr *)&clientaddr, &clilen);
			process_packet(recvbufPtr, len);
		}
#ifdef _AF_XDP		
		else
		{						
			handle_receive_packets(xsk_socket);			
		}
#endif		
	} while (isCorePriority);

	if (doScreensaver && groovyLogo)
	{
		loadLogo(0);
	}

	if (doVerbose > 0 && CheckTimer(logTime))
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






     