
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

#include "../../fpga_io.h"
#include "../../spi.h"

// FPGA SPI commands
#define UIO_GET_VCOUNT    0xf0 


// Groovy UDP server 
#define UDP_PORT 32101
#define CMD_GET_VCOUNT 5
//#define CMD_SET_VCOUNT 6

/* General Server variables */
static int groovyServer = 0;
static int sockfd;
static struct sockaddr_in clientaddr;
static socklen_t clilen = sizeof(struct sockaddr); 

static int groovy_start()
{		
	printf("Groovy-Server 0.1 starting\n");
		
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
    
        // Non blocking socket        
    	int flags;
    	flags = fcntl(sockfd, F_GETFD, 0);
    	if (flags < 0) 
    	{
      		printf("get falg error\n");
       		return -1;
    	}
    	flags |= O_NONBLOCK;
    	if (fcntl(sockfd, F_SETFL, flags) < 0) 
    	{
       		printf("set nonblock fail\n");
       		return -1;
    	}     	   	    	
	
	int beTrue = 1;
	setsockopt(sockfd,SOL_SOCKET,SO_REUSEADDR,&beTrue,sizeof(int));
 
    	if (bind(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) < 0)
    	{
    		printf("bind error\n");
        	return -1;
    	}            	    	    	
    	
    	printf("Groovy-Server 0.1 started\n");
    			    	            
        return 1;
        
		
}

void groovy_stop()
{
	close(sockfd);
}

void groovy_poll()
{	
	char recvbuf[1] = { 0 };   
	char sendbuf[2] = { 0 }; 
    	int len = 0;         	
        //static struct timeval start; 
        
	if (groovyServer != 1) groovyServer = groovy_start();	 
	 
	len = recvfrom(sockfd, recvbuf, sizeof(recvbuf), 0, (struct sockaddr *)&clientaddr, &clilen);
	
	if (len > 0) 
    	{
    		//log(0,"command: %i\n", recvbuf[0]);
    		switch (recvbuf[0]) 
    		{			
			case CMD_GET_VCOUNT:
			{	
				//gettimeofday(&start, NULL); 			   
				//printf("REQ %ld.%06ld\n", start.tv_sec, start.tv_usec);    	       							  
			    	uint16_t req = 0;
			    	uint16_t vcount = 0;
			    	while (!req)
			    	{
			        	req = spi_uio_cmd_cont(UIO_GET_VCOUNT);
			        	if (req) vcount = spi_w(0);   
    			        	DisableIO();      			        				        	
    			    	}
    			    	//gettimeofday(&start, NULL); 			   
				//printf("SPI %ld.%06ld vcount=%d\n", start.tv_sec, start.tv_usec, vcount);    	       							  
    			    	
			       	//data[0] = CMD_SET_VCOUNT;
			       	sendbuf[0] = vcount & 0xff;        
    				sendbuf[1] = vcount >> 8;			        
			        sendto(sockfd, sendbuf, sizeof(sendbuf), 0, (struct sockaddr *)&clientaddr, clilen);	     			       
			}; break;
		}
	}	
						
}
