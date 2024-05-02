/**************************************************************

   groovymister_wrapper.h - GroovyMiSTer C wrapper API header file

   ---------------------------------------------------------

   GroovyMiSTer  noGPU client for Groovy_MiSTer core

 **************************************************************/

#include <stdint.h>
#include <inttypes.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __linux__
#include <dlfcn.h>
#define LIBTYPE void*
#define OPENLIB(libname) dlopen((libname), RTLD_LAZY)
#define LIBFUNC(libh, fn) dlsym((libh), (fn))
#define LIBERROR dlerror
#define CLOSELIB(libh) dlclose((libh))

#elif defined _WIN32
#include <windows.h>
#define LIBTYPE HINSTANCE
#define OPENLIB(libname) LoadLibrary(TEXT((libname)))
#define LIBFUNC(lib, fn) GetProcAddress((lib), (fn))

#define CLOSELIB(libp) FreeLibrary((libp))
#endif

#ifdef _WIN32
 /* GROOVYMISTER_WIN32_STATIC */
	#ifndef GROOVYMISTER_WIN32_STATIC
		#define MODULE_API_GMW __declspec(dllexport)
	#else
		#define MODULE_API_GMW
	#endif
#else
	#define MODULE_API_GMW
#endif /* _WIN32 */

#ifdef __linux__
#define LIBGMC "libgroovymister.so"
#elif _WIN32
#define LIBGMC "libgroovymister.dll"
#endif

/* joystick map */
#define GMW_JOY_RIGHT (1 << 0)
#define GMW_JOY_LEFT  (1 << 1)
#define GMW_JOY_DOWN  (1 << 2)
#define GMW_JOY_UP    (1 << 3)
#define GMW_JOY_B1    (1 << 4)
#define GMW_JOY_B2    (1 << 5)
#define GMW_JOY_B3    (1 << 6)
#define GMW_JOY_B4    (1 << 7)
#define GMW_JOY_B5    (1 << 8)
#define GMW_JOY_B6    (1 << 9)
#define GMW_JOY_B7    (1 << 10)
#define GMW_JOY_B8    (1 << 11)
#define GMW_JOY_B9    (1 << 12)
#define GMW_JOY_B10   (1 << 13)

/* FPGA data received on ACK */
typedef struct MODULE_API_GMW
{
	uint32_t frame;		//frame on gpu
	uint32_t frameEcho;	//frame received
	uint16_t vCount;	//vertical count on gpu
	uint16_t vCountEcho; 	//vertical received

	uint8_t vramEndFrame; 	//1-fpga has all pixels on vram for last CmdBlit
	uint8_t vramReady;	//1-fpga has free space on vram
	uint8_t vramSynced;	//1-fpga has synced (not red screen)
	uint8_t vgaFrameskip;	//1-fpga used framebuffer (volatile framebuffer off)
	uint8_t vgaVblank;	//1-fpga is on vblank
	uint8_t vgaF1;		//1-field for interlaced
	uint8_t audio;		//1-fgpa has audio activated
	uint8_t vramQueue; 	//1-fpga has pixels prepared on vram
} gmw_fpgaStatus;

typedef struct MODULE_API_GMW{
	uint32_t joyFrame;	//joystick blit frame
	uint8_t  joyOrder;	//joystick blit order
	uint16_t joy1;	 	//joystick 1 map
	uint16_t joy2;	 	//joystick 2 map
	char     joy1LXAnalog; 	//joystick 1 L-Analog X
	char     joy1LYAnalog; 	//joystick 1 L-Analog Y
	char     joy1RXAnalog; 	//joystick 1 R-Analog X
	char     joy1RYAnalog; 	//joystick 1 R-Analog Y
	char     joy2LXAnalog; 	//joystick 2 L-Analog X
	char     joy2LYAnalog; 	//joystick 2 L-Analog Y
	char     joy2RXAnalog; 	//joystick 2 R-Analog X
	char     joy2RYAnalog; 	//joystick 2 R-Analog Y
} gmw_fpgaJoyInputs;

typedef struct MODULE_API_GMW{
	uint32_t ps2Frame;	//ps2 blit frame
	uint8_t  ps2Order;	//ps2 blit order
	uint8_t  ps2Keys[32]; 	//bit array with sdl scancodes convention	
	uint8_t  ps2Mouse;	//byte 0 ps2 mouse [yo,xo,ys,xs,1,bm,br,bl]
	uint8_t  ps2MouseX; 	//byte 1 ps2 mouse X
	uint8_t  ps2MouseY; 	//byte 2 ps2 mouse Y
	uint8_t  ps2MouseZ; 	//byte 3 ps2 mouse Z
}  gmw_fpgaPS2Inputs;

/* Declaration of the wrapper functions */

// Init streaming with ip, port, (lz4frames = 0-raw, 1-lz4, 2-lz4hc, 3-lz4 adaptative), soundRate(1-22k, 2-44.1, 3-48 khz), soundChan(1 or 2), rgbMode(0-RGB888, 1-RGBA888, 2-RGB565)
MODULE_API_GMW void gmw_init(const char* misterHost, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode);
// Close stream
MODULE_API_GMW void gmw_close(void);
// Change resolution (check https://github.com/antonioginer/switchres) for modeline generation (interlace=2 for progressive framebuffer)
MODULE_API_GMW void gmw_switchres(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace);
// This buffer are registered and aligned for sending rgb. Populate it before gmw_blit
MODULE_API_GMW char* gmw_get_pBufferBlit(void);
// Stream frame, vCountSync = 0 for auto frame delay or number of vertical line to sync with, margin with nanoseconds for auto frame delay)
MODULE_API_GMW void gmw_blit(uint32_t frame, uint16_t vCountSync, uint32_t margin);
// This buffer are registered and aligned for sending rgb. Populate it before gmw_audio
MODULE_API_GMW char* gmw_get_pBufferAudio(void);
// Stream audio
MODULE_API_GMW void gmw_audio(uint16_t soundSize);
// sleep to sync with crt raster
MODULE_API_GMW void gmw_waitSync(void);
// get nanoseconds (positive or negative) to sync with raster
MODULE_API_GMW int gmw_diffTimeRaster(void);
// getACK is used internal on WaitSync, dwMilliseconds = 0 will time out immediately if no new data
MODULE_API_GMW uint32_t gmw_getACK(uint8_t dwMilliseconds);
// get fpga status from last ACK received
MODULE_API_GMW void gmw_getStatus(gmw_fpgaStatus* status);
// listen inputs from MiSTer
MODULE_API_GMW void gmw_bindInputs(const char* misterHost);
// refresh inputs
MODULE_API_GMW void gmw_pollInputs(void);
// get joystick inputs
MODULE_API_GMW void gmw_getJoyInputs(gmw_fpgaJoyInputs* joyInputs);
// get ps2 inputs
MODULE_API_GMW void gmw_getPS2Inputs(gmw_fpgaPS2Inputs* ps2Inputs);

// get version
MODULE_API_GMW const char* gmw_get_version();
// Verbose level 0,1,2 (min to max)
MODULE_API_GMW void gmw_set_log_level(int level);


/* Inspired by https://stackoverflow.com/a/1067684 */
typedef struct MODULE_API_GMW
{
	void (*init)(const char* misterHost, uint8_t lz4Frames, uint32_t soundRate, uint8_t soundChan, uint8_t rgbMode);
	void (*close)(void);
	void (*switchres)(double pClock, uint16_t hActive, uint16_t hBegin, uint16_t hEnd, uint16_t hTotal, uint16_t vActive, uint16_t vBegin, uint16_t vEnd, uint16_t vTotal, uint8_t interlace);
	char*(*get_pBufferBlit)(void);
	void (*blit)(uint32_t frame, uint16_t vCountSync, uint32_t margin);
	char*(*get_pBufferAudio)(void);
	void (*audio)(uint16_t soundSize);
	void (*waitSync)(void);
	void (*diffTimeRaster)(void);
	uint32_t (*getACK)(uint8_t dwMilliseconds);
	void (*getStatus)(gmw_fpgaStatus* status);
	void (*bindInputs)(const char* misterHost);
	void (*pollInputs)(void);
	void (*getJoyInputs)(gmw_fpgaJoyInputs* joyInputs);
	void (*getPS2Inputs)(gmw_fpgaPS2Inputs* ps2Inputs);
	const char* (*get_version)(void);
	void (*set_log_level) (int level);
} gmwAPI;


#ifdef __cplusplus
}
#endif
