Install instructions

You need last MiSTer main (2025/03/25)

1) Copy "MiSTer_groovy" to /media/fat. If you are using filezilla, be sure transfer is in binary mode.
2) Copy core "Groovy_20250325.rbf" to /media/fat/_Utility
3) Edit "/media/fat/MiSTer.ini" and add custom binary entry to core
   ....
   [Groovy]
   main=MiSTer_groovy
   ...

This method will execute MiSTer_groovy binary when you start core from _Utility
