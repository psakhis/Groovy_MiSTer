# Groovy core for MiSTer

## General description
This core is a analog GPU for CRTs aiming for very low subframe latency

https://youtu.be/H0175WJFpUs

## Features
- Very low latency (3ms tested with GILT on GroovyMAME with frame delay 8)
- Full RGB888
- Switch all modes (progressive/interlaced) reprogramming pll according to modeline
- Connect with ethernet (can be work on wifi5/6 or Gb lan)
- Menu options: scandoubler, video position, framebuffer, ..

To install on your MiSTer you need replace MiSTer binary, so get from /hps_linux/main and copy to /media/fat of your sdcard (i think 'killall MiSTer' before copy is needed) 
  
## Emulators available

### GroovyMAME
 for src details, see GroovyMAME fork by @Calamity. Now merged https://github.com/antonioginer/GroovyMAME/releases/tag/gm0261sr002z
 ,to activate new MiSTer backend set on command line args:
  
    -video mister 
    -aspect 4:3 
    -switchres 
    -monitor arcade_15 
    -mister_window 
    -mister_ip "192.x.x.x" 
    -mister_compression none 
    -skip_gameinfo 
    -syncrefresh 
    -nothrottle
        
    *Automatic frame delay is applied with frame delay 0
    -mister_fd_margin 1.5/2.0/3.0 (applies a safe margin with ms to auto frame delay calculed)

    *Change "uifont default" to "uifont uismall.bdf" on mame.ini for pixel perfect menu
    *autosync 0 on mame.ini for menu (60hz)
    
### Mednafen 
  for src details, see emu4crt fork https://github.com/psakhis/emu4crt
  ,on mednafen.cfg set:
  
    mister.host 192.x.x.x
    mister.port 32100
    mister.lz4 1 (raw or lz4)
    mister.vsync 0 (automatic frame delay)
    video.resolution_switch mister
  
  
### Retroarch (Dreamcast non working atm) 
Menu isn't adapted, so start with retroach.exe -L cores/xxxx.dll file
  
  on retroarch.cfg set:
  
    mister_ip = "192.x.x.x"
    mister_lz4 = "true"
    video_mister_enable = "true"

    *Automatic frame delay for best results on latency options

## Thanks
@Calamity for hard testing core and implement GroovyMAME for it

@sorgelig, for developing and maintaining MiSTer.

@jotego, for analog adjustment module.

GroovyArcade Discord, https://discord.gg/YtQ6pJh #nogpu

MiSTer Discord #dev-talk

@alanswx for their lessons https://github.com/alanswx/Tutorials_MiSTer

@wickerwaka for their tips using ddr

@alexxnr for testing it and encourage me in the project

