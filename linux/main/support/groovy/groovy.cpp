
/* UDP server */
#include <stdlib.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/udp.h>
#include <netinet/ip.h>
#include <netinet/ether.h>
#include <linux/if_packet.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/ethtool.h>
#include <linux/sockios.h>
#include <linux/net_tstamp.h>
#include <stdio.h>
#include <memory.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <signal.h>

#include <sys/time.h> 
#include <sys/stat.h>
#include <time.h>

#include <unistd.h>
#include <sched.h>
#include <inttypes.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>

#include "../../hardware.h"
#include "../../shmem.h"
#include "../../fpga_io.h"
#include "../../spi.h"

#include "zstd.h"
#include "lz4.h"
#include "pll.h"

// FPGA SPI commands 
#define UIO_GET_GROOVY_STATUS    0xf0 
#define UIO_GET_GROOVY_HPS       0xf1 
#define UIO_SET_GROOVY_INIT      0xf2
#define UIO_SET_GROOVY_SWITCHRES 0xf3
#define UIO_SET_GROOVY_BLIT      0xf4

// FPGA DDR shared
#define BASEADDR 0x30000000
#define HEADER_LEN 0xff       
#define CHUNK 7 
#define HEADER_OFFSET HEADER_LEN - CHUNK 
#define BUFFERSIZE (720 * 576 * 3) + HEADER_LEN

// UDP server 
#define UDP_INACTIVITY 5000
#define UDP_PORT 32100
#define CMD_CLOSE 1
#define CMD_INIT 2
#define CMD_SWITCHRES 3
#define CMD_BLIT 4
#define CMD_GET_STATUS 5
#define CMD_BLIT_VSYNC 6

//https://stackoverflow.com/questions/64318331/how-to-print-logs-on-both-console-and-file-in-c-language
#define LOG_TIMER 16
static struct timeval logTS, logTS_ant, blitStart, blitStop; 
static int doVerbose = 0; 
static int difUs = 0;
static unsigned long logTime = 0;
static FILE * fp = NULL;

//printf("[%06.3f]",(double) difUs/1000); 
//printf(fmt, __VA_ARGS__);	
//fprintf(fp, "[%06.3f]",(double) difUs/1000); 
//fprintf(fp, fmt, __VA_ARGS__);	

#define LOG(sev,fmt, ...) do {	\
			        if (sev == 0) printf(fmt, __VA_ARGS__);	\
			        if (sev <= doVerbose) { \
			        	gettimeofday(&logTS, NULL); 	\
			        	difUs = (difUs != 0) ? ((logTS.tv_sec - logTS_ant.tv_sec) * 1000000 + logTS.tv_usec - logTS_ant.tv_usec) : -1;	\
					fprintf(fp, "[%06.3f]",(double) difUs/1000); \
					fprintf(fp, fmt, __VA_ARGS__);	\
                                	gettimeofday(&logTS_ant, NULL); \
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
   uint16_t PoC_frame_vsync;  
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
   
   double   PoC_pclock;   
        
   //framebuffer          
   uint32_t PoC_bytes_block[6];                             
   uint32_t PoC_pixels_block[6];
   uint32_t PoC_bytes_len;               
   uint32_t PoC_pixels_len;               
   uint32_t PoC_bytes_recv;                             
   uint32_t PoC_pixels_ddr;   
   
   double PoC_width_time; 
   uint16_t PoC_V_Total;  
               
} PoC_type;

union {
    double d;
    uint64_t i;
} u;

/* General Server variables */
static int groovyServer = 0;
static int sockfd;
static struct sockaddr_in servaddr;	
static struct sockaddr_in clientaddr;
static socklen_t clilen = sizeof(struct sockaddr); 
static char recvbuf[65536] = { 0 };

static PoC_type *poc;
static uint8_t *map = 0;    
static uint8_t* buffer;

static int blitCompression = 0;

/* LZ4 Streaming */
static LZ4_streamDecode_t lz4StreamDecode_body;
static LZ4_streamDecode_t* lz4StreamDecode = &lz4StreamDecode_body;
static char decBuf[2][65536];
static int decBufIndex = 0;

static uint16_t LZ4cmpBytes = 0;
static uint16_t LZ4offset = 0;
static uint16_t LZ4blockSize = 0;

static int isBlitting = 0;

static uint8_t hpsBlit = 0; 
static uint8_t numBlit = 0;
static uint8_t doBlocks = 0;
static uint8_t doAlwaysStatus = 0;
static uint8_t doACKStatus = 0;
static uint8_t isConnected = 0; 
static unsigned long isTimeout = 0; 

/* FPGA HPS EXT STATUS */
static uint16_t fpga_vga_vcount = 0;
static uint32_t fpga_vga_frame = 0;
static uint32_t fpga_vram_pixels = 0;
static uint8_t  fpga_vram_end_frame = 0;
static uint8_t  fpga_vram_ready = 0;
static uint8_t  fpga_vram_synced = 0;
static uint8_t  fpga_vga_frameskip = 0;
static uint8_t  fpga_vga_vblank = 0;

static void initDDR()
{
	memset(&buffer[0],0x00,0xff);	  
}


static void groovy_FPGA_hps()
{
	uint8_t req = spi_uio_cmd_cont(UIO_GET_GROOVY_HPS);
	uint16_t hps = 0;
	bitByte bits;  
	bits.byte = 0;
	if (req) 
	{
		hps = spi_w(0); 						
	    	bits.byte = (uint8_t) hps; 	    
	}	
    	DisableIO(); 	
    			
	if (bits.u.bit0 == 1 && bits.u.bit1 == 0) doVerbose = 1;
	else if (bits.u.bit0 == 0 && bits.u.bit1 == 1) doVerbose = 2;
	else if (bits.u.bit0 == 1 && bits.u.bit1 == 1) doVerbose = 3;
	else doVerbose = 0;
	
	printf("doVerbose %d\n", doVerbose);
	
	//if (doVerbose > 0)
	{
		fp = fopen ("/tmp/groovy.log", "wt"); 
		if (fp == NULL)
		{
			printf("error groovy.log\n");       			
		}  	
		struct stat stats;
    		if (fstat(fileno(fp), &stats) == -1) 
    		{
        		printf("error groovy.log stats\n");        		
    		}		   		    		
    		if (setvbuf(fp, NULL, _IOFBF, stats.st_blksize) != 0)    		
    		//if (setvbuf(fp, NULL, _IOFBF, 32768) != 0)
    		{
        		printf("setvbuf failed \n");         		
    		}    		
    		logTime = GetTimer(1000);						
	}			 
	
	if (bits.u.bit2 == 1 && bits.u.bit3 == 0 && bits.u.bit4 == 0) 
	{
		hpsBlit = 0;
		doBlocks = 1;
	} 
	else if (bits.u.bit2 == 0 && bits.u.bit3 == 1 && bits.u.bit4 == 0) 	
	{
		hpsBlit = 1;
		doBlocks = 1;
	}
	else if (bits.u.bit2 == 0 && bits.u.bit3 == 0 && bits.u.bit4 == 1) 	
	{
		hpsBlit = 2;
		doBlocks = 1;
	}
	else if (bits.u.bit2 == 1 && bits.u.bit3 == 1 && bits.u.bit4 == 0) 	
	{
		hpsBlit = 3;
		doBlocks = 1;
	}
	else if (bits.u.bit2 == 1 && bits.u.bit3 == 0 && bits.u.bit4 == 1) 	
	{
		hpsBlit = 4;
		doBlocks = 1;
	}
	else if (bits.u.bit2 == 0 && bits.u.bit3 == 1 && bits.u.bit4 == 1) 	
	{
		hpsBlit = 5;
		doBlocks = 1;
	}
	else
	{
		hpsBlit = 0;
		doBlocks = 0;
	}
		
	printf("hpsBlit=%d doBlocks=%d \n", hpsBlit, doBlocks);	
}

static void groovy_FPGA_status_fast()
{	
	EnableIO();	
	uint16_t req = fpga_spi_fast(UIO_GET_GROOVY_STATUS);		
  	if (req)
  	{	  						  						  					
		fpga_vga_frame   = spi_w(0) | spi_w(0) << 16;  			  					
		fpga_vga_vcount  = spi_w(0);
		uint16_t word161 = spi_w(0);  			 
		uint16_t word162 = spi_w(0);
		uint8_t word81   = (uint8_t)((word162 & 0xFF00) >> 8);
		uint8_t word82   = (uint8_t)(word162 & 0x00FF);  			
		fpga_vram_pixels = word161 | word82 << 16; //24b
		
		bitByte bits;  
		bits.byte = word81;
		fpga_vram_ready     = bits.u.bit0;
		fpga_vram_end_frame = bits.u.bit1;
		fpga_vram_synced    = bits.u.bit2;   
		fpga_vga_frameskip  = bits.u.bit3;   
		fpga_vga_vblank     = bits.u.bit4;   		
		
		if (!fpga_vga_vcount)
		{
			fpga_vga_vcount = poc->PoC_V_Total;
		}
								
  	}  		  		
    	DisableIO(); 	
}

static void groovy_FPGA_status()
{
	uint16_t req = 0;		
  	while (req == 0)
  	{
  		req = spi_uio_cmd_cont(UIO_GET_GROOVY_STATUS);
  		if (req)
  		{  		  			
  			fpga_vga_frame   = spi_w(0) | spi_w(0) << 16;  	  			
	 		fpga_vga_vcount  = spi_w(0);  						  			
  			uint16_t word161 = spi_w(0);  			 
  			uint16_t word162 = spi_w(0);
  			uint8_t word81   = (uint8_t)((word162 & 0xFF00) >> 8);
			uint8_t word82   = (uint8_t)(word162 & 0x00FF);  			
  			fpga_vram_pixels = word161 | word82 << 16; //24b
  			
  			bitByte bits;  
			bits.byte = word81;
			fpga_vram_ready     = bits.u.bit0;
			fpga_vram_end_frame = bits.u.bit1;
			fpga_vram_synced    = bits.u.bit2;  
			fpga_vga_frameskip  = bits.u.bit3;   
			fpga_vga_vblank     = bits.u.bit4;   		
			
			if (!fpga_vga_vcount)
			{
				fpga_vga_vcount = poc->PoC_V_Total;
			}												
  		}  		
  	}	
    	DisableIO(); 	
}

static void groovy_FPGA_switchres()
{	
    uint16_t req = 0;
    while (req == 0)
    {
	req = spi_uio_cmd_cont(UIO_SET_GROOVY_SWITCHRES);	
	if (req) spi_w(1);
    }	
    DisableIO();        
}

static void groovy_FPGA_blit()
{	
    uint16_t req = 0;
    EnableIO();	
    while (req == 0)
    {
	//req = spi_uio_cmd_cont(UIO_SET_GROOVY_BLIT);		
	req = fpga_spi_fast(UIO_SET_GROOVY_BLIT);	
	if (req) spi_w(1);
    }	
    DisableIO();        
}

static void groovy_FPGA_init(int cmd)
{
	uint16_t req = 0;
	while (req == 0)
	{
		req = spi_uio_cmd_cont(UIO_SET_GROOVY_INIT);	
		if (req) spi_w(cmd);
	}
	DisableIO();
}

static void groovy_FPGA_blit(uint32_t pixels, uint8_t numBlit)
{          	
    poc->PoC_pixels_ddr = pixels;    
    	                       	 			         	      	                                         
    buffer[4] = (poc->PoC_pixels_ddr) & 0xff;  
    buffer[5] = (poc->PoC_pixels_ddr >> 8) & 0xff;	       	  
    buffer[6] = (poc->PoC_pixels_ddr >> 16) & 0xff;    
  	 			         	      	             
    buffer[7] = numBlit + 1; 			         	      	             
    
    if (poc->PoC_frame_ddr != poc->PoC_frame_recv)
    {
    	poc->PoC_frame_ddr  = poc->PoC_frame_recv;
    	
    	buffer[0] = (poc->PoC_frame_ddr) & 0xff;  
    	buffer[1] = (poc->PoC_frame_ddr >> 8) & 0xff;	       	  
    	buffer[2] = (poc->PoC_frame_ddr >> 16) & 0xff;    
    	buffer[3] = (poc->PoC_frame_ddr >> 24) & 0xff;               // it's useless 32 -> 24?     
    }	   
    
    groovy_FPGA_blit();     
}


static uint32_t getNormalizedVCount(uint32_t frame, uint16_t vcount)
{	
	return (frame * poc->PoC_V_Total) + vcount;
}

static unsigned long getTimerStatus(uint32_t actual_frame, uint32_t desired_frame, uint16_t actual_vcount, uint16_t desired_vcount)
{
	unsigned long ret = 0;		
	int dif_lines = getNormalizedVCount(desired_frame, desired_vcount) - getNormalizedVCount(actual_frame, actual_vcount);		
	if (dif_lines <= 0)
	{
		ret = GetTimer(0);
	}
	else
	{		
		uint64_t ts = floor(poc->PoC_width_time * (double) dif_lines);				
		ret = GetTimer(ts);
	}
	return ret;
}


static void setSwitchres()
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
                                                                                            			      			      			       
    LOG(1,"[Modeline] %f %d %d %d %d %d %d %d %d %s\n",udp_pclock,udp_hactive,udp_hbegin,udp_hend,udp_htotal,udp_vactive,udp_vbegin,udp_vend,udp_vtotal,udp_interlace?"interlace":"progressive");
       	                     	                       	                          
    poc->PoC_frame_ddr = 0;        	                      			       
    poc->PoC_H = udp_hactive;
    poc->PoC_HFP = udp_hbegin - udp_hactive;
    poc->PoC_HS = udp_hend - udp_hbegin;
    poc->PoC_HBP = udp_htotal - udp_hend;
    poc->PoC_V = udp_vactive;
    poc->PoC_VFP = udp_vbegin - udp_vactive;
    poc->PoC_VS = udp_vend - udp_vbegin;
    poc->PoC_VBP = udp_vtotal - udp_vend;         
           
    poc->PoC_ce_pix = (udp_pclock * 16 < 90) ? 16 : (udp_pclock * 12 < 90) ? 12 : (udp_pclock * 8 < 90) ? 8 : 4;	// we want at least 40Mhz clksys for vga scaler	       
           
    int M=0;    
    int C=0;
    int K=0;	
    
    getMCK_PLL_Fractional(udp_pclock*poc->PoC_ce_pix,M,C,K);
    poc->PoC_pll_M0 = (M % 2 == 0) ? M / 2 : M / 2 + 1;
    poc->PoC_pll_M1 = M / 2;    
    poc->PoC_pll_C0 = (C % 2 == 0) ? C / 2 : C / 2 + 1;
    poc->PoC_pll_C1 = C / 2;	        
    poc->PoC_pll_K = K;	        
    
    poc->PoC_pixels_len = poc->PoC_H * poc->PoC_V;    
    poc->PoC_bytes_len = poc->PoC_pixels_len * 3;
            
    poc->PoC_pixels_block[0] = poc->PoC_H * 16;
    poc->PoC_pixels_block[1] = poc->PoC_H * 32;
    poc->PoC_pixels_block[2] = poc->PoC_H * 64;
    poc->PoC_pixels_block[3] = poc->PoC_H * 128;   
    poc->PoC_pixels_block[4] = poc->PoC_H * 192;   
    poc->PoC_pixels_block[5] = poc->PoC_pixels_len;
    
    poc->PoC_bytes_block[0] = poc->PoC_pixels_block[0] * 3;
    poc->PoC_bytes_block[1] = poc->PoC_pixels_block[1] * 3;
    poc->PoC_bytes_block[2] = poc->PoC_pixels_block[2] * 3;
    poc->PoC_bytes_block[3] = poc->PoC_pixels_block[3] * 3;   
    poc->PoC_bytes_block[4] = poc->PoC_pixels_block[4] * 3;   
    poc->PoC_bytes_block[5] = poc->PoC_bytes_len;
    poc->PoC_bytes_recv = 0;    
    
    LOG(1,"[FPGA header] %d %d %d %d %d %d %d %d ce_pix=%d PLL(M0=%d,M1=%d,C0=%d,C1=%d,K=%d) \n",poc->PoC_H,poc->PoC_HFP, poc->PoC_HS,poc->PoC_HBP,poc->PoC_V,poc->PoC_VFP, poc->PoC_VS,poc->PoC_VBP,poc->PoC_ce_pix,poc->PoC_pll_M0,poc->PoC_pll_M1,poc->PoC_pll_C0,poc->PoC_pll_C1,poc->PoC_pll_K);				       			       	
               		         
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
    
    groovy_FPGA_switchres();                 
}

/*
static void groovy_udp_server_stop()
{
	LOG(1, "[UDP][SERVER][%s]\n", "END");
	close(sockfd);		  
	groovyServer = 1;
}
*/

static void setClose()
{          				
	isBlitting = 0;		
	blitCompression = 0;
	doAlwaysStatus = 0;
	doACKStatus = 0;
	LZ4offset = 0;
	free(poc);	
	initDDR();
	groovy_FPGA_init(0);
	isConnected = 0;
	//groovy_udp_server_stop();	
}

static void sendStatus()
{          	
	int flags = 0;
	flags |= MSG_CONFIRM;	
	char sendbuf[6];
	sendbuf[0] = fpga_vga_vcount & 0xff;
	sendbuf[1] = fpga_vga_vcount >> 8;
	sendbuf[2] = fpga_vga_frame  & 0xff;
	sendbuf[3] = fpga_vga_frame  >> 8;	
	sendbuf[4] = fpga_vga_frame  >> 16;	
	sendbuf[5] = fpga_vga_frame  >> 24;	
	sendto(sockfd, sendbuf, 6, flags, (struct sockaddr *)&clientaddr, clilen);								
}

static void sendACK(uint32_t udp_frame, uint16_t udp_vsync)
{          	
	LOG(1, "[ACK_STATUS][DDR px=%d fr=%d][BLIT fr=%d vsync=%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", poc->PoC_pixels_ddr, poc->PoC_frame_ddr, udp_frame, udp_vsync, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);
	
	int flags = 0;
	flags |= MSG_CONFIRM;	
	char sendbuf[12];
	//echo
	sendbuf[0] = udp_frame & 0xff;
	sendbuf[1] = udp_frame >> 8;	
	sendbuf[2] = udp_frame >> 16;	
	sendbuf[3] = udp_frame >> 24;	
	sendbuf[4] = udp_vsync & 0xff;
	sendbuf[5] = udp_vsync >> 8;
	//gpu
	sendbuf[6] = fpga_vga_frame  & 0xff;
	sendbuf[7] = fpga_vga_frame  >> 8;	
	sendbuf[8] = fpga_vga_frame  >> 16;	
	sendbuf[9] = fpga_vga_frame  >> 24;	
	sendbuf[10] = fpga_vga_vcount & 0xff;
	sendbuf[11] = fpga_vga_vcount >> 8;
	sendto(sockfd, sendbuf, 12, flags, (struct sockaddr *)&clientaddr, clilen);								
}

static void setInit(uint8_t compression)
{          				
	blitCompression = compression;
	LZ4offset = 0;
	doACKStatus = 0;
	doAlwaysStatus = 0;
	poc = (PoC_type *) calloc(1, sizeof(PoC_type));
	initDDR();
	groovy_FPGA_init(0);
	groovy_FPGA_init(1);																	
	isBlitting = 0;	
	
	if (!isConnected)
	{
		char hoststr[NI_MAXHOST];
		char portstr[NI_MAXSERV];
		getnameinfo((struct sockaddr *)&clientaddr, clilen, hoststr, sizeof(hoststr), portstr, sizeof(portstr), NI_NUMERICHOST | NI_NUMERICSERV);
		LOG(1,"[Connected %s:%s]\n", hoststr, portstr);		
		isConnected = 1;
	}
	
}

static void setBlit(uint32_t udp_frame, uint16_t udp_vsync)
{          		
	poc->PoC_frame_recv = udp_frame;	
	poc->PoC_frame_vsync = udp_vsync;
	poc->PoC_bytes_recv = 0;		
	isBlitting = 1;	
	numBlit = hpsBlit;	
	
	if (udp_vsync != 0)
	{
		doAlwaysStatus = 1;	
		doACKStatus = 1;
	}	
	if (doVerbose < 3)
	{
		groovy_FPGA_status_fast();
		LOG(1, "[GET_STATUS][DDR px=%d fr=%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", poc->PoC_pixels_ddr, poc->PoC_frame_ddr, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);		
	}	
	if (!doVerbose && !fpga_vram_synced)
 	{
 		LOG(0, "[GET_STATUS][DDR px=%d fr=%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", poc->PoC_pixels_ddr, poc->PoC_frame_ddr, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);		
 	}		 		
	gettimeofday(&blitStart, NULL); 	
}

static void setBlitRaw(uint16_t len)
{         	 	
	poc->PoC_bytes_recv += len;									
	isBlitting = (poc->PoC_bytes_recv >= poc->PoC_bytes_len) ? 0 : 1;			
	LOG(3, "[DDR_BLIT][%d/%d]\n", poc->PoC_bytes_recv, poc->PoC_bytes_len);	
	
	if (doBlocks)
	{								              
                if (poc->PoC_bytes_recv >= poc->PoC_bytes_block[numBlit])			                
                {		
                	LOG(3, "[ACK_BLIT][DDR px=%d fr=%d]\n", (int) (poc->PoC_bytes_recv / 3),  poc->PoC_frame_recv);                	
                	groovy_FPGA_blit(poc->PoC_bytes_recv / 3, numBlit);			                									                					                				             			    			                		
                	numBlit++;
                }
	}
	else
	{	
     		LOG(3, "[ACK_BLIT][DDR px=%d fr=%d]\n", (int) (poc->PoC_bytes_recv / 3),  poc->PoC_frame_recv);
		groovy_FPGA_blit(poc->PoC_bytes_recv / 3, numBlit);
		numBlit++;
	}
	
        if (isBlitting == 0)
        {		
        	//better if no occurs it
        	if (poc->PoC_pixels_ddr < poc->PoC_pixels_len)
        	{        		
        		LOG(1, "[ACK_BLIT][DDR px=%d fr=%d]\n", poc->PoC_pixels_len,  poc->PoC_frame_recv);
			groovy_FPGA_blit(poc->PoC_pixels_len, numBlit);	
        	}
        	        	
		gettimeofday(&blitStop, NULL); 
        	int difBlit = ((blitStop.tv_sec - blitStart.tv_sec) * 1000000 + blitStop.tv_usec - blitStart.tv_usec);
		LOG(1, "[DDR_BLIT][TOTAL %06.3f]\n",(double) difBlit/1000); 			                	 
        }			     
}

static void setBlitLZ4(uint16_t len)
{
	if (LZ4offset == 0)
	{
		LZ4cmpBytes = ((uint16_t)recvbuf[1]  << 8) | recvbuf[0];
		LOG(3, "[UDP_LZ4][%d/%d]\n", len - 2, LZ4cmpBytes);
		LZ4offset = len;								
	}
	else
	{
		LZ4offset += len;
		LOG(3, "[UDP_LZ4][%d/%d]\n", LZ4offset - 2, LZ4cmpBytes);								
	}	
	
	if (LZ4offset - 2 >= LZ4cmpBytes) //equal, otherwise is client error
	{										
		LZ4offset = 0;	
		if (poc->PoC_bytes_recv == 0)
   		{   	
   			LZ4_setStreamDecode(lz4StreamDecode, NULL, 0);   	
   			decBufIndex = 0;
   		}
   		char* const decPtr = decBuf[decBufIndex]; 	   		 		
   		const int decBytes = LZ4_decompress_safe_continue(lz4StreamDecode, (char *) &recvbuf[2], decPtr, LZ4cmpBytes, LZ4blockSize);   		
   		decBufIndex = (decBufIndex + 1) % 2;
   		if (decBytes <= 0)
   		{
   			LOG(1,"[LZ4_DEC][%d][ERROR]\n", decBytes);
   		}
   		else
   		{
   			memcpy(&buffer[HEADER_OFFSET + poc->PoC_bytes_recv], (char *) &decPtr[0], decBytes);   			   		
			setBlitRaw(decBytes);		   		   															   		
		}	
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
}

static void groovy_udp_server_init()
{
	LOG(1, "[UDP][SERVER][%s]\n", "START");
	
	sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);				
    	if (sockfd < 0)
    	{
    		printf("socket error\n");       		
    	}    	    				    	        	
	    
    	memset(&servaddr, 0, sizeof(servaddr));
    	servaddr.sin_family = AF_INET;
    	servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    	servaddr.sin_port = htons(UDP_PORT);
    	  	
        // Non blocking socket                                                                                                     
    	int flags;
    	flags = fcntl(sockfd, F_GETFD, 0);    	
    	if (flags < 0) 
    	{
      		printf("get falg error\n");       		
    	}
    	flags |= O_NONBLOCK;
    	if (fcntl(sockfd, F_SETFL, flags) < 0) 
    	{
       		printf("set nonblock fail\n");       		
    	}   	
    	    		     	    	        	 	    		    	    		
	// Settings	
	int size = 2 * 1024 * 1024;	
        if (setsockopt(sockfd, SOL_SOCKET, SO_RCVBUFFORCE, (void*)&size, sizeof(size)) < 0)     
        {
        	printf("Error so_rcvbufforce\n");        	
        }  
                                    	
	int beTrueAddr = 1;
	if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, (void*)&beTrueAddr,sizeof(beTrueAddr)) < 0)
	{
        	printf("Error so_reuseaddr\n");        	
        } 
        /*             	                           
        int beTrue = 1;
	if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEPORT, (void*)&beTrue, sizeof(beTrue)) < 0)
	{
        	printf("Error so_reuseport\n");        	
        }                             
        */                      	                         	         
    	if (bind(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) < 0)
    	{
    		printf("bind error\n");        	
    	}         	    	    	 	    	    	
    	
    	groovyServer = 2;   	    	    	 			
}

static void groovy_start()
{			
	printf("Groovy-Server 0.1 starting\n");
	
	// get HPS Server Settings
	groovy_FPGA_hps();   
	
	// map DDR 		
	groovy_map_ddr();	    	
        	
    	// UDP Server     	
	groovy_udp_server_init();   	    	    	    	    	           	    	
    	    	    	
    	// reset fpga    
    	groovy_FPGA_init(0);    
    	    	
    	printf("Groovy-Server 0.1 started\n");    			    	                          		
}

void groovy_poll()
{	
	if (!groovyServer)
	{
		groovy_start();
	}	    	                                                                          	                                               					   										
					
	int len = 0; 					
	char* recvbufPtr;
	
	for (;;)
	{	
		if (doAlwaysStatus)
		{		
			groovy_FPGA_status_fast();
		}	
		
		/*
		if (isConnected && doVerbose == 3 && !isBlitting)
		{
			groovy_FPGA_status_fast();
     			LOG(3, "[GET_STATUS][DDR px=%d fr=%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", poc->PoC_pixels_ddr, poc->PoC_frame_ddr, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);
     		}	
     		*/
     		
     		// ack vsync?	
     		if (doACKStatus && getNormalizedVCount(fpga_vga_frame, fpga_vga_vcount) >= getNormalizedVCount(poc->PoC_frame_recv, poc->PoC_frame_vsync))
		{
			doACKStatus = 0;
			LOG(1, "[ACK_STATUS][DDR px=%d fr=%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", poc->PoC_pixels_ddr, poc->PoC_frame_ddr, fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);
			sendStatus();
		}
									
		recvbufPtr = (isBlitting && !blitCompression) ? (char *) (buffer + HEADER_OFFSET + poc->PoC_bytes_recv) : (char *) &recvbuf[LZ4offset];								
		len = recvfrom(sockfd, recvbufPtr, 65536, 0, (struct sockaddr *)&clientaddr, &clilen);
							
		if (len > 0) 
		{    	
			isTimeout = GetTimer(UDP_INACTIVITY);					    			    			    			
			if (!isBlitting)
			{				
	    			switch (recvbufPtr[0]) 
	    			{		
		    			case CMD_CLOSE:
					{						   											        
						LOG(1, "[CMD_CLOSE][%d]\n", recvbufPtr[0]);
						setClose();						
					}; break;
					
					case CMD_INIT:
					{	
						uint8_t compression = recvbufPtr[1];
						if (len > 2 && compression)
						{
							LZ4blockSize = ((uint16_t) recvbufPtr[3]  << 8) | recvbufPtr[2];
							LOG(1, "[CMD_INIT][%d][Compression=%d][BlockSize=%d]\n", recvbufPtr[0], compression, LZ4blockSize);
						}	
				       		else
				       		{
				       			LOG(1, "[CMD_INIT][%d][Compression=%d]\n", recvbufPtr[0], compression);	
				       		}	
						
						setInit(compression);						
					}; break;
					
					case CMD_SWITCHRES:
					{				       	       
				       		LOG(1, "[CMD_SWITCHRES][%d]\n", recvbufPtr[0]);
				       		setSwitchres();					       						       				       						       						       		
					}; break;
					
					case CMD_BLIT:
					{							
						uint32_t udp_frame = ((uint32_t) recvbufPtr[4]  << 24) | ((uint32_t)recvbufPtr[3]  << 16) | ((uint32_t)recvbufPtr[2]  << 8) | recvbufPtr[1];
						uint16_t udp_vsync = ((uint16_t) recvbufPtr[6]  << 8) | recvbufPtr[5];
						if (len > 6 && blitCompression)
						{
							LZ4blockSize = ((uint16_t) recvbufPtr[8]  << 8) | recvbufPtr[7];
							LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d][BlockSize=%d]\n", recvbufPtr[0], udp_frame, udp_vsync, LZ4blockSize);							
						}	
				       		else
				       		{
				       			LOG(1, "[CMD_BLIT][%d][Frame=%d][Vsync=%d]\n", recvbufPtr[0], udp_frame, udp_vsync);
				       		}																		
				       		setBlit(udp_frame, udp_vsync);					       				       					       		
					}; break;
					
					case CMD_GET_STATUS:
					{	
						groovy_FPGA_status();					
				       		LOG(1, "[CMD_GET_STATUS][%d][GPU vc=%d fr=%d fskip=%d vb=%d][VRAM px=%d sync=%d free=%d eof=%d]\n", recvbufPtr[0], fpga_vga_vcount, fpga_vga_frame, fpga_vga_frameskip, fpga_vga_vblank, fpga_vram_pixels, fpga_vram_synced, fpga_vram_ready, fpga_vram_end_frame);				       		
						sendStatus();							        				
					}; break;
					
					case CMD_BLIT_VSYNC:
					{							
						uint32_t udp_frame = ((uint32_t) recvbufPtr[4]  << 24) | ((uint32_t)recvbufPtr[3]  << 16) | ((uint32_t)recvbufPtr[2]  << 8) | recvbufPtr[1];
						uint16_t udp_vsync = ((uint16_t) recvbufPtr[6]  << 8) | recvbufPtr[5];
						if (len > 6 && blitCompression)
						{
							LZ4blockSize = ((uint16_t) recvbufPtr[8]  << 8) | recvbufPtr[7];
							LOG(1, "[CMD_BLIT_VSYNC][%d][Frame=%d][Vsync=%d][BlockSize=%d]\n", recvbufPtr[0], udp_frame, udp_vsync, LZ4blockSize);							
						}	
				       		else
				       		{
				       			LOG(1, "[CMD_BLIT_VSYNC][%d][Frame=%d][Vsync=%d]\n", recvbufPtr[0], udp_frame, udp_vsync);
				       		}																		
				       		setBlit(udp_frame, 0);	
				       		groovy_FPGA_status();	
				       		sendACK(udp_frame, udp_vsync);			       					       		
					}; break;
					
					default: 
					{
						LOG(1,"command: %i\n", recvbufPtr[0]);
					}										
				}				
			}			
			else
			{						        																																		
				if (poc->PoC_bytes_len > 0) // modeline?
				{       
					
					switch(blitCompression)
					{
						case 0: 
						{
							setBlitRaw(len); //memcpy(&buffer[HEADER_OFFSET + poc->PoC_bytes_recv], &recvbufPtr[0], len);
						}
						break; 	
						case 1: 
						{							
							setBlitLZ4(len);
						} 
						break;
					}					                
				}
				else
				{					
					LOG(1, "[UDP_BLIT][%d bytes][Skipped no modeline]\n", len);
					isBlitting = 0;					
				}																				
			}							
		} 
		else
		{
			if (isConnected && CheckTimer(isTimeout))
			{
				LOG(1, "[UDP][CLOSE][%s]\n", "INACTIVITY");
				setClose();				
			}
		}
									       				
		if (!isBlitting)		
		{						
			break;
		}						
	} 
						        
	if (doVerbose > 0 && CheckTimer(logTime))		
   	{   	      		
		fflush(fp);	
		logTime = GetTimer(LOG_TIMER);		
   	} 
   	   	    	
   	              
} 








     