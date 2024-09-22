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
int gmw_inputsBinded;

MODULE_API_GMW int gmw_init(const char* misterHost, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode, uint16_t mtu)
{
	if (gmw == NULL)
	{
		gmw = new GroovyMister;
		gmw_inputsBinded = 0;
	}
	return gmw->CmdInit(misterHost, 32100, lz4Frames, soundRate, soundChan, rgbMode, mtu);	
}

MODULE_API_GMW void gmw_close(void)
{
	if (gmw != NULL)
	{
		gmw->CmdClose();
		delete gmw;
		gmw = NULL;
		gmw_inputsBinded = 0;
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

MODULE_API_GMW char* gmw_get_pBufferBlit(uint8_t field)
{
	if (gmw != NULL)
	{
		return gmw->getPBufferBlit(field);
	}
	else
	{
		printf("[MiSTer] gmw_get_pBufferBlit failed\n");
		return NULL;
	}
}

MODULE_API_GMW char* gmw_get_pBufferBlitDelta(void)
{
	if (gmw != NULL)
	{
		return gmw->getPBufferBlitDelta();
	}
	else
	{
		printf("[MiSTer] gmw_get_pBufferBlitDelta failed\n");
		return NULL;
	}
}

MODULE_API_GMW void gmw_blit(uint32_t frame, uint8_t field, uint16_t vCountSync, uint32_t margin, uint32_t matchDeltaBytes)
{
	if (gmw != NULL)
	{
		gmw->CmdBlit(frame, field, vCountSync, margin, matchDeltaBytes);
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
		return gmw->getPBufferAudio();
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


MODULE_API_GMW int gmw_diffTimeRaster(void)
{
	if (gmw != NULL)
	{
		return gmw->DiffTimeRaster();
	}
	else
	{
		printf("[MiSTer] gmw_diffTimeRaster failed\n");
		return 0;
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
		gmw_inputsBinded = 0;
	}
	if (!gmw_inputsBinded)
	{
		gmw->BindInputs(misterHost, 32101);
	}
	gmw_inputsBinded = 1;
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

MODULE_API_GMW void gmw_getJoyInputs(gmw_fpgaJoyInputs* joyInputs)
{
	if (gmw != NULL)
	{
		joyInputs->joyFrame     = gmw->joyInputs.joyFrame;
		joyInputs->joyOrder     = gmw->joyInputs.joyOrder;
		joyInputs->joy1         = gmw->joyInputs.joy1;
		joyInputs->joy2         = gmw->joyInputs.joy2;
		joyInputs->joy1LXAnalog = gmw->joyInputs.joy1LXAnalog;
		joyInputs->joy1LYAnalog = gmw->joyInputs.joy1LYAnalog;
		joyInputs->joy1RXAnalog = gmw->joyInputs.joy1RXAnalog;
		joyInputs->joy1RYAnalog = gmw->joyInputs.joy1RYAnalog;
		joyInputs->joy2LXAnalog = gmw->joyInputs.joy2LXAnalog;
		joyInputs->joy2LYAnalog = gmw->joyInputs.joy2LYAnalog;
		joyInputs->joy2RXAnalog = gmw->joyInputs.joy2RXAnalog;
		joyInputs->joy2RYAnalog = gmw->joyInputs.joy2RYAnalog;
	}
	else
	{
		memset(&joyInputs, 0, sizeof(joyInputs));
		printf("[MiSTer] gmw_getJoyInputs failed\n");
	}
}

MODULE_API_GMW void gmw_getPS2Inputs(gmw_fpgaPS2Inputs* ps2Inputs)
{
	if (gmw != NULL)
	{
		ps2Inputs->ps2Frame  = gmw->ps2Inputs.ps2Frame;
		ps2Inputs->ps2Order  = gmw->ps2Inputs.ps2Order;
		memcpy(&ps2Inputs->ps2Keys, &gmw->ps2Inputs.ps2Keys, sizeof(ps2Inputs->ps2Keys));
		ps2Inputs->ps2Mouse  = gmw->ps2Inputs.ps2Mouse;
		ps2Inputs->ps2MouseX = gmw->ps2Inputs.ps2MouseX;
		ps2Inputs->ps2MouseY = gmw->ps2Inputs.ps2MouseY;
		ps2Inputs->ps2MouseZ = gmw->ps2Inputs.ps2MouseZ;
	}
	else
	{
		memset(&ps2Inputs, 0, sizeof(ps2Inputs));
		printf("[MiSTer] gmw_getPS2Inputs failed\n");
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
