#ifndef __PLL_H__
#define __PLL_H__

struct pll_data_t
{
	short load_current;
	
};

double getMCK_PLL_Fractional(double const Fout, int &M, int &C, int &K);   
double getMNC_PLL_Integer(double const px, int &M, int &N, int &C);   


#endif
