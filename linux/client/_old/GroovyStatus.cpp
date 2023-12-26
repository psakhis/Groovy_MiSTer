
#define CMD_GET_STATUS 5

static char bufferRecv[6];

//this waits and ack from server 
static void GroovyWaitStatus()
{	
   int err = 0;
   uint16_t rc;       	     	 		 	
   DWORD Flags = 0;    
        	 
   DWORD BytesRecv;   
   DWORD timeout = INFINITE;  //can be set timeout in ms
   int sSender = sizeof(ServerAddr);  
      	                   	   
   DataBufRecv.len = 6;
   DataBufRecv.buf = bufferRecv;   	   	 
   
   for(;;)
   {   
	   rc = WSARecvFrom(sockfd, &DataBufRecv, 1, &BytesRecv, &Flags, (SOCKADDR *) &ServerAddr, &sSender, &OverlappedRecv, NULL);  
	   if (rc != 0)
	   {
		if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
	   	{
	   		MDFN_printf(_("WSARecvFrom get status failed with error: %d\n"), err);   	
	   	}      
	   
		rc = WSAWaitForMultipleEvents(1, &OverlappedRecv.hEvent, TRUE, timeout, TRUE);   
		if (rc == WSA_WAIT_TIMEOUT) 
		{
		        //MDFN_printf(_("WSAWaitForMultipleEvents get status timeout\n"));  
		        WSAResetEvent(OverlappedRecv.hEvent); 		      
		        break;    	      
		}
		if (rc == WSA_WAIT_FAILED) 
		{
		        MDFN_printf(_("WSAWaitForMultipleEvents get status failed with error: %d\n"), WSAGetLastError());      
		}
		   
		rc = WSAGetOverlappedResult(sockfd, &OverlappedRecv, &BytesRecv, FALSE, &Flags);	// non blocking	   
		if (rc == FALSE) 
		{
		        MDFN_printf(_("WSAGetOverlapped get status failed with error: %d\n"), WSAGetLastError());      
		}
		   
		WSAResetEvent(OverlappedRecv.hEvent);   			
	   }
	   
	   uint16_t vcount = 0;
	   memcpy(&vcount,&DataBufRecv.buf[0],2);
	   uint32_t frame = 0;
	   memcpy(&frame,&DataBufRecv.buf[2],4); 		
	   //MDFN_printf(_("vcount=%d,frame=%d\n"), vcount, frame);	
	   
	   if (frame >= PoC_frame)
	   {	   	
	   	break;	   	
	   } 	   
   }   		   	        
}


//example requesting a status on any moment
static void GroovyStatus()
{	
   int err = 0;
   uint16_t rc;
   DWORD SendBytes;       	     	 		 	
   DWORD Flags;    
        	 
   DWORD BytesRecv;   
   DWORD timeout;  
   int sSender = sizeof(ServerAddr);  
   
   char buffer[1];    	  
   
   buffer[0] = CMD_GET_STATUS;    
       	   	     
   int i = 0;	         
        
   for (;;)
   {
   	DataBuf.len = 1;
   	DataBuf.buf = buffer;
   	rc = WSASendTo(sockfd, &DataBuf, 1, &SendBytes, 0, (SOCKADDR*) &ServerAddr, sizeof(ServerAddr), &Overlapped, NULL);
   	if (rc != 0)
   	{
   		if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
	   	{
	   		MDFN_printf(_("WSASend req status failed with error: %d\n"), err);   	
	   	}      
	   
		rc = WSAWaitForMultipleEvents(1, &Overlapped.hEvent, TRUE, WSA_INFINITE, TRUE);   
		if (rc == WSA_WAIT_FAILED) 
		{
		        MDFN_printf(_("WSAWaitForMultipleEvents req status failed with error: %d\n"), WSAGetLastError());      
		}
		   
		rc = WSAGetOverlappedResult(sockfd, &Overlapped, &SendBytes, FALSE, &Flags);	// non blocking	   
		if (rc == FALSE) 
		{
		        MDFN_printf(_("WSAGetOverlapped req status failed with error: %d\n"), WSAGetLastError());      
		}
		   
		WSAResetEvent(Overlapped.hEvent);             
   	}
   	
   	Flags = 0;   	
   	DataBufRecv.len = 6;
   	DataBufRecv.buf = bufferRecv;
   	   	   	   	  	     	
   	timeout = 2; // timeout in 2ms
   	
   	rc = WSARecvFrom(sockfd, &DataBufRecv, 1, &BytesRecv, &Flags, (SOCKADDR *) &ServerAddr, &sSender, &OverlappedRecv, CompletGetStatus);  
   	if (rc != 0)
   	{
   		if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
	   	{
	   		MDFN_printf(_("WSARecvFrom get status failed with error: %d\n"), err);   	
	   	}      
	   
		rc = WSAWaitForMultipleEvents(1, &OverlappedRecv.hEvent, FALSE, WSA_INFINITE, TRUE);   
		if (rc == WSA_WAIT_TIMEOUT) 
		{
		        MDFN_printf(_("WSAWaitForMultipleEvents get status timeout\n"));      
		        break;
		}
		if (rc == WSA_WAIT_FAILED) 
		{
		        MDFN_printf(_("WSAWaitForMultipleEvents get status failed with error: %d\n"), WSAGetLastError());      
		}
		   						          
   	}   
   	
   	uint16_t vcount = 0;
	memcpy(&vcount,&DataBufRecv.buf[0],2);
	uint32_t frame = 0;
	memcpy(&frame,&DataBufRecv.buf[2],4); 		
	//MDFN_printf(_("vcount=%d,frame=%d\n"), vcount, frame);		   	
   	
	break;
		   	
   }
            	
 
   
   
}

