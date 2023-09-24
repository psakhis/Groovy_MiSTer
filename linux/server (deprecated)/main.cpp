
/* UDP server */
#include <stdlib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/ethtool.h>
#include <linux/sockios.h>
#include <stdio.h>
#include <memory.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <signal.h>

#include <sys/time.h> 
#include <time.h>

#include <unistd.h>
#include <sched.h>
#include <inttypes.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
//#include <pthread.h>

#include "zstd.h"
#include "lz4.h"
#include "shmem.h"
//#include "fpga_io.h"
//#include "spi.h"
#include "pll.h"
#include "offload.h"


// FPGA SPI commands (not used out from MiSTer main, interferences with it)
#define UIO_GET_VCOUNT    0xf0 

// FPGA DDR shared
#define BASEADDR 0x30000000
#define HEADER_LEN 0xff       
#define CHUNK 7 
#define HEADER_OFFSET HEADER_LEN - CHUNK 
#define BUFFERSIZE (720 * 576 * 3) + HEADER_LEN

// PoC UDP server 
#define UDP_PORT 32100
#define CMD_CLOSE 1
#define CMD_INIT 2
#define CMD_SWITCHRES 3
#define CMD_BLIT 4
#define CMD_GET_VCOUNT 5

//memcpy partial config (9000 px is arbitrary number)
#define SUBFRAME_PX 9000
#define SUBFRAME_BYTES (SUBFRAME_PX * 3)

//https://stackoverflow.com/questions/64318331/how-to-print-logs-on-both-console-and-file-in-c-language
char timestamp[24];
static char logX[65536] = { 0 }; 
static int logOffset = 0; 
static struct timeval logTS, logTS_ant; 
static int doVerbose = 0; 
static int difUs = 0;

#define log(sev,fmt, ...) do {	\
			        if (sev == 0) printf(fmt, __VA_ARGS__);	\
			        if (sev <= doVerbose && logOffset < 65000) { \
			        	gettimeofday(&logTS, NULL); 		\
			        	difUs = (difUs != 0) ? ((logTS.tv_sec - logTS_ant.tv_sec) * 1000000 + logTS.tv_usec - logTS_ant.tv_usec) : -1;	\
			        	logOffset += snprintf(logX+logOffset, sizeof(logX)-logOffset, "[%06.3f]",(double) difUs/1000); \
                                	logOffset += snprintf(logX+logOffset, sizeof(logX)-logOffset, fmt, __VA_ARGS__);	\
                                	logTS_ant = logTS;	\
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
   //header (0x00) -> burst 1	
   uint8_t  PoC_start; 		 // 0x00 - 8 bit signals		
   //frame sync           
   uint8_t  PoC_frame_ddr; 	 // 0x01  current frame 
   uint32_t PoC_subframe_px_ddr; // 0x02, only 24 used, pixels writed on ddr for current frame
   //1 bytes free                 
   //2 bytes for vcount          
      
   //modeline + pll -> need burst 3
   
   //modeline
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
   uint8_t  PoC_pll_N0;  // 20 High
   uint8_t  PoC_pll_N1;  // 21 Low
   uint8_t  PoC_pll_C0;  // 22 High
   uint8_t  PoC_pll_C1;  // 23 Low
   uint8_t  PoC_ce_pix;  // 24 Divider clk_sys
   
   double   PoC_pclock;   
   
   uint8_t  PoC_frame_vram;             // on 0xC0 position, reported from FPGA (only for log verbose 3)
   
   //framebuffer  
   uint32_t PoC_pixels_len;      	// number of pixels expected for current frame
   uint32_t PoC_pixels_current;         // number of pixels received on current frame      
} PoC_type;

union {
    double d;
    uint64_t i;
} u;

/* General Server variables */
static int printVersion = 0;
static int sockfd;
static struct sockaddr_in clientaddr;
static socklen_t clilen = sizeof(struct sockaddr); 
static PoC_type *poc;
static uint8_t* buffer;


static void initDDR()
{
    memset(&buffer[0],0x00,0xff);	  
}

/* General Methods */
static void flushLog()
{
   FILE * fp;
   fp = fopen ("poc.log", "wt");   
   while(doVerbose > 0)
   {   	
   	if (logOffset > 0)
   	{
   		logX[logOffset] = '\0';   	
   		fprintf(fp, logX);
   		logOffset = 0;
   	}	
   	sleep(1);
   }  
   if (logOffset > 0)
   {
   	logX[logOffset] = '\0';   	
   	fprintf(fp, logX);
   	logOffset = 0;
   }	    
   fclose(fp);
}

// Get logs from FPGA (waiting vram, only verbose 3)
static void logFPGA() 
{                                         
    log(3,"[Frame %d][WaitVram %d][Pixels %d][Start]\n", poc->PoC_frame_ddr, poc->PoC_frame_vram, poc->PoC_pixels_len);      	   					             			       
    while (poc->PoC_frame_ddr != poc->PoC_frame_vram)
    {    		 		
    	poc->PoC_frame_vram = buffer[0xC0];
    	usleep(1);
    }
    log(3,"[Frame %d][WaitVram %d][Pixels %d][End]\n", poc->PoC_frame_ddr, poc->PoC_frame_vram, poc->PoC_pixels_len);       					             
    if (buffer[0xC1] == 0x01) log(3,"[Frame %d][Resynced]\n", poc->PoC_frame_ddr);                     					                         				     	                		
}

static void sigintCallback(int x) {
	printf("Groovy-Server 0.1 --> (Ctrl+C) detected %d\n", x);	
	if (doVerbose > 0)
	{
		doVerbose = 0;
		offload_stop();	
	}	
        //free resources
	initDDR();
	free(poc);
	close(sockfd);	
	exit(-1);
}

static void registerSignalHandler() {
	signal(SIGINT, sigintCallback);
}

static void checkArguments(int argc, char**argv) {
	int i;

	for (i = 1; i < argc; i++) {		
		if (strcmp("-version", argv[i]) == 0) {
			printVersion = 1;
		}
		if (strcmp("-verbose", argv[i]) == 0) {
			doVerbose = atoi(argv[i+1]);
		}
	}
}

static void setBitStart(int bit, int value) {
    bitByte bits;  
    bits.byte = poc->PoC_start;   
    switch(bit) {
    	case 0: bits.u.bit0 = value; break; // start 
    	case 1: bits.u.bit1 = value; break; // updating semaphor
    	case 2: bits.u.bit2 = value; break; // interlaced (use future?)
    	case 3: bits.u.bit3 = value; break; // field (use future?)
    	case 4: bits.u.bit4 = value; break; // modeline requested change
    	case 5: bits.u.bit5 = value; break; // pixel clock requested change
    	case 6: bits.u.bit6 = value; break; // vcount request
    	case 7: bits.u.bit7 = value; break; // free 
    }  	     
    poc->PoC_start = bits.byte;    	
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
                                                                                        			      			      			       
    log(1,"[Modeline] %f %d %d %d %d %d %d %d %d %s \n",udp_pclock,udp_hactive,udp_hbegin,udp_hend,udp_htotal,udp_vactive,udp_vbegin,udp_vend,udp_vtotal,udp_interlace?"interlace":"progressive");
    
    poc->PoC_start = 0; 	                     	                       	                          
    poc->PoC_frame_ddr = 0;
    poc->PoC_frame_vram = 0;     	                      			       
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
    int N=0;	
    int C=0;
    getMNC(udp_pclock*poc->PoC_ce_pix,M,N,C);
    poc->PoC_pll_M0 = (M % 2 == 0) ? M / 2 : M / 2 + 1;
    poc->PoC_pll_M1 = M / 2;
    poc->PoC_pll_N0 = (N % 2 == 0) ? N / 2 : N / 2 + 1;
    poc->PoC_pll_N1 = N / 2;
    poc->PoC_pll_C0 = (C % 2 == 0) ? C / 2 : C / 2 + 1;
    poc->PoC_pll_C1 = C / 2;	        
        
    poc->PoC_pixels_len = poc->PoC_H * poc->PoC_V;
    poc->PoC_pixels_current = 0;
    
    log(1,"[FPGA header] %02hhX %d %d %d %d %d %d %d %d ce_pix=%d PLL(M0=%d,M1=%d,N0=%d,N1=%d,C0=%d,C1=%d) \n",poc->PoC_start,poc->PoC_H,poc->PoC_HFP, poc->PoC_HS,poc->PoC_HBP,poc->PoC_V,poc->PoC_VFP, poc->PoC_VS,poc->PoC_VBP,poc->PoC_ce_pix,poc->PoC_pll_M0,poc->PoC_pll_M1,poc->PoC_pll_N0,poc->PoC_pll_N1,poc->PoC_pll_C0,poc->PoC_pll_C1);				       			       	
    
    //set to DDR
    initDDR();
        
    setBitStart(0,1); // start  
    setBitStart(1,1); // start updating            
    buffer[0]  =  poc->PoC_start;			   
   
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
    buffer[20] =  poc->PoC_pll_N0;  
    buffer[21] =  poc->PoC_pll_N1; 
    buffer[22] =  poc->PoC_pll_C0;  
    buffer[23] =  poc->PoC_pll_C1; 
    buffer[24] =  poc->PoC_ce_pix;  
    
    setBitStart(4,1); // req modeline change
    
    if (poc->PoC_pclock != udp_pclock)
    {
    	setBitStart(5,1); // req pll change
    	poc->PoC_pclock = udp_pclock;
    }
      
    setBitStart(1,0); // end updating
    
    buffer[0]  =  poc->PoC_start;
          
    int resChanged = 0;
    bitByte bits;  
    while (!resChanged)
    {     	
        bits.byte = buffer[0];   		 		
    	resChanged = (bits.u.bit4 == 0 && bits.u.bit5 == 0) ? 1 : 0;    	
    	usleep(1);
    }       
    poc->PoC_start = bits.byte; 
    log(1,"[CMD_SWITCHRES][Waiting %s ACK][End]\n", "FPGA");       					             
        
}

static void setSubFrame(uint8_t frame, char *rgb, uint32_t rgbOffset, uint32_t rgbSize)
{   
   log(2,"[DDR][Memcpy subframe %d][%6u bytes][Px %d][Endframe %s][Start]\n", frame, rgbSize, poc->PoC_pixels_current, (poc->PoC_pixels_current == poc->PoC_pixels_len) ? "yes" : " no");   
   memcpy(&buffer[HEADER_OFFSET + rgbOffset], &rgb[0], rgbSize);         
   setBitStart(1,1); // updating header  
   buffer[0] = poc->PoC_start;         
   buffer[1] = frame;  
   buffer[2] = (poc->PoC_pixels_current) & 0xff;  
   buffer[3] = (poc->PoC_pixels_current >> 8) & 0xff;	       	  
   buffer[4] = (poc->PoC_pixels_current >> 16) & 0xff;    
   buffer[5] = (poc->PoC_pixels_current >> 24) & 0xff; //not used
   setBitStart(1,0); // end updating        
   buffer[0] = poc->PoC_start; 	
   log(2,"[DDR][Memcpy subframe %d][%6u bytes][End]\n", frame, rgbSize);	
}

static int setBlit(char* recvbuf, int poc_Compression, int udpSize)
{     	    	             
   int endFrame = 0;
   char* cBuff = { 0 };
   
   uint8_t udp_frame; 												
   uint32_t udp_pixel_offset;  				
   uint32_t udp_pixel_len; 
  
   udp_frame = (uint8_t) recvbuf[1];
   udp_pixel_offset = ((uint32_t) recvbuf[5] << 24) | ((uint32_t)recvbuf[4] << 16) | ((uint32_t)recvbuf[3] << 8) | recvbuf[2];
   udp_pixel_len = ((uint32_t) recvbuf[9] << 24) | ((uint32_t)recvbuf[8] << 16) | ((uint32_t)recvbuf[7] << 8) | recvbuf[6];   
   
   log(3,"[UDP][udp_frame %d][udp_pixel_offset %d][udp_pixel_len %d]\n", udp_frame, udp_pixel_offset, udp_pixel_len);  
       
   uint32_t rgbSize = udp_pixel_len * 3;    	    	
   uint32_t rgbOffset = udp_pixel_offset * 3;  
         
   if (poc_Compression == 1) // ZSTD
   {   	  	
   	unsigned long long const rSize = ZSTD_getFrameContentSize(&recvbuf[10], (unsigned)udpSize - 10);      	   	
   	cBuff = (char*)malloc((size_t)rSize);	      		
   	log(2,"[ZSTD][Decomp frame %d][%6u bytes][Start]\n", udp_frame, (unsigned)udpSize - 10);       	    	
   	size_t const dSize = ZSTD_decompress(cBuff, rSize, &recvbuf[10], (size_t)udpSize - 10);     		 
   	log(2,"[ZSTD][Decomp frame %d][%6u bytes][End]\n", udp_frame, (unsigned)dSize);       	    	    	
   }
   
   if (poc_Compression >= 2) // LZ4
   {   	    	
   	cBuff = (char*)malloc(rgbSize);   	     	 	    
   	log(2,"[LZ4][Decomp frame %d][%6u bytes][Start]\n", udp_frame, (unsigned)udpSize - 10);            	   	    		   	   	   	   	   	      	   	   	
        const int dSize = LZ4_decompress_safe(&recvbuf[10], cBuff, (size_t)udpSize - 10, rgbSize);               	       	                                   	       	                                    	       	                                   	       	                       
   	log(2,"[LZ4][Decomp frame %d][%6u bytes][End]\n", udp_frame, (unsigned)dSize);    
   }	
   
   // If activated memcpy partial, blit two 2 times (FPGA starts asap)
   if (SUBFRAME_PX > 0 && SUBFRAME_PX < udp_pixel_len) 
   {   	 
   	poc->PoC_pixels_current += SUBFRAME_PX;
   	setSubFrame(udp_frame, (poc_Compression > 0) ? &cBuff[0] : &recvbuf[10], rgbOffset, SUBFRAME_BYTES);    
   	poc->PoC_pixels_current += udp_pixel_len - SUBFRAME_PX; 
   	setSubFrame(udp_frame, (poc_Compression > 0) ? &cBuff[SUBFRAME_BYTES] : &recvbuf[10+SUBFRAME_BYTES], rgbOffset + SUBFRAME_BYTES, rgbSize - SUBFRAME_BYTES); 
   }   
   else 
   {   	    	
   	poc->PoC_pixels_current += udp_pixel_len; 
 	setSubFrame(udp_frame, (poc_Compression > 0) ? &cBuff[0] : &recvbuf[10], rgbOffset, rgbSize);   	 	 	 	   
   }  
   
   // update end of frame
   if (poc->PoC_pixels_current >= poc->PoC_pixels_len)
   {
 	endFrame = 1;   		    
      	poc->PoC_pixels_current = 0;          	          	   	
      	poc->PoC_frame_ddr = udp_frame;
   }     
   
   if (poc_Compression > 0) free(cBuff);

   return endFrame;		
}


int main(int argc, char *argv[])
{	
    //set to cpu #1, best i/o interruptions
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(1, &set);
    sched_setaffinity(0, sizeof(set), &set);		        		
    
    checkArguments(argc, argv);
    if (printVersion) 
    {
    	printf("Groovy-Server 0.1\n");
    	return 0;
    }
    printf("Groovy-Server 0.1 --> (Ctrl+C) to Exit\n");					        
    
    //log on cpu #0
    if (doVerbose > 0)
    {
    	offload_start();
    	offload_add_work([=] {flushLog();});
    }	   
   
    // Map DDR 
    int pagesize = sysconf(_SC_PAGE_SIZE);
    if (pagesize==0) pagesize=4096;   
    int offset = BASEADDR;
    int map_start = offset & ~(pagesize - 1);
    int map_off = offset - map_start;
    int num_bytes=BUFFERSIZE;
         
    static uint8_t *map = 0;        
    map = (uint8_t*)shmem_map(map_start, num_bytes+map_off);  
    buffer = map + map_off;     
    
    initDDR();
    poc = (PoC_type *) calloc(1, sizeof(PoC_type)); 
    
    // UDP Server 
    struct sockaddr_in servaddr;	
    sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sockfd < 0)
    {
    	printf("socket error\n");
       	return -1;
    }
    
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(UDP_PORT);
    
    // Best blocking for reserve cpu usage    
    /*int flags;
    flags = fcntl(sockfd, F_GETFD, 0);
    if (flags < 0) 
    {
      	log(0,"get falg error\n");
       	return -1;
    }
    flags |= O_NONBLOCK;
    if (fcntl(sockfd, F_SETFL, flags) < 0) 
    {
       	log(0,"set nonblock fail\n");
       	return -1;
    }        	
    */
     	
    // 2Mb Buffer
    // netstat -s -u --> see if you drop packets for buffer 
    // sudo sysctl -w net.core.rmem_max=33554432 for 32Mb or 2097152 for 2Mb
    // sudo chrt -r 70 poc --> to run in real time
    // sudo nice -n -20 poc --> max prior user
    int size = 2 * 1024 * 1024;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVBUF, &size, (socklen_t)sizeof(int));
    
    if (bind(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) < 0)
    {
    	printf("bind error\n");
        return -1;
    }
    
    // Catch Ctrl+C	
    registerSignalHandler();	
    			    	
    char recvbuf[65536] = { 0 };    
    int len = 0;     
    int poc_Compression = 0;   
    
    while (1)
    {        	
    	len = recvfrom(sockfd, recvbuf, sizeof(recvbuf), 0, (struct sockaddr *)&clientaddr, &clilen);
    	    	  	    	
    	if (len > 0) 
    	{
    		//log(0,"command: %i\n", recvbuf[0]);
    		switch (recvbuf[0]) 
    		{
			case CMD_CLOSE:
			{						   											        
				log(1,"[CMD_CLOSE][%d]\n",recvbuf[0]);	
   				//free resources
				poc_Compression = 0;
				initDDR();										       			       				
				free(poc);																																																																				       			       				
			}; break;
			
			case CMD_INIT:
			{	
				log(1,"[CMD_INIT][%d][Compression=%d]\n",recvbuf[0],recvbuf[1]);										
				poc = (PoC_type *) calloc(1, sizeof(PoC_type));	
				poc_Compression = recvbuf[1];															
				initDDR();
				setBitStart(0,1);
				buffer[0] = poc->PoC_start;																						   													   				
			}; break;
			
			case CMD_SWITCHRES:
			{				       	       
			       log(1,"[CMD_SWITCHRES][%d]\n",recvbuf[0]);				               			       
			       setSwitchres(recvbuf);				     		       			     			   			     				               			       			 
			}; break;
			
			case CMD_BLIT:
			{				        	    			    			
			       if  (poc->PoC_start != 0)				    	       			       
			       {
			       		log(1,"[CMD_BLIT][%d][%d bytes]\n",recvbuf[0],len);				               			       			       			       			       		
			       		int endFrame = setBlit(recvbuf, poc_Compression, len);			       
			       		if (endFrame && doVerbose > 2) logFPGA();			       					       						       		
			       } 
			       else 
			       {
			         	log(1,"[CMD_BLIT][%d][%d bytes][Skipped, no modeline]\n",recvbuf[0],len);			          				       			       			           			      			    			      			             			
			       }	
			}; break;
			
			case CMD_GET_VCOUNT:
			{								       	       
				log(1,"[CMD_VCOUNT][%d]\n",recvbuf[0]); 
							  								
				/* SPI it's faster, but can interfere with MiSTer main. Recommend it's get vcount from MiSTer main port 
			    	uint16_t req = 0;
			    	uint16_t vcount = 0;
			    	while (!req)
			    	{
			        	req = spi_uio_cmd_cont(UIO_GET_VCOUNT);
			        	if (req) vcount = spi_w(0);   
    			        	DisableIO();      			        				        	
    			    	}
    			    	*/
    				setBitStart(1,0); // no block
    				setBitStart(4,0); // no modeline req.
    				setBitStart(5,0); // no px req.          
    				setBitStart(6,1); // vcount requested
    				buffer[0] = poc->PoC_start;	
    				int resChanged = 0;
    				bitByte bits;  
    				while (!resChanged)    				
    				{     	
    					usleep(1);
        				bits.byte = buffer[0];   		 		
    					resChanged = (bits.u.bit6 == 0) ? 1 : 0;      					  					    	    					
    				}       
    				poc->PoC_start = bits.byte;     				
    				uint16_t vcount = ((uint16_t)buffer[7] << 8) | buffer[6];    				  				
    				
    			    	char data[2] = { 0 };			     
			       	data[0] = vcount  & 0xff;        
    				data[1] = vcount >> 8;			        
			        sendto(sockfd, data, sizeof(data), 0, (struct sockaddr *)&clientaddr, clilen);	 			        
    			    	log(1,"[CMD_VCOUNT][vcount=%d]\n", vcount);     
			}; break;
		}
	}						            	
    }	
    						
   return 0;
}

