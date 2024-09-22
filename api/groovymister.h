#ifndef __GROOVYMISTER_H__
#define __GROOVYMISTER_H__

#include <inttypes.h>

#ifdef _WIN32
 #include <winsock2.h>
 #include <ws2tcpip.h>
 #include <mswsock.h>
 #include "rio.h"
#else
 #include <cstring>
 #include <cstdio>
 #include <sys/socket.h>
 #include <netinet/in.h>
 #include <time.h>
#endif

#ifndef GROOVYMISTER_VERSION
#define GROOVYMISTER_VERSION "1.0.0"
#endif

#define BUFFER_SIZE 1245312 // 720x576x3
#define BUFFER_SLICES 846
#define MTU_HEADER 28
#define BUFFER_MTU 1500 - MTU_HEADER

//joystick map
#define GM_JOY_RIGHT (1 << 0)
#define GM_JOY_LEFT  (1 << 1)
#define GM_JOY_DOWN  (1 << 2)
#define GM_JOY_UP    (1 << 3)
#define GM_JOY_B1    (1 << 4)
#define GM_JOY_B2    (1 << 5)
#define GM_JOY_B3    (1 << 6)
#define GM_JOY_B4    (1 << 7)
#define GM_JOY_B5    (1 << 8)
#define GM_JOY_B6    (1 << 9)
#define GM_JOY_B7    (1 << 10)
#define GM_JOY_B8    (1 << 11)
#define GM_JOY_B9    (1 << 12)
#define GM_JOY_B10   (1 << 13)

/*! fpgaStatus :
 *  Data received after CmdInit and CmdBlit calls
 */
typedef struct fpgaStatus{
	uint32_t frame;		//frame on gpu
	uint32_t frameEcho;	//frame received
	uint16_t vCount;	//vertical count on gpu
	uint16_t vCountEcho; 	//vertical received

	uint8_t vramEndFrame; 	//1-fpga has all pixels on vram for last CmdBlit
	uint8_t vramReady;	//1-fpga has free space on vram
	uint8_t vramSynced;	//1-fpga has synced (not red screen)
	uint8_t vgaFrameskip;	//1-fpga used framebuffer (volatile framebuffer off)
	uint8_t vgaVblank;	//1-fpga is on vblank
	uint8_t vgaF1;		//1-field for interlaced
	uint8_t audio;		//1-fgpa has audio activated
	uint8_t vramQueue; 	//1-fpga has pixels prepared on vram
} fpgaStatus;

typedef struct fpgaJoyInputs{
	uint32_t joyFrame;	//joystick blit frame
	uint8_t  joyOrder;	//joystick blit order
	uint16_t joy1;	 	//joystick 1 map
	uint16_t joy2;	 	//joystick 2 map
	char     joy1LXAnalog; 	//joystick 1 L-Analog X
	char     joy1LYAnalog; 	//joystick 1 L-Analog Y
	char     joy1RXAnalog; 	//joystick 1 R-Analog X
	char     joy1RYAnalog; 	//joystick 1 R-Analog Y
	char     joy2LXAnalog; 	//joystick 2 L-Analog X
	char     joy2LYAnalog; 	//joystick 2 L-Analog Y
	char     joy2RXAnalog; 	//joystick 2 R-Analog X
	char     joy2RYAnalog; 	//joystick 2 R-Analog Y
} fpgaJoyInputs;

typedef struct fpgaPS2Inputs{
	uint32_t ps2Frame;	//ps2 blit frame
	uint8_t  ps2Order;	//ps2 blit order
	uint8_t  ps2Keys[32]; 	//bit array with sdl scancodes convention
	uint8_t  ps2Mouse;	//byte 0 ps2 mouse [yo,xo,ys,xs,1,bm,br,bl]
	uint8_t  ps2MouseX; 	//byte 1 ps2 mouse X
	uint8_t  ps2MouseY; 	//byte 2 ps2 mouse Y
	uint8_t  ps2MouseZ; 	//byte 3 ps2 mouse Z
} fpgaPS2Inputs;

typedef unsigned long DWORD;

class GroovyMister
{
 public:
	 
	fpgaStatus fpga; 	 // Data with last received ACK
	fpgaJoyInputs joyInputs; // Data with last joystick inputs received
	fpgaPS2Inputs ps2Inputs; // Data with last ps2 inputs received

	GroovyMister();
	~GroovyMister();
	
	char* getPBufferBlit(uint8_t field); // This buffer are registered and aligned for sending rgb. Populate it before CmdBlit
	char* getPBufferBlitDelta(void); // This buffer are registered and aligned for sending rgb. Populate it before CmdBlit with delta difference between actual frame and last
	char* getPBufferAudio(void); // This buffer are registered and aligned for sending audio. Populate it before CmdAudio
	
	// Close connection
	void CmdClose(void);
	// Init streaming with ip, port
	int CmdInit(const char* misterHost, uint16_t misterPort, int lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode, uint16_t mtu);
	// Change resolution (check https://github.com/antonioginer/switchres) with modeline
	void CmdSwitchres(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace);
	// Stream frame, field = 0 for progressive, vCountSync = 0 for auto frame delay or number of vertical line to sync with, margin with nanoseconds for auto frame delay)
	void CmdBlit(uint32_t frame, uint8_t field, uint16_t vCountSync, uint32_t margin, uint32_t matchDeltaBytes);
	// Stream audio
	void CmdAudio(uint16_t soundSize);
	// getACK is used internal on WaitSync, dwMilliseconds = 0 will time out immediately if no new data
	uint32_t getACK(DWORD dwMilliseconds);
	// sleep to sync with crt raster
	void WaitSync(void);
	// get nanoseconds (positive or negative) to sync with raster
	int DiffTimeRaster(void);

	void BindInputs(const char* misterHost, uint16_t misterPort);
	void PollInputs(void);

	void setVerbose(uint8_t sev);
	const char* getVersion();

 private:

	uint8_t m_verbose;

#ifdef _WIN32
	SOCKET m_sockFD;
	RIO_EXTENSION_FUNCTION_TABLE m_rio;
	RIO_CQ m_sendQueue;
	RIO_CQ m_receiveQueue;
	RIO_RQ m_requestQueue;
	HANDLE m_hIOCP;
	RIO_BUFFERID m_sendRioBufferId;
	RIO_BUF m_sendRioBuffer;
	RIO_BUFFERID m_receiveRioBufferId;
	RIO_BUF m_receiveRioBuffer;
	RIO_BUFFERID m_sendRioBufferBlitId[2];	
	RIO_BUF *m_pBufsBlit[2];
	RIO_BUFFERID m_sendRioBufferAudioId;
	RIO_BUF m_sendRioBufferAudio;
	RIO_BUF *m_pBufsAudio;
	SOCKET m_sockInputsFD;

	LARGE_INTEGER m_tickStart;
	LARGE_INTEGER m_tickEnd;
	LARGE_INTEGER m_tickSync;
	LARGE_INTEGER m_tickCongestion;
#else
	int m_sockFD;
	int m_sockInputsFD;

	struct timespec m_tickStart;
	struct timespec m_tickEnd;
	struct timespec m_tickSync;
	struct timespec m_tickCongestion;
#endif
	struct sockaddr_in m_serverAddr;
	struct sockaddr_in m_serverAddrInputs;
	char m_bufferSend[26];
	char m_bufferReceive[13];
	char m_bufferInputsReceive[41];
	char *m_pBufferBlit[2];
	char *m_pBufferBlitDelta;
	char *m_pBufferAudio;
	char *m_pBufferLZ4[2];
	uint8_t m_lz4Frames;
	uint8_t m_soundChan;
	uint8_t m_rgbMode;
	uint32_t m_RGBSize;
	uint8_t  m_interlace;
	uint16_t m_vTotal;
	uint32_t m_frame;
	uint32_t m_frameTime;
	uint32_t m_widthTime;
	uint32_t m_streamTime;
	uint32_t m_emulationTime;
	uint16_t m_mtu;
	uint8_t m_doCongestionControl;
	uint8_t m_core_version;
	uint32_t m_network_ping;
	uint8_t m_delta_enabled[2];
	uint8_t m_isConnected;

	char *AllocateBufferSpace(const DWORD bufSize, const DWORD bufCount, DWORD& totalBufferSize, DWORD& totalBufferCount);
	void Send(void *cmd, int cmdSize);
	void SendStream(uint8_t whichBuffer, uint8_t field, uint32_t bytesToSend, uint32_t cSize);
	void setTimeStart(void);
	void setTimeEnd(void);
	uint32_t DiffTime(void);
	void setFpgaStatus(void);
	void setFpgaJoystick(int len);
	void setFpgaPS2(int len);
};

#endif
