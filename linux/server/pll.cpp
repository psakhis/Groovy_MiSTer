
#include <math.h>
#include <time.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/types.h>

#include "pll.h"

#define REF_CLOCK       50    //reference clock
#define MIN_CLOCK      300    //min clock freq
#define MAX_CLOCK     1000    //max clock freq

#define MIN_N            1    //min divide factor
#define MAX_N            7    //max divide factor

#define MIN_M            1    //min mult factor
#define MAX_M           95    //max mult factor


int getMinC(double const px) 
{
	int C = 0;	
	double clock = 0;	
	while (clock < MIN_CLOCK) 
	{
		clock = clock + px;
		C++;	
	}		
	return C;
}

int getMaxC(double const px) 
{
	int C = 0;	
	double clock = 0;	
	while (clock < MAX_CLOCK) 
	{
		clock = clock + px;
		C++;	
	}		
	return C;
}

double getMNC(double const px, int &M, int &N, int &C)
{	
	bool stopN = false;
	double error = 9;
	M = MIN_M;
	N = MIN_N;
	C = 0;	
	int C1 = getMinC(px);	
	int C2 = getMaxC(px);
	for (int c = C1; c <= C2; c++)
	{
		double clock = c * px;			
		if (clock >= MIN_CLOCK && clock <= MAX_CLOCK) 	
		{
			double val = clock / REF_CLOCK;		
			double tmp_error = error;
			double tmp_val;
			for (int m = MIN_M; m <= MAX_M; m++) // (no VCO controled!) can be fail on altera
			{	
			 	for (int n = MIN_N; n <= MAX_N && !stopN; n++)
			 	{	
			 		double vco = n / (double) m;				 		 		
			 		tmp_val = m / (double) n;		 		
			 		tmp_error = fabs(val - tmp_val);		 				 			 				 		
			 		if (tmp_error < error && vco < 0.086) 
			 		{    
			 			error = tmp_error;
			 			M = m;
			 			N = n;  
			 			C = c;				 			
			 		};
			 		if (vco > 0.086) stopN = true;		 				 					 		
			 	}  	
			 	stopN = false;
	       		 }
	       		 	   		
		}	
	}		
	return error;
}
