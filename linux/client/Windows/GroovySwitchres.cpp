
#define CMD_SWITCHRES 3

static void GroovySwitchres()
{
   int err = 0;
   uint16_t rc;
           
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
   if (!std::string(CurGame->shortname).compare(str_sms)) 
   { 	
   	printf("Modeline SMS\n");
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
   
   char buffer[27];   
   
   printf("[DEBUG] Sending CMD_SWITCHRES...\n"); 
   buffer[0] = CMD_SWITCHRES;             
   memcpy(&buffer[1],&px,sizeof(px));
   memcpy(&buffer[9],&udp_hactive,sizeof(udp_hactive));
   memcpy(&buffer[11],&udp_hbegin,sizeof(udp_hbegin));
   memcpy(&buffer[13],&udp_hend,sizeof(udp_hend));
   memcpy(&buffer[15],&udp_htotal,sizeof(udp_htotal));
   memcpy(&buffer[17],&udp_vactive,sizeof(udp_vactive));
   memcpy(&buffer[19],&udp_vbegin,sizeof(udp_vbegin));
   memcpy(&buffer[21],&udp_vend,sizeof(udp_vend));
   memcpy(&buffer[23],&udp_vtotal,sizeof(udp_vtotal));
   memcpy(&buffer[25],&udp_interlace,sizeof(udp_interlace));    
    
   DataBuf.len = 27;
   DataBuf.buf = buffer;
   	   
   DWORD SendBytes;  
   DWORD Flags;      
          
   rc = WSASendTo(sockfd, &DataBuf, 1, &SendBytes, 0, (SOCKADDR*) &ServerAddr, sizeof(ServerAddr), &Overlapped, NULL);
   if (rc != 0)
   {
	   if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
	   {
	   	MDFN_printf(_("WSASend switchres failed with error: %d\n"), err);   	
	   }      
	   
	   rc = WSAWaitForMultipleEvents(1, &Overlapped.hEvent, TRUE, WSA_INFINITE, TRUE);
	   if (rc == WSA_WAIT_FAILED) 
	   {
	        MDFN_printf(_("WSAWaitForMultipleEvents switchres failed with error: %d\n"), WSAGetLastError());      
	   }
	   
	   rc = WSAGetOverlappedResult(sockfd, &Overlapped, &SendBytes, FALSE, &Flags);	
	   if (rc == FALSE) 
	   {
	        MDFN_printf(_("WSAGetOverlapped switchres failed with error: %d\n"), WSAGetLastError());      
	   }
	   
	   WSAResetEvent(Overlapped.hEvent);  
   }             
}