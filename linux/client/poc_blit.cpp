
static int PoC_Compress(int idCompress, char *bufferCompressed, const char *bufferRGB, uint32_t bufSize)
{  	
  switch(PoC_Compression)
  { 
   	case 1: // ZSTD
   	{
   		size_t const buffSize_ZSTD = ZSTD_compressBound((size_t)bufSize);   		   	
   		return ZSTD_compress(bufferCompressed, buffSize_ZSTD, &bufferRGB[0], (size_t) bufSize, 1);         	       		     		
   	} break;
   	case 2: // LZ4
   	{
   		size_t const buffSize_LZ4 = LZ4_compressBound((size_t)bufSize);   		 		      				   
   		return LZ4_compress_default((const char *)&bufferRGB[0], bufferCompressed, (size_t) bufSize, buffSize_LZ4);     		   		
   	} break;
   	case 3: // LZ4HC
   	{
   		size_t const buffSize_LZ4 = LZ4_compressBound((size_t)bufSize);   		  		   
   		return LZ4_compress_HC((const char *)&bufferRGB[0], bufferCompressed, (size_t) bufSize, buffSize_LZ4, LZ4HC_CLEVEL_DEFAULT); 
   	} break;		

 }
 return 0;	
	
}

//frame to frame
static void PoC_Blit(int idCompress, const char *bufferRGB, uint16_t bufSize, uint8_t frame, uint32_t pixels_frame)
{
 int size = 0;
 uint32_t offset = 0; 
 char *send_buffer;
 send_buffer = (char *)malloc((size_t)65536);      
 uint32_t pixel_len = 0; 
 pixel_len = 21800; //multiple x8
 
 char *buffCompressed;
 int cSize;
   
 send_buffer[0] = 0x04;    
 memcpy(&send_buffer[1],&frame,1);    
 memcpy(&send_buffer[2],&offset,4);
 memcpy(&send_buffer[6],&pixel_len,4); 
 
 if (idCompress > 0) 
 {
 	buffCompressed = (char *)malloc((size_t)65536); 	   	   	
 	cSize = PoC_Compress(idCompress, &buffCompressed[0], &bufferRGB[0], pixel_len * 3);
 	memcpy(&send_buffer[10],&buffCompressed[0], cSize);  
 	free(buffCompressed);
 }
 else   memcpy(&send_buffer[10],&bufferRGB[0],pixel_len * 3);  
    	
 int sendFrame = 1; 
 uint32_t total_pixels = 0;
 while (sendFrame)
 {
 	total_pixels += pixel_len; 
 	size = (idCompress == 0) ? 10 + (pixel_len * 3) : 10 + cSize; 
 	int clientResult = send(sockfd, send_buffer, size, 0);   	   	   	
 	if (clientResult == SOCKET_ERROR)
 	{
		printf("[DEBUG] Sending back response got an error: %d\n", WSAGetLastError());
      		WSACleanup();
 	}   
 	if (total_pixels >= pixels_frame) 
 	 	sendFrame = 0;
 	else
 	{ 	 		 		
 		offset += pixel_len;	 
   		if (offset + pixel_len > pixels_frame) 
   	 		pixel_len = pixels_frame - offset;
   	 	   	 	
   	 	memcpy(&send_buffer[2],&offset,4);
 		memcpy(&send_buffer[6],&pixel_len,4); 
 		
 		if (idCompress > 0) 
 		{
 			buffCompressed = (char *)malloc((size_t)65536); 	   	   	
 			cSize = PoC_Compress(idCompress, &buffCompressed[0], &bufferRGB[offset * 3], pixel_len * 3);
 			memcpy(&send_buffer[10],&buffCompressed[0], cSize);  
 			free(buffCompressed);
 		}
 		else   memcpy(&send_buffer[10],&bufferRGB[offset * 3],pixel_len * 3);   		 		   		
 	} 	
 	
 }		 	
	
}


 if (PoC_Compression > 0)
   {
   	char *buffCompressed = (char *)malloc((size_t)65536); 	   	   	
   	int cSize = PoC_Compress(PoC_Compression, &buffCompressed[0], (const char *)&tmp_buffer[0], tmp_inc);
   	  	  	
   	PoC_frame = (PoC_frame < 60) ?  PoC_frame + 1 : 1;    	
  
   	PoC_Blit(PoC_Compression, (const char *)&tmp_buffer[0], tmp_inc, PoC_frame, totalPixels); //same packets than raw
   		
   	free(buffCompressed);
   	
   	
   	gettimeofday(&stop, NULL);				   
  	msACK = ((stop.tv_sec - start.tv_sec) * 1000000 + stop.tv_usec - start.tv_usec) / 1000;	
   }

   else
   {
   	PoC_frame = (PoC_frame < 60) ?  PoC_frame + 1 : 1; 	
   	PoC_Blit(PoC_Compression, (const char *)&tmp_buffer[0], tmp_inc, PoC_frame, totalPixels);                 
   }
	             	
 }
 
 
