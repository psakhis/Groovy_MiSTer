#ifndef QB_CONFIG_H__
#define QB_CONFIG_H__

#define PACKAGE_NAME "retroarch"
#define HAVE_7ZIP 1
#define HAVE_ACCESSIBILITY 1
/* #undef HAVE_AL */
/* #undef HAVE_ALSA */
/* #undef HAVE_ANGLE */
/* #undef HAVE_AUDIOIO */
#define HAVE_AUDIOMIXER 1
#define HAVE_AVCODEC 1
#define HAVE_AVDEVICE 1
#define HAVE_AVFORMAT 1
#define HAVE_AVUTIL 1
#define HAVE_AV_CHANNEL_LAYOUT 1
#define HAVE_BLISSBOX 1
/* #undef HAVE_BLUETOOTH */
#define HAVE_BSV_MOVIE 1
/* #undef HAVE_BUILTINBEARSSL */
#define HAVE_BUILTINFLAC 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_BUILTINGLSLANG 1
#endif
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_BUILTINMBEDTLS 1
#endif
#define HAVE_BUILTINZLIB 1
#define HAVE_C99 1
/* #undef HAVE_CACA */
#define HAVE_CC 1
#define HAVE_CC_RESAMPLER 1
#define HAVE_CDROM 1
/* #undef HAVE_CG */
#ifndef CXX_BUILD
#define HAVE_CHD 1
#endif
#define HAVE_CHEATS 1
/* #undef HAVE_CHECK */
#define HAVE_CHEEVOS 1
#define HAVE_COMMAND 1
#define HAVE_CONFIGFILE 1
/* #undef HAVE_COREAUDIO3 */
#define HAVE_CORE_INFO_CACHE 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_CRTSWITCHRES 1
#endif
#define HAVE_CXX 1
#define HAVE_CXX11 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_D3D10 1
#endif
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_D3D11 1
#endif
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_D3D12 1
#endif
/* #undef HAVE_D3D8 */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_D3D9 1
#endif
#define HAVE_D3DX 1
/* #undef HAVE_D3DX8 */
#define HAVE_D3DX9 1
/* #undef HAVE_DBUS */
/* #undef HAVE_DEBUG */
#define HAVE_DINPUT 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_DISCORD 1
#endif
/* #undef HAVE_DISPMANX */
/* #undef HAVE_DRM */
/* #undef HAVE_DRMINGW */
#define HAVE_DR_MP3 1
#define HAVE_DSOUND 1
#define HAVE_DSP_FILTER 1
#define HAVE_DYLIB 1
#define HAVE_DYNAMIC 1
/* #undef HAVE_DYNAMIC_EGL */
/* #undef HAVE_EGL */
/* #undef HAVE_EXYNOS */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_FFMPEG 1
#endif
/* #undef HAVE_FLAC */
/* #undef HAVE_FLOATHARD */
/* #undef HAVE_FLOATSOFTFP */
#define HAVE_FONTCONFIG 1
#define HAVE_FREETYPE 1
/* #undef HAVE_GBM */
#define HAVE_GDI 1
#define HAVE_GETADDRINFO 1
/* #undef HAVE_GETOPT_LONG */
#define HAVE_GFX_WIDGETS 1
#define HAVE_GLSL 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_GLSLANG 1
#endif
/* #undef HAVE_GLSLANG_GENERICCODEGEN */
/* #undef HAVE_GLSLANG_HLSL */
/* #undef HAVE_GLSLANG_MACHINEINDEPENDENT */
/* #undef HAVE_GLSLANG_OGLCOMPILER */
/* #undef HAVE_GLSLANG_OSDEPENDENT */
/* #undef HAVE_GLSLANG_SPIRV */
/* #undef HAVE_GLSLANG_SPIRV_TOOLS */
/* #undef HAVE_GLSLANG_SPIRV_TOOLS_OPT */
/* #undef HAVE_HID */
/* #undef HAVE_HLSL */
#define HAVE_IBXM 1
#define HAVE_IFINFO 1
#define HAVE_IMAGEVIEWER 1
/* #undef HAVE_JACK */
/* #undef HAVE_KMS */
#define HAVE_LANGEXTRA 1
/* #undef HAVE_LIBCHECK */
#define HAVE_LIBRETRODB 1
/* #undef HAVE_LIBSHAKE */
/* #undef HAVE_LIBUSB */
/* #undef HAVE_LUA */
/* #undef HAVE_MALI_FBDEV */
/* #undef HAVE_MEMFD_CREATE */
#define HAVE_MENU 1
/* #undef HAVE_METAL */
#define HAVE_MICROPHONE 1
/* #undef HAVE_MIST */
#define HAVE_MISTER 1
/* #undef HAVE_MMAP */
#define HAVE_MOC 1
/* #undef HAVE_MPV */
#define HAVE_NEAREST_RESAMPLER 1
/* #undef HAVE_NEON */
#define HAVE_NETPLAYDISCOVERY 1
#define HAVE_NETPLAYDISCOVERY 1
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_NETWORKGAMEPAD 1
#endif
#define HAVE_NETWORKING 1
#define HAVE_NETWORK_CMD 1
/* #undef HAVE_NETWORK_VIDEO */
#define HAVE_NOUNUSED 1
#define HAVE_NOUNUSED_VARIABLE 1
#define HAVE_NVDA 1
/* #undef HAVE_ODROIDGO2 */
/* #undef HAVE_OMAP */
#define HAVE_ONLINE_UPDATER 1
/* #undef HAVE_OPENDINGUX_FBDEV */
#define HAVE_OPENGL 1
#define HAVE_OPENGL1 1
/* #undef HAVE_OPENGLES */
/* #undef HAVE_OPENGLES3 */
/* #undef HAVE_OPENGLES3_1 */
/* #undef HAVE_OPENGLES3_2 */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_OPENGL_CORE 1
#endif
#define HAVE_OPENSSL 1
/* #undef HAVE_OSMESA */
/* #undef HAVE_OSS */
/* #undef HAVE_OSS_BSD */
/* #undef HAVE_OSS_LIB */
#define HAVE_OVERLAY 1
/* #undef HAVE_PARPORT */
#define HAVE_PATCH 1
/* #undef HAVE_PLAIN_DRM */
/* #undef HAVE_PRESERVE_DYLIB */
/* #undef HAVE_PULSE */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_QT 1
#endif
#define HAVE_QT5CONCURRENT 1
#define HAVE_QT5CORE 1
#define HAVE_QT5GUI 1
#define HAVE_QT5NETWORK 1
#define HAVE_QT5WIDGETS 1
#define HAVE_RBMP 1
#define HAVE_REWIND 1
#define HAVE_RJPEG 1
/* #undef HAVE_ROAR */
#define HAVE_RPNG 1
/* #undef HAVE_RSOUND */
#define HAVE_RTGA 1
#define HAVE_RUNAHEAD 1
#define HAVE_RWAV 1
/* #undef HAVE_SAPI */
#define HAVE_SCREENSHOTS 1
/* #undef HAVE_SDL */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_SDL2 1
#endif
/* #undef HAVE_SDL_DINGUX */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_SHADERPIPELINE 1
#endif
/* #undef HAVE_SIXEL */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_SLANG 1
#endif
/* #undef HAVE_SOCKET_LEGACY */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_SPIRV_CROSS 1
#endif
#define HAVE_SR2 1
#define HAVE_SSA 1
/* #undef HAVE_SSE */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_SSL 1
#endif
#define HAVE_STB_FONT 1
#define HAVE_STB_IMAGE 1
#define HAVE_STB_VORBIS 1
/* #undef HAVE_STDIN_CMD */
/* #undef HAVE_STEAM */
/* #undef HAVE_STRCASESTR */
/* #undef HAVE_SUNXI */
#define HAVE_SWRESAMPLE 1
#define HAVE_SWSCALE 1
/* #undef HAVE_SYSTEMD */
/* #undef HAVE_SYSTEMMBEDTLS */
#define HAVE_THREADS 1
#define HAVE_THREAD_STORAGE 1
#define HAVE_TRANSLATE 1
/* #undef HAVE_UDEV */
#define HAVE_UPDATE_ASSETS 1
#define HAVE_UPDATE_CORES 1
#define HAVE_UPDATE_CORE_INFO 1
/* #undef HAVE_V4L2 */
/* #undef HAVE_VC_TEST */
/* #undef HAVE_VG */
/* #undef HAVE_VIDEOCORE */
/* #undef HAVE_VIDEOPROCESSOR */
#define HAVE_VIDEO_FILTER 1
/* #undef HAVE_VIVANTE_FBDEV */
#if __cplusplus || __STDC_VERSION__ >= 199901L
#define HAVE_VULKAN 1
#endif
#define HAVE_VULKAN_DISPLAY 1
#define HAVE_WASAPI 1
/* #undef HAVE_WAYLAND */
/* #undef HAVE_WAYLAND_CURSOR */
/* #undef HAVE_WAYLAND_PROTOS */
/* #undef HAVE_WAYLAND_SCANNER */
/* #undef HAVE_WIFI */
#define HAVE_WINMM 1
#define HAVE_WINRAWINPUT 1
/* #undef HAVE_X11 */
#define HAVE_XAUDIO 1
#define HAVE_XDELTA 1
/* #undef HAVE_XINERAMA */
#define HAVE_XINPUT 1
/* #undef HAVE_XKBCOMMON */
/* #undef HAVE_XRANDR */
/* #undef HAVE_XSHM */
/* #undef HAVE_XVIDEO */
#define HAVE_ZLIB 1
#endif
