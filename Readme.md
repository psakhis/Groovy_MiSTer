# Groovy core for MiSTer

## General description
This core is a analog GPU for CRTs aiming for very low subframe latency

https://youtu.be/H0175WJFpUs

## Features 
- Very low latency (~3ms tested with GILT on GroovyMAME with frame delay 8)
- RGB888/RGB565/RGBA888 blitting
- Switch all modes (progressive/interlaced) reprogramming pll according to modeline
- Connect with GB ethernet (direct connection recommended)
- Audio stream
- Inputs stream (keyboard, mouse, 2 joypads)
- Native LZ4 uncompress on FPGA
- [History](https://github.com/psakhis/Groovy_MiSTer/blob/main/history.txt)

## Installation (transfers in binary mode!)
- Copy MiSTer_groovy to /media/fat 
- Copy Groovy.rbf to /media/fat/_Utility 
- Edit MiSTer.ini and add custom binary at end of file<br />
  <sub>
  [Groovy]<br />
  main=MiSTer_groovy<br />
  </sub>
  
  - Only for XDP high performance feature, some tweaks on Linux are needed. For UDP isn't needed.
  1. Replace kernel: zImage_dtb file on /media/fat/linux (is same [kernel](MiSTer-devel/Linux-Kernel_MiSTer#55) with some patches for eth0 driver and builded with CONFIG_XDP_SOCKETS=Y)
  2. Save groovy_xdp_kern.o to /usr/lib/arm-linux-gnueabihf/bpf (this program will be injected on eth while xdp is running)
  3. Save libelf.so.1 on /usr/lib (library requiered)
  4. On MiSTer.ini change binary from MiSTer_groovy to MiSTer_groovy_XDP 
## Emulators available
### [GroovyMAME](https://github.com/antonioginer/GroovyMAME/releases) <br />
  MAME fork by @Calamity, download mame_mister.ini and rename to mame.ini
 
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
    -joystickprovider mister (from 0.264, analog joysticks from 0.266)
    -keyboardprovider mister (from 0.266)
    -mouseprovider mister (from 0.266)
        
    *Automatic frame delay is applied with frame delay 0
    -mister_fd_margin 1.5/2.0/3.0 (applies a safe margin with ms to auto frame delay)

    *Change "uifont default" to "uifont uismall.bdf" on mame.ini for pixel perfect menu
    *autosync 0 on mame.ini for menu (60hz)
    *MAC builds from https://github.com/djfumberger/GroovyMAME/releases/tag/2024Jan19
    
### [emu4crt](https://github.com/psakhis/emu4crt/releases) 
  Mednafen fork, on mednafen.cfg set:
  
    mister.host 192.x.x.x  
    mister.lz4 1 (0-raw, 1-lz4, 2-lz4hc, 3-lz4 adaptative)
    mister.vsync 0 (0 for automatic frame delay or line do you want to sync)
    mister.mtu 1500 (3800 for jumbo frames)
    mister.interlaced_fb 1 (0 for force progressive framebuffer with interlaced modes)
    video.resolution_switch mister
  
### [Retroarch](https://github.com/antonioginer/RetroArch/tree/mister) 
  Retroarch fork, on retroarch.cfg set (note: these lines has to exists on retroarch.cfg):
  
    mister_ip = "192.x.x.x"
    mister_lz4 = "1" (0-raw, 1-lz4, 2-lz4hc, 3-adaptative)
    crt_switch_resolution = "4" (switchres.ini custom file)
    crt_switch_resolution_super = "0"
    aspect_ratio_index = "22" (core provided)
    video_mister_enable = "true"
    video_vsync = "false"
    mister_scanlines = "true" 
    mister_force_rgb565 = "false" (activate it when bandwidth problems)
    mister_interlaced_fb = "true"
    input_driver = "mister" (for input keyboard/mouse connected on MiSTer)
    input_joypad_driver = "mister" (for input controllers connected on MiSTer)
    menu_driver = "rgui" (it's the only menu supported)
    vrr_runloop_enable = "true" (better performance for flycast)
    audio_sync = "false" (better performance for flycast)
    mister_mtu = "1500" (for enable jumbo frame, 3800 is allowed)

    *Automatic frame delay for best results on latency options
    *For dosbox core, set 60fps on core options.
    *Hardware cores only works with glcore/vulkan.
    *For run a core from command line -> retroach.exe -L cores/xxxx.dll file
    
### [MiSTerCast](https://github.com/iequalshane/MiSTerCast) 
Thanks to @Shane for this great windows utility to mirror desktop.

## Thanks
@Calamity for hard testing core and implement GroovyMAME for it

@sorgelig, for developing and maintaining MiSTer.

@jotego, for analog adjustment module.

[GroovyArcade Discord](https://discord.gg/YtQ6pJh) #nogpu

MiSTer Discord #dev-talk

@alanswx for their [lessons](https://github.com/alanswx/Tutorials_MiSTer)

@wickerwaka for their tips using ddr

@coolbho3k for their [overclock](https://github.com/coolbho3k/MiSTer-Overclock-Scripts)  

@Emulators teams: Mednafen, MAME and Retroarch

@alexxnr for testing it and encourage me in the project

