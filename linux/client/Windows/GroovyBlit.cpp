
#include <mednafen/lz4/lz4.h>

#define CMD_BLIT 4

static void GroovyBlit(uint32_t frame, uint16_t vsync, uint16_t line_width)
{	            	        
   int err = 0;
   uint16_t rc;   
         	 		 	   
   char buffer[9];
   
   buffer[0] = CMD_BLIT;
   memcpy(&buffer[1], &frame, sizeof(frame));    
   memcpy(&buffer[5], &vsync, sizeof(vsync));    // if != 0, server will send ack with get_status on this vcount line
   DataBuf.len = 7;  	
  
   if (PoC_Compression) // updated block size 
   {   	    
   	uint16_t blockSize = (line_width << 4) * 3; // 16 lines;   	
   	buffer[7] = (uint16_t) blockSize & 0xff;
        buffer[8] = (uint16_t) blockSize >> 8;
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
	   	MDFN_printf(_("WSASend blit failed with error: %d\n"), err);   	
	   }      
	   
	   rc = WSAWaitForMultipleEvents(1, &Overlapped.hEvent, TRUE, WSA_INFINITE, TRUE);   
	   if (rc == WSA_WAIT_FAILED) 
	   {
	        MDFN_printf(_("WSAWaitForMultipleEvents blit failed with error: %d\n"), WSAGetLastError());      
	   }
	   
	   rc = WSAGetOverlappedResult(sockfd, &Overlapped, &SendBytes, FALSE, &Flags);		   
	   if (rc == FALSE) 
	   {
	        MDFN_printf(_("WSAGetOverlapped blit failed with error: %d\n"), WSAGetLastError());      
	   }
	   
	   WSAResetEvent(Overlapped.hEvent);             
   }
}   

// after blit, for send packets with mtu limit (can be used for send raw rgb with isLZ4 = 0)
static void GroovySendMTU(char *buffer, uint32_t bufSize, uint8_t isLZ4)
{	            	        
   int err = 0;
   uint16_t rc = 0;
   DWORD SendBytes = 0;       	     	 		 	
   DWORD Flags = 0;
   uint32_t bufferOffset = 0;         
   uint16_t chunk_blockSize = (isLZ4 && bufSize > 1472) ? 1472 : (bufSize > 1470) ? 1470 : bufSize; //for LZ4, reach max MTU (raw frames isn't divisible)
         		 	 	 	       		 	   	    	   	   	             	 	                      	  	
   for (;;)
   { 	    		   	   		   	 		
   	DataBuf.len = chunk_blockSize;
        DataBuf.buf = (char *) &buffer[bufferOffset];   
   
   	rc = WSASendTo(sockfd, &DataBuf, 1, &SendBytes, 0, (SOCKADDR*) &ServerAddr, sizeof(ServerAddr), &Overlapped, NULL);
   	if (rc != 0)
   	{
   	   	if ((rc == SOCKET_ERROR) && (WSA_IO_PENDING != (err = WSAGetLastError()))) 
   		{
   			MDFN_printf(_("WSASend failed with error: %d\n"), err);   	
   		}
   		
   		rc = WSAWaitForMultipleEvents(1, &Overlapped.hEvent, TRUE, WSA_INFINITE, TRUE);   
   		if (rc == WSA_WAIT_FAILED) 
   		{
   		        MDFN_printf(_("WSAWaitForMultipleEvents failed with error: %d\n"), WSAGetLastError());      
   		}
   		   
   		rc = WSAGetOverlappedResult(sockfd, &Overlapped, &SendBytes, FALSE, &Flags);	
   		if (rc == FALSE) 
   		{
   		        MDFN_printf(_("WSAGetOverlapped failed with error: %d\n"), WSAGetLastError());      
     	        }
     	        
   		WSAResetEvent(Overlapped.hEvent);		 		 		 					 		    		 		   		 		 		 				 		   	
   	}
   	
   	bufferOffset += chunk_blockSize; 	
   	 		 		 				 		 			 		
   	chunk_blockSize = (bufSize - bufferOffset < chunk_blockSize) ? bufSize - bufferOffset : chunk_blockSize;
   	   	 	   	 		 		
   	if (chunk_blockSize == 0)
   	{
   		break;
   	} 	 		 		
   } 				 		
}

// after blit, for send rgb with lz4stream, this uses GroovySendMTU as well 
static void GroovyBlitLZ4(char* bufferRGB, uint32_t bufSize, uint16_t line_width)
{	
	uint16_t blockSize = (line_width << 4) * 3; // 16 lines;   
	
	LZ4_stream_t lz4Stream_body;
    	LZ4_stream_t* lz4Stream = &lz4Stream_body;
    	LZ4_initStream(lz4Stream, sizeof (*lz4Stream));	
    	
	char cmpBuf[LZ4_COMPRESSBOUND(blockSize)+2];			
	uint32_t bufferOffset = 0;	
	char inpBuf[2][blockSize+1];	
    	int  inpBufIndex = 0;
	
	
	// test decompress
	/*
	char uncmpBytes[2][65536]; 
	uint8_t decBufIndex = 0;
	LZ4_streamDecode_t lz4StreamDecode_body;
	LZ4_streamDecode_t* lz4StreamDecode = &lz4StreamDecode_body;	
	LZ4_setStreamDecode(lz4StreamDecode, NULL, 0);
	*/
	
	// double buffer method
	//*
	//*  Note 2 : The previous 64KB of source data is __assumed__ to remain present, unmodified, at same address in memory !
 	//*
 	//*  Note 3 : When input is structured as a double-buffer, each buffer can have any size, including < 64 KB.
 	//*           Make sure that buffers are separated, by at least one byte.
 	//*           This construction ensures that each block only depends on previous block.	
	for (;;)
	{		
		const int inpBytes = (bufSize - bufferOffset < blockSize) ? bufSize - bufferOffset : blockSize;
		
		if (inpBytes == 0)
		{
			break;
		}
	        
	        char* const inpPtr = inpBuf[inpBufIndex];	        
	        memcpy((char *) &inpPtr[0], (char *) &bufferRGB[bufferOffset], inpBytes);
	        
		const uint16_t cSize = LZ4_compress_fast_continue(lz4Stream, inpPtr, (char *) &cmpBuf[2], inpBytes, sizeof(cmpBuf), 1); 
				
		cmpBuf[0] = (uint16_t) cSize & 0xff;
        	cmpBuf[1] = (uint16_t) cSize >> 8;
		
		//MDFN_printf(_("chunk_compressed_size %d bytes %d offset %d inbytes\n"), cSize, bufferOffset, inpBytes);
		
		/*
		// test decomp		
		char* const decPtr = uncmpBytes[decBufIndex];  				
		const int decBytes = LZ4_decompress_safe_continue(lz4StreamDecode, (char *) &cmpBuf[2], decPtr, cSize, blockSize);	
		//const int decBytes = LZ4_decompress_fast_continue(lz4StreamDecode, (char *) &cmpBuf[2], decPtr, inpBytes);	
		int c = memcmp((char *)&bufferRGB[bufferOffset], (char *) &decPtr[0], decBytes);
		MDFN_printf(_("chunk_compressed_size %d bytes, decompress %d bytes! cmp=%d\n"), cSize, decBytes,c);
		decBufIndex = (decBufIndex + 1) % 2;
		*/
		
		GroovySendMTU((char *) &cmpBuf[0], cSize + 2, 1);											 				
		
		bufferOffset += inpBytes;
		inpBufIndex = (inpBufIndex + 1) % 2;
	}
	
}

//on main
//...
   GroovyBlit(PoC_frame, 120, line_width);
   if (PoC_Compression == 0)   
   	GroovySendMTU((char *)&tmp_buffer[0], totalPixels * 3, 0);
   else	
   	GroovyBlitLZ4((char *)&tmp_buffer[0], totalPixels * 3, line_width);
//...   	
   	