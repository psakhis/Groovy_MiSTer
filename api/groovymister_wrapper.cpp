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
GroovyMister* gmwInputs;

MODULE_API_GMW void gmw_init(const char* misterHost, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode)
{	
	gmw = new GroovyMister;		
	gmw->CmdInit(misterHost, 32100, lz4Frames, soundRate, soundChan, rgbMode);
}

MODULE_API_GMW void gmw_close(void)
{	
	gmw->CmdClose();
	delete gmw;	
}

MODULE_API_GMW void gmw_switchres(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace)
{
	gmw->CmdSwitchres(pClock, hActive, hBegin, hEnd, hTotal, vActive, vBegin, vEnd, vTotal, interlace);
}

MODULE_API_GMW char* gmw_get_pBufferBlit(void)
{
	return gmw->pBufferBlit;
}

MODULE_API_GMW void gmw_blit(uint32_t frame, uint16_t vCountSync, uint32_t margin)
{
	gmw->CmdBlit(frame, vCountSync, margin);
}

MODULE_API_GMW char* gmw_get_pBufferAudio(void)
{
	return gmw->pBufferAudio;
}

MODULE_API_GMW void gmw_audio(uint16_t soundSize)
{
	gmw->CmdAudio(soundSize);
}

MODULE_API_GMW void gmw_waitSync(void)
{
	gmw->WaitSync();
}

MODULE_API_GMW uint32_t gmw_getACK(uint8_t dwMilliseconds)
{
	return gmw->getACK(dwMilliseconds);
}

MODULE_API_GMW void gmw_getStatus(gmw_fpgaStatus* status)
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

MODULE_API_GMW void gmw_bindInputs(void)
{	
	gmwInputs = new GroovyMister();	
	gmwInputs->BindInputs();
}

MODULE_API_GMW void gmw_pollInputs(void)
{
	gmwInputs->PollInputs();
}

MODULE_API_GMW void gmw_getInputs(gmw_fpgaInputs* inputs)
{	
	inputs->joyFrame = gmwInputs->inputs.joyFrame; 
 	inputs->joyOrder = gmwInputs->inputs.joyOrder; 
 	inputs->joy1 = gmwInputs->inputs.joy1; 
 	inputs->joy2 = gmwInputs->inputs.joy2;  		
}

MODULE_API_GMW const char* gmw_get_version() {
	if (gmw != NULL)
	{
		return gmw->getVersion();
	}	
	if (gmwInputs != NULL)
	{
		return gmwInputs->getVersion();
	}	
}

MODULE_API_GMW void gmw_set_log_level(int level)
{
	if (gmw != NULL)
	{
		gmw->setVerbose(level);	
	}	
	if (gmwInputs != NULL)
	{
		gmwInputs->setVerbose(level);	
	}	
}


#ifdef __cplusplus
}
#endif