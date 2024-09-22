Install instructions

You need last MiSTer main (2024/03/25)

Full source code [MiSTer_groovy](https://github.com/psakhis/Main_MiSTer)

1) Copy "MiSTer_groovy" to /media/fat. If you are using filezilla, be sure transfer is in binary mode.
2) Copy core "Groovy_20250922.rbf" to /media/fat/_Utility
3) Edit "/media/fat/MiSTer.ini" and add custom binary entry to core
   ....
   [Groovy]
   main=MiSTer_groovy
   ...

This method will execute MiSTer_groovy binary when you start core from _Utility

- Only for XDP high performance feature, some tweaks on Linux are needed. For UDP isn't needed.
  1. Replace kernel: zImage_dtb file on /media/fat/linux (is same [kernel](https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/pull/55) with some patches for eth0 driver and builded with CONFIG_XDP_SOCKETS=Y)
  2. Save groovy_xdp_kern.o to /usr/lib/arm-linux-gnueabihf/bpf (this program will be injected on eth while xdp is running)
  3. Save libelf.so.1 on /usr/lib (library requiered)
  4. On MiSTer.ini change binary from MiSTer_groovy to MiSTer_groovy_XDP 
