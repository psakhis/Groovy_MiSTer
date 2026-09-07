Install instructions

You need last MiSTer main (2024/03/25)

Full source code [MiSTer_groovy](https://github.com/psakhis/Main_MiSTer)

1) Copy "MiSTer_groovyNLC" to /media/fat. If you are using filezilla, be sure transfer is in binary mode.
2) Copy core "GroovyNLC_20260904.rbf" to /media/fat/_Utility
3) Edit "/media/fat/MiSTer.ini" and add custom binary entry to core
   ....
   [GroovyNLC]
   main=MiSTer_groovyNLC
   ...

This method will execute MiSTer_groovyNLC binary when you start core from _Utility

The section name must match CONF_STR field 0 in Groovy.sv ("GroovyNLC"), not the
.rbf filename - the rbf can be called anything.

UPGRADING FROM A "Groovy" INSTALL
The core name keys the OSD settings file and the input maps, so a rename would
normally orphan both. The binary handles this for you: if GroovyNLC.CFG or the
GroovyNLC_input_* maps are missing it reads the old Groovy-named ones, and writes
the new name on the next save / button define. You should not have to do anything.

Why it matters: without that fallback the status word loads as all zeros, and the
Audio, Joysticks, PS2 and Verbose options all list their DISABLED value first - so
the core comes up muted, ignoring controllers, and logging nothing, while video
(gated by no status bit) keeps working normally. On a genuinely fresh install with
no config at all the binary seeds Audio=On and Joysticks=Analog for the same reason.

To copy the files across by hand instead - note the maps live in config/inputs/,
and profile maps carry a _p<n>_ infix:

   cp /media/fat/config/Groovy.CFG /media/fat/config/GroovyNLC.CFG
   cd /media/fat/config/inputs && for f in Groovy_input_*; do cp "$f" "GroovyNLC${f#Groovy}"; done
   cd /media/fat/config        && for f in Groovy_input_*; do cp "$f" "GroovyNLC${f#Groovy}"; done
   ln -s /media/fat/games/Groovy /media/fat/games/GroovyNLC   # only if you browse .gmc files

(the second loop covers the older location the loader still probes; either may be
empty, that is fine. Per-device profiles and nicknames live in
config/inputs/<id>_groovy.cfg, which is not core-name keyed and needs no action.)

MiSTer.ini SECTIONS
Section matching is exact, so any OTHER keys you had under a literal [Groovy]
heading - rumble, controller_unique_mapping, video_mode, vsync_adjust, per-core
scaler settings - silently stop applying under the new name. Move them to
[GroovyNLC], or name the section [Groovy*], which prefix-matches both core names.

Note /tmp/CORENAME and /tmp/RBFNAME now read "GroovyNLC" - check any external
scripts (Zaparoo/mrext) that key on the core name.

The server log is /tmp/groovynlc.log. Verbose (OSD > Server > Debug options) is
honoured live - you do not need to save and reload to change the level.

- Only for XDP high performance feature, some tweaks on Linux are needed. For UDP isn't needed.
  1. Replace kernel: zImage_dtb file on /media/fat/linux (is same [kernel](https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/pull/55) with some patches for eth0 driver and builded with CONFIG_XDP_SOCKETS=Y)
  2. Save groovy_xdp_kern.o to /usr/lib/arm-linux-gnueabihf/bpf (this program will be injected on eth while xdp is running)
  3. Save libelf.so.1 on /usr/lib (library requiered)
  4. On MiSTer.ini change binary from MiSTer_groovyNLC to MiSTer_groovy_XDP 
