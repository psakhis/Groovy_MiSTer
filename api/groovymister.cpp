#include "../mednafen.h"
#include "../mednafen-driver.h"
#include "groovymister.h"

#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <cstring> 

#ifndef _WIN32 
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
#endif

#include "lz4/lz4.h"
#include "lz4/lz4hc.h"

#define USE_RIO 1

#define LOG(sev,fmt, ...) do {\
			        if (sev <= m_verbose) {\
					printf(fmt, __VA_ARGS__);\
                                }\
                           } while (0)

#define CMD_CLOSE 1
#define CMD_INIT 2
#define CMD_SWITCHRES 3
#define CMD_AUDIO 4
#define CMD_GET_STATUS 5
#define CMD_BLIT_VSYNC 6

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
    
GroovyMister::GroovyMister()
{
	m_verbose = 0;
	m_lz4Frames = 0;
	m_soundChan = 0;
	m_rgbMode = 0;
	
	fpga.frame = 0;
 	fpga.frameEcho = 0;
 	fpga.vCount = 0;
 	fpga.vCountEcho = 0; 	
	fpga.vramEndFrame = 0;
 	fpga.vramReady = 0;
 	fpga.vramSynced = 0;
 	fpga.vgaFrameskip = 0;
 	fpga.vgaVblank = 0;
 	fpga.vgaF1 = 0;
 	fpga.audio = 0;
 	fpga.vramQueue = 0;
 	 	
 	inputs.joyFrame = 0;
 	inputs.joyOrder = 0;
 	inputs.joy1 = 0;
 	inputs.joy2 = 0;
 	
 	m_RGBSize = 0;
 	m_interlace = 0;
        m_vTotal = 0;
        m_frame = 0; 
        m_frameTime = 0;
        m_streamTime = 0;      
        m_emulationTime = 0;       
	
	DWORD totalBufferCount = 0;
   	DWORD totalBufferSize = 0;   	
   	pBufferBlit  = AllocateBufferSpace(BUFFER_SIZE, 1, totalBufferSize, totalBufferCount); 
   	pBufferAudio = AllocateBufferSpace(BUFFER_SIZE, 1, totalBufferSize, totalBufferCount); 
   	m_pBufferLZ4 = AllocateBufferSpace(BUFFER_SIZE, 1, totalBufferSize, totalBufferCount);    	
}


GroovyMister::~GroovyMister()
{
  	free(pBufferBlit);
  	free(pBufferAudio);
  	free(m_pBufferLZ4);  	
}

void GroovyMister::CmdClose(void)
{           
   m_bufferSend[0] = CMD_CLOSE;
   Send(&m_bufferSend[0], 1);         
#ifdef _WIN32
if (USE_RIO)
{
   m_rio.RIOCloseCompletionQueue(m_sendQueue);
   m_rio.RIOCloseCompletionQueue(m_receiveQueue);
   m_rio.RIODeregisterBuffer(m_sendRioBufferId);	
   m_rio.RIODeregisterBuffer(m_sendRioBufferBlitId);
   m_rio.RIODeregisterBuffer(m_sendRioBufferAudioId);
}   
   ::closesocket(m_sockFD);
   ::closesocket(m_sockInputsFD);
   ::WSACleanup();
#else
   close(m_sockFD);
   close(m_sockInputsFD);
#endif  		
}

void GroovyMister::setVerbose(uint8_t sev)
{
	m_verbose = sev;
}

const char* GroovyMister::getVersion()
{
	return &GROOVYMISTER_VERSION[0];
}

uint8_t GroovyMister::CmdInit(const char* misterHost, uint16_t misterPort, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode)
{   
	// Set server          	 	                      
	m_serverAddr.sin_family = AF_INET;
	m_serverAddr.sin_port = htons(misterPort);
	m_serverAddr.sin_addr.s_addr = inet_addr(misterHost);   
			
	// Set socket   
#ifdef _WIN32              
   	WSADATA wsd;                                           
   	uint16_t rc;
      		   
   	rc = ::WSAStartup(MAKEWORD(2, 2), &wsd);
   	if (rc != 0) 
   	{
		LOG(0, "[MiSTer] Unable to load Winsock: %d\n", rc);       
  	}
            
   	m_sockFD = INVALID_SOCKET;  

if (USE_RIO)
{   
   	LOG(0, "[MiSTer] Initialising socket registered io %s...\n","");                
   	m_sockFD = ::WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_REGISTERED_IO);	          
   	if (m_sockFD == INVALID_SOCKET)
   	{
  		LOG(0,"[MiSTer] Could not create socket : %lu", ::GetLastError());        
   	}    
   	
	LOG(0,"[MiSTer] Setting WSAIoctl %s...\n","");	    
	GUID functionTableId = WSAID_MULTIPLE_RIO;
	DWORD dwBytes = 0;
	if ( NULL != WSAIoctl(m_sockFD, SIO_GET_MULTIPLE_EXTENSION_FUNCTION_POINTER, &functionTableId, sizeof(GUID), (void**)&m_rio, sizeof(m_rio), &dwBytes, NULL, NULL) )
	{
		LOG(0,"[MiSTer] Could not create WSAIoctl : %lu", ::GetLastError());
	}
	
	m_hIOCP = ::CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0) ;
	if (NULL == m_hIOCP)
	{		
		LOG(0,"[MiSTer] Could not create IoCompletionPort : %lu", ::GetLastError());
	}				
	
	OVERLAPPED overlapped;
        ZeroMemory(&overlapped, sizeof(overlapped));
        
	RIO_NOTIFICATION_COMPLETION completionType ;

	completionType.Type = RIO_IOCP_COMPLETION;
	completionType.Iocp.IocpHandle = m_hIOCP;
	completionType.Iocp.CompletionKey = (void*)1; 
	completionType.Iocp.Overlapped = &overlapped;		
	
	LOG(0,"[MiSTer] Register Buffers %s...\n","");	    
	m_sendRioBufferId = m_rio.RIORegisterBuffer(m_bufferSend, 26);
    	if (m_sendRioBufferId == RIO_INVALID_BUFFERID)
    	{
        	LOG(0,"[MiSTer] RIORegisterBuffer m_BufferSend Error: %lu\n", ::GetLastError());        		
    	}        		
    	m_sendRioBuffer.BufferId = m_sendRioBufferId;
    	m_sendRioBuffer.Offset = 0;
    	m_sendRioBuffer.Length = 26;
        
        m_receiveRioBufferId = m_rio.RIORegisterBuffer(m_bufferReceive, 17);
    	if (m_receiveRioBufferId == RIO_INVALID_BUFFERID)
    	{
        	LOG(0,"[MiSTer] RIORegisterBuffer m_BufferReceive Error: %lu\n", ::GetLastError());        		
    	}        		
    	m_receiveRioBuffer.BufferId = m_receiveRioBufferId;
    	m_receiveRioBuffer.Offset = 0;
    	m_receiveRioBuffer.Length = 17;
    	
    	if (lz4Frames)
    	{    		
		m_sendRioBufferBlitId = m_rio.RIORegisterBuffer(m_pBufferLZ4, BUFFER_SIZE);
	}
	else
	{
		m_sendRioBufferBlitId = m_rio.RIORegisterBuffer(pBufferBlit, BUFFER_SIZE);								
	}
	if (m_sendRioBufferBlitId == RIO_INVALID_BUFFERID)
    	{
        	LOG(0,"[MiSTer] RIORegisterBuffer pBufferBlit Error: %lu\n", ::GetLastError());        		
    	}        		
	        
        DWORD offset = 0;			    											    	    		    		    		 	    		    	
    	m_pBufsBlit = new RIO_BUF[BUFFER_SLICES];    		
    	for (DWORD i = 0; i < BUFFER_SLICES; ++i)
   	{      	
	   RIO_BUF *pBuffer = m_pBufsBlit + i;
      	
           pBuffer->BufferId = m_sendRioBufferBlitId;
      	   pBuffer->Offset = offset;
           pBuffer->Length = BUFFER_MTU;

	   offset += BUFFER_MTU;
   	}   
   	
        m_sendRioBufferAudioId = m_rio.RIORegisterBuffer(pBufferAudio, BUFFER_SIZE);
        if (m_sendRioBufferAudioId == RIO_INVALID_BUFFERID)
    	{
        	LOG(0,"[MiSTer] RIORegisterBuffer pBufferAudio Error: %lu\n", ::GetLastError());        		
    	}  
        offset = 0;			    											    	    		    		    		 	    		    	
    	m_pBufsAudio = new RIO_BUF[BUFFER_SLICES];    		
    	for (DWORD i = 0; i < BUFFER_SLICES; ++i)
   	{      	
	   RIO_BUF *pBuffer = m_pBufsAudio + i;
      	
           pBuffer->BufferId = m_sendRioBufferAudioId;
      	   pBuffer->Offset = offset;
           pBuffer->Length = BUFFER_MTU;

	   offset += BUFFER_MTU;
   	}   			
   	
   	LOG(0,"[MiSTer] Create queues %s...\n","");		
	m_sendQueue = m_rio.RIOCreateCompletionQueue(BUFFER_SLICES, &completionType);
	if (m_sendQueue == RIO_INVALID_CQ)
	{
		LOG(0,"[MiSTer]Could not create m_sendQueue : %lu", ::GetLastError());	
	}
	
	m_receiveQueue = m_rio.RIOCreateCompletionQueue(BUFFER_SLICES, &completionType);
	if (m_receiveQueue == RIO_INVALID_CQ)
	{
		LOG(0,"[MiSTer]Could not create m_receiveQueue : %lu", ::GetLastError());	
	}
	
	m_requestQueue = m_rio.RIOCreateRequestQueue(m_sockFD, BUFFER_SLICES, 1, BUFFER_SLICES, 1, m_receiveQueue, m_sendQueue, NULL) ;
	if (m_requestQueue == RIO_INVALID_RQ)
	{
		LOG(0,"[MiSTer]Could not create m_requestQueue : %lu", ::GetLastError());	
	}
	
	LOG(0,"[MiSTer] Connect %s...\n","");	
	if (SOCKET_ERROR == ::connect(m_sockFD, reinterpret_cast<sockaddr *>(&m_serverAddr), sizeof(m_serverAddr)))
   	{
      		LOG(0,"[MiSTer] Could not connect : %lu", ::GetLastError());
   	}  
   	
   	m_rio.RIONotify(m_receiveQueue);  	   		   		   		   				   					
}
else
{
	LOG(0, "[MiSTer] Initialising socket %s...\n","");                
   	m_sockFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);          
   	if (m_sockFD == INVALID_SOCKET)
   	{
  		LOG(0,"[MiSTer] Could not create socket : %lu", ::GetLastError());        
   	}    
	   		                     	   			
	LOG(0,"[MiSTer] Setting socket async %s...\n",""); 
  	u_long iMode=1;
   	rc = ioctlsocket(m_sockFD, FIONBIO, &iMode); 
   	if (rc < 0)
   	{
   		LOG(0,"[MiSTer] set nonblock fail %d\n", rc);
   	}
   	
	LOG(0,"[MiSTer] Setting send buffer to %d bytes...\n", 2097152);	    
	int optVal = 2097152;  
	int optLen = sizeof(int);
	rc = setsockopt(m_sockFD, SOL_SOCKET, SO_SNDBUF, (char*)&optVal, optLen);
	if (rc != 0) 
	{
		LOG(0,"[MiSTer] Unable to set send buffer: %d\n", rc);       
	}   						  	   
}

#else	               
  	printf("[DEBUG] Initialising socket...\n");  
  	m_sockFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);				
  	if (sockfd < 0)
  	{
  		LOG(0,"[MiSTer] Could not create socket : %d", sockfd);      		     		
  	}        
      
	LOG(0,"[MiSTer] Setting socket async %s...\n",""); 
  	// Non blocking socket                                                                                                     
  	int flags;
  	flags = fcntl(m_sockFD, F_GETFD, 0);    	
  	if (flags < 0) 
  	{
  		LOG(0,"[MiSTer] get falg error %d\n", flags);  		     		
  	}
  	flags |= O_NONBLOCK;
  	if (fcntl(m_sockFD, F_SETFL, flags) < 0) 
  	{
  		LOG(0,"[MiSTer] set nonblock fail %d\n", flags);  		     		
  	}   	
  
  	printf("[DEBUG] Setting send buffer to 2097152 bytes...\n");    		     	    	        	 	    		    	    		
  	int size = 2 * 1024 * 1024;	
  	if (setsockopt(m_sockFD, SOL_SOCKET, SO_SNDBUF, (void*)&size, sizeof(size)) < 0)     
  	{
  		LOG(0,"[MiSTer] Unable to set send buffer: %d\n", 2097152);        	
  	}     
#endif  
       
   	LOG(0,"[MiSTer] Sending CMD_INIT...lz4 %d sound_rate %d sound_chan %d\n", lz4Frames, soundRate, soundChan);   
   
   	m_lz4Frames = lz4Frames;
   	m_soundChan = soundChan;
   	m_rgbMode = rgbMode;
   	
   	m_bufferSend[0] = CMD_INIT;  
   	m_bufferSend[1] = (lz4Frames) ? 1 : 0; //0-RAW or 1-LZ4 ;
   	m_bufferSend[2] = (soundRate == 22050) ? 1 : (soundRate == 44100) ? 2 : (soundRate == 48000) ? 3 : 0;  
  	m_bufferSend[3] = soundChan;            
        m_bufferSend[4] = rgbMode;            
        
  	Send(&m_bufferSend[0], 5);   

#ifdef _WIN32  
if (USE_RIO)
{ 	  	
        m_rio.RIOReceive(m_requestQueue, &m_receiveRioBuffer, 1, 0, &m_receiveRioBuffer);  
}        
#endif        

        uint32_t ackTime = getACK(60);
        if (!ackTime)
        {
        	LOG(0,"[MiSTer] ACK failed with %d ms\n", 60); 
        	CmdClose();  
        	return 0;        	
        }
        else
        {
        	LOG(0,"[MiSTer] ACK received with %f ms\n", (double) ackTime / 10000);           	
        	return 1;
        }
    
}

void GroovyMister::CmdSwitchres(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace)
{	
	uint8_t interlace_modeline = (interlace != 2) ? interlace : 1;
	
	m_RGBSize = (m_rgbMode) ? (hActive * vActive) << 2 : hActive * vActive * 3;
        
        if (interlace == 1)
        {
        	m_RGBSize = m_RGBSize >> 1;	
        }
                        		
	m_widthTime = 10 * round((double) hTotal * (1 / pClock)); //in nanosec, time to raster 1 line
	m_frameTime = (m_widthTime * vTotal) >> interlace_modeline; 
	m_interlace = interlace_modeline;
	m_vTotal    = vTotal;	
		
	m_bufferSend[0] = CMD_SWITCHRES;             
	memcpy(&m_bufferSend[1],&pClock,sizeof(pClock));
	memcpy(&m_bufferSend[9],&hActive,sizeof(hActive));
	memcpy(&m_bufferSend[11],&hBegin,sizeof(hBegin));
	memcpy(&m_bufferSend[13],&hEnd,sizeof(hEnd));
	memcpy(&m_bufferSend[15],&hTotal,sizeof(hTotal));
	memcpy(&m_bufferSend[17],&vActive,sizeof(vActive));
	memcpy(&m_bufferSend[19],&vBegin,sizeof(vBegin));
	memcpy(&m_bufferSend[21],&vEnd,sizeof(vEnd));
	memcpy(&m_bufferSend[23],&vTotal,sizeof(vTotal));
	memcpy(&m_bufferSend[25],&interlace,sizeof(interlace));    
	
	Send(&m_bufferSend[0], 26);  	
}

void GroovyMister::CmdBlit(uint32_t frame, uint16_t vCountSync, uint32_t margin)
{
	m_frame = frame;
	uint16_t vSync = vCountSync;
	
	if (!vSync)
	{
		if (m_frame <= 10)
		{
			vSync = m_vTotal >> 1;
		}
		else
		{
			uint32_t timeCalc = (margin + m_emulationTime >= m_frameTime) ? 0 : margin + m_emulationTime - m_streamTime;
			vSync = (timeCalc == 0) ? 1 : m_vTotal - round(m_vTotal * timeCalc) / m_frameTime; 			
		}
	}	
	
	uint32_t cSize = 0;
	uint32_t bytesToSend = 0;	
	switch (m_lz4Frames) 
	{
		case(1): cSize = LZ4_compress_default((char *)&pBufferBlit[0], m_pBufferLZ4, m_RGBSize, m_RGBSize); 
		         break;
		case(2): cSize = LZ4_compress_HC((char *)&pBufferBlit[0], m_pBufferLZ4, m_RGBSize, m_RGBSize, LZ4HC_CLEVEL_DEFAULT); 
			 break;
	}        
   	 
	m_bufferSend[0] = CMD_BLIT_VSYNC;
   	memcpy(&m_bufferSend[1], &frame, sizeof(frame));    
   	memcpy(&m_bufferSend[5], &vSync, sizeof(vSync)); 
   	if (cSize > 0) 
   	{
   		memcpy(&m_bufferSend[7], &cSize, sizeof(cSize));  
   		bytesToSend = cSize;
   		Send(&m_bufferSend[0], 11);   	
   	} 
   	else
   	{
   		bytesToSend = m_RGBSize;
   		Send(&m_bufferSend[0], 7); 
   	}
	
	setTimeStart();	
        SendStream(0, bytesToSend, cSize);   
        setTimeEnd();
        m_streamTime = DiffTime();
        //printf("[DEBUG] Stream time %lu\n",m_streamTime);
}

void GroovyMister::CmdAudio(uint16_t soundSize)
{
   	if (!fpga.audio)
   	{
		return;
   	}	
   
   	m_bufferSend[0] = CMD_AUDIO; 
   	memcpy(&m_bufferSend[1], &soundSize, sizeof(soundSize));                               	   	    
   	Send(&m_bufferSend[0], 3);      	             	
   	
   	SendStream(1, soundSize, 0); 	              	
}

uint32_t GroovyMister::getACK(DWORD dwMilliseconds)
{	
	uint32_t getACKresult = 0;		
	uint32_t frameUDP = fpga.frameEcho;
	if (dwMilliseconds > 0)
	{
		setTimeStart();	
	}
#ifdef _WIN32 
if (USE_RIO)
{ 	  	       
	static const DWORD RIO_MAX_RESULTS = 1000;
	DWORD numberOfBytes = 0;
    	ULONG_PTR completionKey = 0;
    	OVERLAPPED* pOverlapped = 0;
    	if (::GetQueuedCompletionStatus(m_hIOCP, &numberOfBytes, &completionKey, &pOverlapped, dwMilliseconds))
    	{        	    		         	
         	RIORESULT results[RIO_MAX_RESULTS];         	         	
        	ULONG numResults = m_rio.RIODequeueCompletion(m_receiveQueue, results, RIO_MAX_RESULTS);         	 
        	ULONG idx;	        	
        	while (numResults)
        	{
        		idx=0;
        		do
        		{
	        		if (results[idx].BytesTransferred == 13) //blit ACK
	        		{       
	        			if (dwMilliseconds > 0)
					{
						setTimeEnd();
	        				getACKresult = DiffTime();
					}
					else
					{
						getACKresult = 1;
					}  		
	        			        		
	        			memcpy(&frameUDP, &m_bufferReceive[0], 4);					
					if (frameUDP > fpga.frameEcho)      
					{		   
	        				setFpgaStatus();
	        			}   
	        		}
	        		idx++;
        		} while (idx <= numResults);	     		     		        				        		        		      		
        		numResults = m_rio.RIODequeueCompletion(m_receiveQueue, results, numResults); 
        	}
        	m_rio.RIOReceive(m_requestQueue, &m_receiveRioBuffer, 1, 0, &m_receiveRioBuffer);	
    	}        	
    	m_rio.RIONotify(m_receiveQueue);  
    	return getACKresult;
}    	
#endif
	socklen_t sServerAddr = sizeof(struct sockaddr);  	
  	int len = 0;   	
  	uint32_t diff = 1;
  	uint32_t dwNanoseconds = dwMilliseconds * 10000; 
  	do
  	{  		
  		len = recvfrom(m_sockFD, m_bufferReceive, sizeof(m_bufferReceive), 0, (struct sockaddr *)&m_serverAddr, &sServerAddr);  		
  		if (dwMilliseconds > 0)
		{
			setTimeEnd();
        		diff = DiffTime();
		}
  		if (len == 13) //blit ACK
  		{  	  			
			getACKresult = diff;															  			 
        		memcpy(&frameUDP, &m_bufferReceive[0], 4);					
			if (frameUDP > fpga.frameEcho)      
			{		   
        			setFpgaStatus();
        		}	
  		}	  			
        } while ((len > 0) || (!getACKresult && dwNanoseconds > diff)); 		  	          
    	return getACKresult;
}

void GroovyMister::WaitSync()
{
	m_tickStart = m_tickSync;
	setTimeEnd();
	m_emulationTime = DiffTime(); 				
	int sleepTime = (m_emulationTime >= m_frameTime) ? 0 : m_frameTime - m_emulationTime;	
	int prevSleepTime = sleepTime;
	uint32_t realTime = 0;	
	setTimeStart();	
	do
	{
		int diffRaster = DiffTimeRaster();
		sleepTime = (diffRaster < 0 && abs(diffRaster) > sleepTime) ? 0 : sleepTime + diffRaster;		
		setTimeEnd();
		realTime = DiffTime();
		
	} while (realTime <= (uint32_t) sleepTime);
		     	 	
	m_tickSync = m_tickEnd;   

       // LOG(2,"[MiSTer] Frame %d Sleep prev=%d/final=%d/real=%d (frameTime=%d blitTime=%d emulationTime=%d) (vcount_vsync=%d/%d vcount_gpu=%d/%d)\n", m_frame, prevSleepTime, sleepTime, realTime, m_frameTime, m_streamTime, m_emulationTime, fpga.frameEcho, fpga.vCountEcho, fpga.frame, fpga.vCount);	      
        
	if (((uint32_t) sleepTime + 10000 < realTime)) //sleep?
        {
        	LOG(1,"[MiSTer] Frame %d Sleep prev=%d/final=%d/real=%d (frameTime=%d blitTime=%d emulationTime=%d) (vcount_vsync=%d/%d vcount_gpu=%d/%d)\n", m_frame, prevSleepTime, sleepTime, realTime, m_frameTime, m_streamTime, m_emulationTime, fpga.frameEcho, fpga.vCountEcho, fpga.frame, fpga.vCount);	      
	}     		
}



void GroovyMister::BindInputs(void)
{   		
	// Set server          	 	                      
	m_serverAddrInputs.sin_family = AF_INET;		
	m_serverAddrInputs.sin_port = htons(32101);
	m_serverAddrInputs.sin_addr.s_addr = htonl(INADDR_ANY);		
	// Set socket   
#ifdef _WIN32              
   	WSADATA wsd;                                           
   	uint16_t rc;      		      
   	rc = ::WSAStartup(MAKEWORD(2, 2), &wsd);
   	if (rc != 0) 
   	{
		LOG(0, "[MiSTer][Inputs] Unable to load Winsock: %d\n", rc);       
  	}              	
   	m_sockInputsFD = INVALID_SOCKET;  
	LOG(0, "[MiSTer][Inputs] Initialising socket %s...\n","");                
   	m_sockInputsFD = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);          
   	if (m_sockInputsFD == INVALID_SOCKET)
   	{
  		LOG(0,"[MiSTer][Inputs] Could not create socket : %lu", ::GetLastError());        
   	}    	   		                     	   		   		
	LOG(0,"[MiSTer][Inputs] Setting socket async %s...\n",""); 
  	u_long iMode=1;
   	rc = ioctlsocket(m_sockInputsFD, FIONBIO, &iMode); 
   	if (rc < 0)
   	{
   		LOG(0,"[MiSTer][Inputs] set nonblock fail %d\n", rc);
   	}      	
   	LOG(0,"[MiSTer][Inputs] Binding port %s...\n",""); 
   	rc = ::bind(m_sockInputsFD, (struct sockaddr *)&m_serverAddrInputs, sizeof(m_serverAddrInputs));
   	if (rc < 0)
    	{
    		LOG(0,"[MiSTer][Inputs] bind fail %d\n", rc);       	
    	}     	  						
    		   
#else	               
  	printf("[MiSTer][Inputs] Initialising socket...\n");  
  	m_sockInputsFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);				
  	if (m_sockInputsFD < 0)
  	{
  		LOG(0,"[MiSTer][Inputs] Could not create socket : %d", sockfd);      		     		
  	}              
	LOG(0,"[MiSTer][Input] Setting socket async %s...\n",""); 
  	// Non blocking socket                                                                                                     
  	int flags;
  	flags = fcntl(m_sockInputsFD, F_GETFD, 0);    	
  	if (flags < 0) 
  	{
  		LOG(0,"[MiSTer][Inputs] get falg error %d\n", flags);  		     		
  	}
  	flags |= O_NONBLOCK;
  	if (fcntl(m_sockInputsFD, F_SETFL, flags) < 0) 
  	{
  		LOG(0,"[MiSTer] set nonblock fail %d\n", flags);  		     		
  	}    	   	
  	LOG(0,"[MiSTer][Inputs] Binding port %s...\n",""); 
   	if (bind(m_sockInputsFD, (struct sockaddr *)&m_serverAddrInputs, sizeof(m_serverAddrInputs)) < 0)
    	{
    		LOG(0,"[MiSTer][Inputs] bind fail %d\n", 0);       	
    	}  	
#endif                          
}

void GroovyMister::PollInputs(void)
{
	uint32_t joyFrame = inputs.joyFrame;
	uint8_t  joyOrder = inputs.joyOrder;
	socklen_t sServerAddr = sizeof(struct sockaddr);  	
  	int len = 0;   	
  	do
  	{  	//Mednafen::MDFN_printf(_("GGGGGGGGGGGGGGGGGGGGGGGG...\n"));  	
  		len = recvfrom(m_sockInputsFD, m_bufferInputsReceive, sizeof(m_bufferInputsReceive), 0, (struct sockaddr *)&m_serverAddrInputs, &sServerAddr);    		  				
  		if (len == 9) //blit joystick
		{
			memcpy(&joyFrame, &m_bufferInputsReceive[0], 4);
			memcpy(&joyOrder, &m_bufferInputsReceive[4], 1);	        			
			if (joyFrame > inputs.joyFrame || (joyFrame == inputs.joyFrame && joyOrder > inputs.joyOrder))
			{
				setFpgaJoystick();
			}
		}  	  			
        } while (len > 0); 	  	          
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 
// PRIVATE
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifdef _WIN32 
template <typename TV, typename TM>
inline TV RoundDown(TV Value, TM Multiple)
{
	return((Value / Multiple) * Multiple);
}

template <typename TV, typename TM>
inline TV RoundUp(TV Value, TM Multiple)
{
	return(RoundDown(Value, Multiple) + (((Value % Multiple) > 0) ? Multiple : 0));
}
#endif

//get aligned memory
char *GroovyMister::AllocateBufferSpace(const DWORD bufSize, const DWORD bufCount, DWORD& totalBufferSize, DWORD& totalBufferCount)
{	
#ifdef _WIN32 	
	SYSTEM_INFO systemInfo;
	::GetSystemInfo(&systemInfo);

	const unsigned __int64 granularity = systemInfo.dwAllocationGranularity;
	const unsigned __int64 desiredSize = bufSize * bufCount;
	unsigned __int64 actualSize = RoundUp(desiredSize, granularity);

	if (actualSize > std::numeric_limits<DWORD>::max())
	{
		actualSize = (std::numeric_limits<DWORD>::max() / granularity) * granularity;
	}

	totalBufferCount = std::min<DWORD>(bufCount, static_cast<DWORD>(actualSize / bufSize));
	totalBufferSize = static_cast<DWORD>(actualSize) ;
	char *lBuffer = reinterpret_cast<char *>(VirtualAllocEx(GetCurrentProcess(), 0, totalBufferSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));

	if (lBuffer == 0)
	{
		LOG(0,"[MiSTer] VirtualAllocEx Error %lu\n", ::GetLastError());		
	}

	return lBuffer;
#else
	totalBufferSize = bufSize;
	char *lBuffer = (char*)malloc((size_t)bufSize); 
	return lBuffer;
#endif	
}


void GroovyMister::Send(void *cmd, int cmdSize)
{
#ifdef _WIN32     
if (USE_RIO)
{ 
	m_sendRioBuffer.Length = cmdSize;  	  	
  	m_rio.RIOSend(m_requestQueue, &m_sendRioBuffer, 1, RIO_MSG_DONT_NOTIFY, &m_sendRioBuffer);   		   		
  	return;
}	    
#endif
  	sendto(m_sockFD, (char *) cmd, cmdSize, 0, (struct sockaddr *)&m_serverAddr, sizeof(m_serverAddr));	   
}

void GroovyMister::SendStream(uint8_t whichBuffer, uint32_t bytesToSend, uint32_t cSize)
{	
	DWORD flags = RIO_MSG_DONT_NOTIFY | RIO_MSG_DEFER;
	uint32_t bytesSended = 0;	
#ifdef _WIN32 
if (USE_RIO)
{	             
        int i=0;
	while (bytesSended < bytesToSend)
	{			
		if (whichBuffer == 0)
		{
			m_pBufsBlit[i].Length = (bytesToSend - bytesSended >= BUFFER_MTU) ? BUFFER_MTU : bytesToSend - bytesSended;  	  	
  			m_rio.RIOSend(m_requestQueue, &m_pBufsBlit[i], 1, flags, &m_pBufsBlit[i]);					
  		}
  		else
  		{
  			m_pBufsAudio[i].Length = (bytesToSend - bytesSended >= BUFFER_MTU) ? BUFFER_MTU : bytesToSend - bytesSended;  	  	
  			m_rio.RIOSend(m_requestQueue, &m_pBufsAudio[i], 1, flags, &m_pBufsAudio[i]);					
  		}	
  		bytesSended += BUFFER_MTU;   	
  		i++;
	}
	m_rio.RIOSend(m_requestQueue, NULL, 0, RIO_MSG_COMMIT_ONLY, NULL);
	return;
}		
#endif
	while (bytesSended < bytesToSend)
	{				
		uint32_t chunkSize = (bytesToSend - bytesSended >= BUFFER_MTU) ? BUFFER_MTU : bytesToSend - bytesSended;  
		if (whichBuffer == 0)
		{
			if (cSize > 0)
			{
				Send(&m_pBufferLZ4[bytesSended], chunkSize); 
			}	  
			else
			{	  		
  				Send(&pBufferBlit[bytesSended], chunkSize); 
  			}	
  		}
  		else
  		{
  			Send(&pBufferAudio[bytesSended], chunkSize);
  		}	
  		bytesSended += BUFFER_MTU;   	  		
	}
}

inline void GroovyMister::setTimeStart(void)
{
#ifdef _WIN32
	QueryPerformanceCounter(&m_tickStart);     
#else
	clock_gettime(CLOCK_MONOTONIC, &m_tickStart);     
#endif   	
}

inline void GroovyMister::setTimeEnd(void)
{
#ifdef _WIN32
	QueryPerformanceCounter(&m_tickEnd);     
#else
	clock_gettime(CLOCK_MONOTONIC, &m_tickEnd);     
#endif 	
}
	
uint32_t GroovyMister::DiffTime(void)
{
#ifdef _WIN32
	return m_tickEnd.QuadPart - m_tickStart.QuadPart;  
#else
	uint32_t diffTime = 0;
        timespec temp;
        if ((m_tickEnd.tv_nsec - m_tickStart.tv_nsec) < 0) 
        {
                temp.tv_sec = m_tickEnd.tv_sec - m_tickStart.tv_sec - 1;
                temp.tv_nsec = 1000000000 + m_tickEnd.tv_nsec - m_tickStart.tv_nsec;
        } 
        else 
        {
                temp.tv_sec = m_tickEnd.tv_sec - m_tickStart.tv_sec;
                temp.tv_nsec = m_tickEnd.tv_nsec - m_tickStart.tv_nsec;
        }
        diffTime = (temp.tv_sec * 1000000000) + temp.tv_nsec;
        return diffTime / 100;
#endif 			
}

void GroovyMister::setFpgaStatus(void)
{
	uint8_t fpgaBits;
	memcpy(&fpga.frameEcho, &m_bufferReceive[0], 4);
	memcpy(&fpga.vCountEcho, &m_bufferReceive[4], 2);
	memcpy(&fpga.frame, &m_bufferReceive[6], 4);
	memcpy(&fpga.vCount, &m_bufferReceive[10], 2);  		  	
	memcpy(&fpgaBits, &m_bufferReceive[12], 1); 
			
	bitByte bits;  
	bits.byte = fpgaBits;
	fpga.vramReady     = bits.u.bit0;
	fpga.vramEndFrame  = bits.u.bit1;
	fpga.vramSynced    = bits.u.bit2;   
	fpga.vgaFrameskip  = bits.u.bit3;   
	fpga.vgaVblank     = bits.u.bit4;   		
	fpga.vgaF1         = bits.u.bit5;   
	fpga.audio         = bits.u.bit6;
 	fpga.vramQueue     = bits.u.bit7;
 	
 	LOG(2,"[MiSTer] ACK %d %d / %d %d / bits(%d%d%d%d%d%d%d%d)\n", fpga.frameEcho, fpga.vCountEcho, fpga.frame, fpga.vCount, fpga.vramReady, fpga.vramEndFrame, fpga.vramSynced, fpga.vgaFrameskip, fpga.vgaVblank, fpga.vgaF1, fpga.audio, fpga.vramQueue); 	 	
}

void GroovyMister::setFpgaJoystick(void)
{		
	memcpy(&inputs.joyFrame, &m_bufferInputsReceive[0], 4);
	memcpy(&inputs.joyOrder, &m_bufferInputsReceive[4], 1);
	memcpy(&inputs.joy1, &m_bufferInputsReceive[5], 2);
	memcpy(&inputs.joy2, &m_bufferInputsReceive[7], 2);  		  		
				 	
 	LOG(2,"[MiSTer] JOY %d %d / %d %d\n", inputs.joyFrame, inputs.joyOrder, inputs.joy1, inputs.joy2);
}

int GroovyMister::DiffTimeRaster(void)
{
	uint32_t frameEcho = fpga.frameEcho;
	int diffTime = 0;		
	if (m_frame != fpga.frameEcho)
	{
		getACK(0);		
	}	
	if (fpga.frameEcho != frameEcho)
	{
		//patch if emulator freezes to align frame counter
		/*
  		if ((fpga.frameEcho + 1) < fpga.frame) 
  		{  		
  			LOG(2,"[MiSTer] patch %d (patched=%d) %d / %d %d \n", fpga.frameEcho, fpga.frame + 1, fpga.vCountEcho, fpga.frame, fpga.vCount);
  	 		fpga.frameEcho = fpga.frame + 1;  	  	 		 		
  		}*/
		LOG(2,"[MiSTer] echo %d %d / %d %d \n", fpga.frameEcho, fpga.vCountEcho, fpga.frame, fpga.vCount);
		uint32_t vCount1 = ((fpga.frameEcho - 1) * m_vTotal + fpga.vCountEcho) >> m_interlace;
		uint32_t vCount2 = (fpga.frame * m_vTotal + fpga.vCount) >> m_interlace;
		int dif = (int) (vCount1 - vCount2) / 2; //dicotomic
	  	 
		diffTime = (int) (m_widthTime * dif);  	
	}
	return diffTime;
}