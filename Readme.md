# Groovy core for MiSTer

## General description
This core is a analog GPU for CRTs aiming for very low subframe latency

https://youtu.be/H0175WJFpUs

## Features
- Very low latency (~3ms tested with GILT on GroovyMAME with frame delay 8)
- Full RGB888
- Switch all modes (progressive/interlaced) reprogramming pll according to modeline
- Connect with ethernet (can be work on wifi5/6 or Gb lan)
- Menu options: scandoubler, video position, framebuffer, ..
- Audio stream (set ON on audio core options)
- Double framebuffer for interlaced resolutions (framebuffer per field)
- More speed and stability fixes (lz4 is recommended for interlaced or 480p)
- Retroarch support for opengl/vulkan hardware rendered cores like flycast
  * Dosbox-pure set 60fps on core options
  * Flycast, disable threaded render on core options (or config/Flycast/Flycast.opt reicast_threaded_rendering = "disabled")
- Mednafen/Retroarch can work with arcade_31 monitor on swithres.ini
- GroovyMame MAC builds from https://github.com/djfumberger/GroovyMAME/releases/tag/2024Jan19
  
To install on your MiSTer you need replace MiSTer binary, so get from /hps_linux/main and copy to /media/fat of your sdcard (i think 'killall MiSTer' before copy is needed)

## Test build features (experimental)
- (20240302) New native LZ4 blitting inside FPGA (from GroovyMame 0.264, Mednafen and MiSTerCast beta)
- (20240302) New PWM core option (implemented by https://github.com/Jokippo)
- (20240325) Framebuffer progressive on interlaced resolutions. On MAME new argument -nomister_interlaced_fb to activate it
- (20240401) GroovyMame and Mednafen joysticks from mister
- (20240427) Retroarch 

To install on your MiSTer follow instructions https://github.com/psakhis/Groovy_MiSTer/tree/main/hps_linux
  
## Emulators available

### GroovyMAME
 for src details, see GroovyMAME fork by @Calamity. Now merged https://github.com/antonioginer/GroovyMAME/releases
 ,to activate new MiSTer backend set on with (note: you can edit it on mame.ini or like arguments):
  
    -video mister 
    -aspect 4:3 
    -switchres 
    -monitor arcade_15 
    -mister_window 
    -mister_ip "192.x.x.x" 
    -mister_compression lz4
    -skip_gameinfo 
    -syncrefresh 
    -nothrottle
    -nomister_interlaced_fb (from 0.264) 
    -joystickprovider mister (from 0.264)
        
    *Automatic frame delay is applied with frame delay 0
    -mister_fd_margin 1.5/2.0/3.0 (applies a safe margin with ms to auto frame delay)

    *Change "uifont default" to "uifont uismall.bdf" on mame.ini for pixel perfect menu
    *autosync 0 on mame.ini for menu (60hz)
    
### Mednafen 
  for src details, see emu4crt fork https://github.com/psakhis/emu4crt
  ,on mednafen.cfg set:
  
    mister.host 192.x.x.x
    mister.port 32100
    mister.lz4 1 (0-raw, 1-lz4 or 2-lz4hc)
    mister.vsync 0 (automatic frame delay)
    video.resolution_switch mister
  
  
### Retroarch (test build)
retroach.exe -L cores/xxxx.dll file
  
  on retroarch.cfg set (note: these lines has to exists on retroarch.cfg):
  
    mister_ip = "192.x.x.x"
    mister_lz4 = "3" (0-raw, 1-lz4, 2-lz4hc, 3-adaptative)
    crt_switch_resolution = "4" (switchres.ini custom file)
    crt_switch_resolution_super = "0"
    video_mister_enable = "true"
    video_vsync = "false"
    mister_scanlines = "true" 
    mister_force_rgb565 = "false" (activate it when bandwidth problems)
    mister_interlaced_fb = "false"
    input_joypad_driver = "mister" (for input controllers connected on MiSTer)

    *Automatic frame delay for best results on latency options

### MiSTerCast 
Thanks to @Shane for this great windows utility to mirror desktop. https://github.com/iequalshane/MiSTerCast

## Thanks
@Calamity for hard testing core and implement GroovyMAME for it

@sorgelig, for developing and maintaining MiSTer.

@jotego, for analog adjustment module.

GroovyArcade Discord, https://discord.gg/YtQ6pJh #nogpu

MiSTer Discord #dev-talk

@alanswx for their lessons https://github.com/alanswx/Tutorials_MiSTer

@wickerwaka for their tips using ddr

@Emulators teams: Mednafen, MAME and Retroarch

@alexxnr for testing it and encourage me in the project

