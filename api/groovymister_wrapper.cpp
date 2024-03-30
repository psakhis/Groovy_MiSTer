/**************************************************************

   groovymister_wrapper.h - GroovyMiSTer C wrapper API header file

   ---------------------------------------------------------

   GroovyMiSTer  noGPU client for Groovy_MiSTer core

 **************************************************************/

#define MODULE_API_EXPORTS_GMW
#include "groovymister.h"
#include "groovymister_wrapper.h"
#ifdef __cplusplus
extern "C" {
#endif


GroovyMister* gmw;

MODULE_API_GMW void gmw_init(const char* misterHost, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode)
{	
	if (gmw == NULL)
	{
		gmw = new GroovyMister;		
	}	
	gmw->CmdInit(misterHost, 32100, lz4Frames, soundRate, soundChan, rgbMode);
}

MODULE_API_GMW void gmw_close(void)
{	
	if (gmw != NULL)
	{
		gmw->CmdClose();
		delete gmw;	
	} 
	else
	{
		printf("[MiSTer] gmw_close failed\n");
	}	
}

MODULE_API_GMW void gmw_switchres(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace)
{
	if (gmw != NULL)
	{
		gmw->CmdSwitchres(pClock, hActive, hBegin, hEnd, hTotal, vActive, vBegin, vEnd, vTotal, interlace);
	}
	else
	{
		printf("[MiSTer] gmw_switchres failed\n");
	}	
}

MODULE_API_GMW char* gmw_get_pBufferBlit(void)
{
	if (gmw != NULL)
	{
		return gmw->pBufferBlit;
	}
	else
	{
		printf("[MiSTer] gmw_get_pBufferBlit failed\n");
		return NULL;
	}	
}

MODULE_API_GMW void gmw_blit(uint32_t frame, uint16_t vCountSync, uint32_t margin)
{
	if (gmw != NULL)
	{
		gmw->CmdBlit(frame, vCountSync, margin);
	}
	else
	{
		printf("[MiSTer] gmw_blit failed\n");		
	}	
}

MODULE_API_GMW char* gmw_get_pBufferAudio(void)
{
	if (gmw != NULL)
	{
		return gmw->pBufferAudio;
	}	
	else
	{
		printf("[MiSTer] gmw_get_pBufferAudio failed\n");
		return NULL;
	}	
}

MODULE_API_GMW void gmw_audio(uint16_t soundSize)
{
	if (gmw != NULL)
	{
		gmw->CmdAudio(soundSize);
	}
	else
	{
		printf("[MiSTer] gmw_audio failed\n");		
	}	
}

MODULE_API_GMW void gmw_waitSync(void)
{
	if (gmw != NULL)
	{
		gmw->WaitSync();
	}
	else
	{
		printf("[MiSTer] gmw_waitSync failed\n");
	}	
}

MODULE_API_GMW uint32_t gmw_getACK(uint8_t dwMilliseconds)
{
	if (gmw != NULL)
	{
		return gmw->getACK(dwMilliseconds);
	}
	else
	{
		printf("[MiSTer] gmw_getACK failed\n");
		return 0;
	}	
}

MODULE_API_GMW void gmw_getStatus(gmw_fpgaStatus* status)
{
	if (gmw != NULL)
	{
		status->frame = gmw->fpga.frame;		
	 	status->frameEcho = gmw->fpga.frameEcho;	
	 	status->vCount = gmw->fpga.vCount;	
	 	status->vCountEcho = gmw->fpga.vCountEcho; 	
	 	
	 	status->vramEndFrame = gmw->fpga.vramEndFrame; 	
	 	status->vramReady = gmw->fpga.vramReady;	
	 	status->vramSynced = gmw->fpga.vramSynced;	
	 	status->vgaFrameskip = gmw->fpga.vgaFrameskip;	
	 	status->vgaVblank = gmw->fpga.vgaVblank;	
	 	status->vgaF1 = gmw->fpga.vgaF1;		
	 	status->audio = gmw->fpga.audio;		
	 	status->vramQueue = gmw->fpga.vramQueue; 	
	 }
	 else
	 {
	 	printf("[MiSTer] gmw_getStatus failed\n");
	 }	 	 	
}

MODULE_API_GMW void gmw_bindInputs(const char* misterHost)
{	
	if (gmw == NULL)
	{
		gmw = new GroovyMister();
	}
	gmw->BindInputs(misterHost, 32101);
}

MODULE_API_GMW void gmw_pollInputs(void)
{
	if (gmw != NULL)
	{
		gmw->PollInputs();
	}
	else
	{
		printf("[MiSTer] gmw_pollInputs failed\n");
	}	
}

MODULE_API_GMW void gmw_getInputs(gmw_fpgaInputs* inputs)
{	
	if (gmw != NULL)
	{
		inputs->joyFrame = gmw->inputs.joyFrame; 
 		inputs->joyOrder = gmw->inputs.joyOrder; 
 		inputs->joy1 = gmw->inputs.joy1; 
 		inputs->joy2 = gmw->inputs.joy2;  
 	}
 	else
 	{
 		printf("[MiSTer] gmw_getInputs failed\n");
 	}		
}

MODULE_API_GMW const char* gmw_get_version()
{	
	if (gmw != NULL)
	{
		return gmw->getVersion();
	}	
	else
	{
		printf("[MiSTer] gmw_get_version failed\n");
		return NULL;
	}	
}

MODULE_API_GMW void gmw_set_log_level(int level)
{
	if (gmw != NULL)
	{
		gmw->setVerbose(level);	
	}	
	else
	{
		printf("[MiSTer] gmw_set_log_level failed\n");
	}	
}


#ifdef __cplusplus
}
#endif