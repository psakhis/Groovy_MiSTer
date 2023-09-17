
static void PoC_Init()
{   
   WSADATA wsa;
   printf("[DEBUG] Initialising Winsock...");	
   int res = WSAStartup(MAKEWORD(2,2),&wsa);
   if (res != NO_ERROR)
   {
      printf("Failed. Error code : %d",WSAGetLastError());    
   }
   printf("done.\n");	
   printf("[DEBUG] Initialising socket...");
   sockfd = INVALID_SOCKET;
   sockfd = socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
 
   if (sockfd == INVALID_SOCKET)
   {
     printf("Could not create socket : %d",WSAGetLastError());     
   }  
   printf("done.\n");
   
   struct sockaddr_in ServerAddr;   
   struct sockaddr_in ServerAddr2;       
   short port = 32100;    
   const char* local_host = "192.168.137.137";

   ServerAddr.sin_family = AF_INET;
   ServerAddr.sin_port = htons(port);
   ServerAddr.sin_addr.s_addr = inet_addr(local_host);

   
   // Connect to server.   
   printf("[DEBUG] Connect to the server...");	
   int iResult = connect(sockfd, (SOCKADDR*) &ServerAddr, sizeof(ServerAddr) );            
   if (iResult == SOCKET_ERROR) 
   {
        printf("Connect failed with error: %d\n", WSAGetLastError() );
        closesocket(sockfd);
        WSACleanup();      
  }
  printf("done.\n");
  
  printf("[DEBUG] Socket non blocking...");	
  int timeout = 1000; //ms
  setsockopt(sockfd,SOL_SOCKET,SO_RCVTIMEO,(char *)&timeout,sizeof(int)); 
  printf("done.\n");
  
  char SendBuf[27];
  printf("[DEBUG] Sending CMD_INIT...");	
  SendBuf[0] = 0x02;     //CMD_INIT
  SendBuf[1] = PoC_Compression; //1-ZSTD 2-LZ4 3-LZHC
  int clientResult = send(sockfd,SendBuf,2,0);

  if (clientResult == SOCKET_ERROR)
  {
      	printf("[DEBUG] Sending back response got an error: %d\n", WSAGetLastError());
      	WSACleanup();
  }
  printf("done.\n");    
  
  double px = 0;
  uint16_t udp_hactive = 0;			      
  uint16_t udp_hbegin = 0;
  uint16_t udp_hend = 0;
  uint16_t udp_htotal = 0;
  uint16_t udp_vactive = 0;
  uint16_t udp_vbegin = 0;
  uint16_t udp_vend = 0;
  uint16_t udp_vtotal = 0;
  uint8_t  udp_interlace = 0; 
  
  const std::string str_sms = "sms";
  const std::string str_nes = "nes";
  const std::string str_snes = "snes";
  const std::string str_md = "md";
  if (!std::string(CurGame->shortname).compare(str_sms)) 
  { 	printf("Modeline SMS\n");
	px = 5.176785;      
	udp_hactive = 256;			      
	udp_hbegin = 266;
	udp_hend = 290;
	udp_htotal = 331;
	udp_vactive = 240;
	udp_vbegin = 242;
	udp_vend = 245;
	udp_vtotal = 261;
	udp_interlace = 0;    
  }
  if (!std::string(CurGame->shortname).compare(str_snes)) 
  { 	printf("Modeline SNES\n");
	px = 5.172103;      
	udp_hactive = 256;			      
	udp_hbegin = 266;
	udp_hend = 290;
	udp_htotal = 331;
	udp_vactive = 240;
	udp_vbegin = 241;
	udp_vend = 244;
	udp_vtotal = 260;
	udp_interlace = 0;    
  }
  if (!std::string(CurGame->shortname).compare(str_nes)) 
  { 	printf("Modeline NES\n");
	px = 5.172103;      
	udp_hactive = 256;			      
	udp_hbegin = 266;
	udp_hend = 290;
	udp_htotal = 331;
	udp_vactive = 240;
	udp_vbegin = 241;
	udp_vend = 244;
	udp_vtotal = 260;
	udp_interlace = 0;    
  }  	
  
  if (!std::string(CurGame->shortname).compare(str_md)) 
  { 	printf("Modeline MD\n");
	px = 6.506171;      
	udp_hactive = 320;			      
	udp_hbegin = 333;
	udp_hend = 364;
	udp_htotal = 416;
	udp_vactive = 240;
	udp_vbegin = 242;
	udp_vend = 245;
	udp_vtotal = 261;
	udp_interlace = 0;    
  } 

  PoC_width = udp_hactive; 
  
  SendBuf[0] = 0x03; //CMD_SWITCHRES
  
  printf("[DEBUG] Sending CMD_SWITCHRES...");  
  SendBuf[0] = 0x03;      
  memcpy(&SendBuf[1],&px,sizeof(px));
  memcpy(&SendBuf[9],&udp_hactive,sizeof(udp_hactive));
  memcpy(&SendBuf[11],&udp_hbegin,sizeof(udp_hbegin));
  memcpy(&SendBuf[13],&udp_hend,sizeof(udp_hend));
  memcpy(&SendBuf[15],&udp_htotal,sizeof(udp_htotal));
  memcpy(&SendBuf[17],&udp_vactive,sizeof(udp_vactive));
  memcpy(&SendBuf[19],&udp_vbegin,sizeof(udp_vbegin));
  memcpy(&SendBuf[21],&udp_vend,sizeof(udp_vend));
  memcpy(&SendBuf[23],&udp_vtotal,sizeof(udp_vtotal));
  memcpy(&SendBuf[25],&udp_interlace,sizeof(udp_interlace));      
  clientResult = send(sockfd,SendBuf,26,0);
  
  if (clientResult == SOCKET_ERROR)
  {
      	printf("[DEBUG] Sending back response got an error: %d\n", WSAGetLastError());
      	WSACleanup();
  }
  printf("done.\n");	
  PoC_start = 1;
  PoC_frame = 0;
}