# Groovy core for MiSTer

## General description
This core is a analog gpu for crt for subframe latency emulators

Emulators available

### GroovyMAME


  
### Mednafen 
  for src details, see emu4crt fork https://github.com/psakhis/emu4crt
  ,on mednafen.cfg set:
  
     mister.host "192.x.x.x"
  
     mister.port 32100
  
     mister.lz4 1 (raw or lz4)
  
     mister.vsync 0 (automatic frame delay)
  

  
### Retroarch (Dreamcast non working atm)
  
  on retroarch.cfg set:
  
     mister_ip = "192.x.x.x"
  
     mister_lz4 = "true"
  
     video_mister_enable = "true"

     *Automatic frame delay for best results on latency options





