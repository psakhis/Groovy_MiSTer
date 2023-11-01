
#ifdef WIN32
 #include <winsock2.h>  
 #include <ws2tcpip.h> 
#endif

#define CMD_CLOSE 1
#define CMD_INIT 2

static WSABUF DataBuf;
static WSABUF DataBufRecv;
static WSAOVERLAPPED Overlapped;
static WSAOVERLAPPED OverlappedRecv;
static SOCKET sockfd; 
static struct sockaddr_in ServerAddr; 

static int PoC_Compression = 1; //0-RAW or 1-LZ4 

static void GroovyInit()
{   
   WSADATA wsd;       
   sockfd = INVALID_SOCKET;                               
   
   int err = 0;
   uint16_t rc;
   
   MDFN_printf(_("[DEBUG] Initialising Winsock...\n"));   	
   // Load Winsock
   rc = WSAStartup(MAKEWORD(2, 2), &wsd);
   if (rc != 0) 
   {
	MDFN_printf(_("Unable to load Winsock: %d\n"), rc);       
   }
   MDFN_printf(_("done.\n"));	     
    
   MDFN_printf(_("[DEBUG] Initialising socket overlapped...\n"));                
   sockfd = WSASocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, NULL, 0, WSA_FLAG_OVERLAPPED);
          
   if (sockfd == INVALID_SOCKET)
   {
     	MDFN_printf(_("Could not create socket : %d"),WSAGetLastError());        
   }    
   
   // Set server  
   short port = 32100;      
   const char* local_host = "192.168.137.136";   
     	                       
   ServerAddr.sin_family = AF_INET;
   ServerAddr.sin_port = htons(port);
   ServerAddr.sin_addr.s_addr = inet_addr(local_host);                              
  
   // Make sure the Overlapped struct is zeroed out
   SecureZeroMemory((PVOID) &Overlapped, sizeof (WSAOVERLAPPED));       
   
   // Create a event handler setup the overlapped structure.
   Overlapped.hEvent = WSACreateEvent();        
   
   // Make sure the Overlapped struct is zeroed out
   SecureZeroMemory((PVOID) &OverlappedRecv, sizeof (WSAOVERLAPPED));       
   
   // Create a event handler setup the overlapped structure.
   OverlappedRecv.hEvent = WSACreateEvent();        
   
   if (Overlapped.hEvent == NULL || OverlappedRecv.hEvent == NULL) 
   {
        MDFN_printf(_("WSACreateEvent failed with error: %d\n"), WSAGetLastError());              
   }
   MDFN_printf(_("done.\n"));
   
   MDFN_printf(_("[DEBUG] Setting send buffer to 2097152 bytes...\n"));	    
   int optVal = 2097152;  
   int optLen = sizeof(int);
   rc = setsockopt(sockfd, SOL_SOCKET, SO_SNDBUF, (char*)&optVal, optLen);
   if (rc != 0) 
   {
	MDFN_printf(_("Unable to set send buffer: %d\n"), rc);       
   }    
   
   MDFN_printf(_("[DEBUG] Sending CMD_INIT...\n"));
    
   char buffer[4];         
   buffer[0] = CMD_INIT;  
   buffer[1] = PoC_Compression; //0-RAW or 1-LZ4 
   
   DataBuf.len = 2;
      
   if (PoC_Compression) // default blocks size (can be updated on blits)
   {   	    
   	uint16_t blockSize = 8192; 
   	buffer[2] = (uint16_t) blockSize & 0xff;
        buffer[3] = (uint16_t) blockSize >> 8;
        DataBuf.len += 2;
   }
     
   DataBuf.buf = buffer;
   	   
   DWORD SendBytes;     
   DWORD Flags;
       
   rc = WSASendTo(sockfd, &DataBuf, 1, &SendBytes, 0, (SOCKADDR*) &ServerAddr, sizeof(ServerAddr), &Overlapped, NULL);
   if (rc != 0)
   {
	   if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
	   {
	   	MDFN_printf(_("WSASend init failed with error: %d\n"), err);   	
	   }
	   
	   rc = WSAWaitForMultipleEvents(1, &Overlapped.hEvent, TRUE, WSA_INFINITE, TRUE);
	   if (rc == WSA_WAIT_FAILED) 
	   {
	        MDFN_printf(_("WSAWaitForMultipleEvents init failed with error: %d\n"), WSAGetLastError());      
	   }
	   
	   rc = WSAGetOverlappedResult(sockfd, &Overlapped, &SendBytes, FALSE, &Flags);	
	   if (rc == FALSE) 
	   {
	        MDFN_printf(_("WSAGetOverlapped init failed with error: %d\n"), WSAGetLastError());      
	   }
	             
	   WSAResetEvent(Overlapped.hEvent);
   }
   
}