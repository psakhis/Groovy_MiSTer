//psakhis PLL get values

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
#define MIN_N            1    //min divide factor
#define MAX_N            8    //max divide factor (can be superior at cost for cpu)


//based on Quartus
int getMinM(int N) 
{
	switch(N)
	{
		case 1: return 7;
		case 2: return 13;
		case 3: return 19;
		case 4: return 25;
		case 5: return 32;
		case 6: return 38;
		case 7: return 44;
		case 8: return 50;
	}
	return 0;	
}

//based on Quartus
int getMaxM(int N) 
{
	switch(N)
	{
		case 1: return 32;
		case 2: return 64;
		case 3: return 96;
		case 4: return 128;
		case 5: return 160;
		case 6: return 192;
		case 7: return 224;
		case 8: return 256;
	}
	return 0;		
}

//based on Quartus (not validate min or max here)
int isValidM(int M, int N) 
{
	if (M % 2 == 0) return 1;
	else
	{
		switch(N)
		{
			case 1: return 1;
			case 2: return 1;
			case 3: return 1;
			case 4: return 1;
			case 5: 
			{
				if (M == 45 || M == 55 || M >= 61) return 1;
				else return 0;
			};
			case 6: 
			{
				if (M == 45 || M == 57 || M == 63 || M >= 73) return 1;
				else return 0;
			};
			case 7: 
			{
				if (M == 63 || M == 77 || M >= 85) return 1;
				else return 0;
			};
			case 8: 
			{
				if (M >= 97) return 1;
				else return 0;
			};
		}	
	}
	return 0;	
}

double getMinClock(int N)
{
	return REF_CLOCK / (double) N;	
}

double getMaxClock(int N)
{
	return REF_CLOCK * (double) getMaxM(N) / (double) getMinClock(N);
}

int getMinC(double const px, int N) 
{
	int min_clock = (int) getMinClock(N);	
	int C = 0;	
	double clock = 0;	
	while (clock < min_clock) 
	{
		clock = clock + px;
		C++;	
	}		
	return C;
}

int getMaxC(double const px, int N) 
{
	int max_clock = (int) getMaxClock(N);
	int C = 0;	
	double clock = 0;	
	while (clock < max_clock) 
	{
		clock = clock + px;
		C++;	
	}		
	return C;
}

double getMNC(double const px, int &M, int &N, int &C)
{				
	double error = 9;
	M = 0;
	N = 0;
	C = 0;	
	
	for (int n = MIN_N; n <= MAX_N; n++)	//Quartus based values
	{
		int c_min = getMinC(px, n);	
		int c_max = getMaxC(px, n);
		for (int c = c_min; c <= c_max; c++)
		{
			double clock = c * px;
			double val = clock / REF_CLOCK;
			double tmp_error = error;
			double tmp_val;
			int m_min = getMinM(n);
			int m_max = getMaxM(n);				
			for (int m = m_min; m <= m_max; m++) 
			{				
				if (isValidM(m, n))
				{
					tmp_val = m / (double) n;	
					tmp_error = fabs(val - tmp_val);					
					if (tmp_error < error) 
			 		{    
						error = tmp_error;
			 			M = m;
			 			N = n;  
			 			C = c;				 			
			 		};
				}							 					 		
			}	
		}		
		
	}		
	return error;
}

