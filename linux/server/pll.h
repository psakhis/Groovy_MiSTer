#ifndef __PLL_H__
#define __PLL_H__

struct pll_data_t
{
	short load_current;
	
};

//int getBattery(int quick, struct battery_data_t *data);

int getMinC(double const px);   
int getMaxC(double const px);   
double getMNC(double const px, int &M, int &N, int &C);   

#endif
