# Groovy core for MiSTer

## General description
This core is a no gpu for crt

To work with, see Windows client examples

#define CMD_CLOSE 1

#define CMD_INIT 2

#define CMD_SWITCHRES 3

#define CMD_BLIT 4

#define CMD_GET_STATUS 5




CMD_CLOSE -> Close emulator. 1 byte udp packet

CMD_INIT -> Prepare emulator to work with (1 byte + 1 byte (0 or 1 for compressed frames) + 2 bytes for default block sizes for compressed frames). Max 4 bytes udp packet

CMD_SWITCHRES -> Switch resolution -> see examples. 27 bytes

CMD_BLIT -> see examples. Max 9 bytes.

CMD_GET_STATUS -> 1 byte. Request frame and vertical count raster position
