#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <math.h>

#ifdef _WIN32 
 #include <winsock2.h>  
 #include <ws2tcpip.h> 
#else
 #include <netinet/udp.h>
 #include <sys/types.h> 
 #include <sys/socket.h> 
 #include <arpa/inet.h> 
 #include <netinet/in.h>  
 #include <fcntl.h>
 
 #include <sys/time.h> 
 #include <sys/stat.h>
 #include <time.h>
 #include <unistd.h> 
 #include <cstring> //memcpy
#endif

#include <../lz4/lz4.h>
#include <../lz4/lz4hc.h>

#include <../switchres/switchres_wrapper.h>

#include <features/features_cpu.h>

#define mister_CMD_CLOSE 1
#define mister_CMD_INIT 2
#define mister_CMD_SWITCHRES 3
#define mister_CMD_BLIT 4
#define mister_CMD_GET_STATUS 5
#define mister_CMD_BLIT_VSYNC 6

#define mister_MAX_BUFFER_WIDTH 1024
#define mister_MAX_BUFFER_HEIGHT 768
#define mister_MAX_LZ4_BLOCK   61440


void mister_CmdClose(void);
void mister_CmdInit(const char* mister_host, short mister_port, bool lz4_frames);
void mister_CmdSwitchres(int w, int h, double vfreq, int orientation);
void mister_CmdBlit(char *bufferFrame, uint16_t vsync); 
 
void mister_setBlitTime(retro_time_t blitTime);  
 
int mister_Sync(retro_time_t emulationTime); //Sync emulator with MiSTer raster
int mister_GetVSyncDif(void); //raster dif. between emulator and MiSTer (usec)
 
int mister_GetField(void);
 
typedef struct mister_video_info
{ 
 bool isConnected;	
 bool lz4_compress;
 uint32_t frame;
 uint16_t width;
 uint16_t height;
 uint16_t lines; //vtotal
 double vfreq;
 uint8_t  interlaced;
 uint32_t widthTime; //usec
 uint32_t frameTime; //usec
   
 retro_time_t avgEmulationTime;
 retro_time_t avgBlitTime;
  
 uint16_t vsync_auto;
 
 //ACK Status
 uint32_t frameEcho;
 uint16_t vcountEcho;
 uint32_t frameGPU;
 uint16_t vcountGPU;
 
 bool firstField;
 
 //UDP	
 char bufferRecv[12];
 struct sockaddr_in ServerAddr;  
 int sockfd;                
  
 //LZ4
 char m_fb[mister_MAX_BUFFER_HEIGHT * mister_MAX_BUFFER_WIDTH * 3];
 char m_fb_compressed[mister_MAX_BUFFER_HEIGHT * mister_MAX_BUFFER_WIDTH * 3]; 
 char inp_buf[2][mister_MAX_LZ4_BLOCK + 1];
} mister_video_t;
 
 //Internal functions 
 //UDP
 void mister_Send(void *cmd, int cmdSize);
 void mister_SendMTU(char *buffer, int bytes_to_send, int chunk_max_size);
 void mister_SendLZ4(char *buffer, int bytes_to_send, int block_size);
 void mister_ReceiveBlitACK(void);


 


