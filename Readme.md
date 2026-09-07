# GroovyNLC

<img width="64" height="64" alt="GroovyNLC" src="https://github.com/user-attachments/assets/6e9e3c9b-c168-43fd-871a-d2211153b7be" />

GroovyNLC turns a MiSTer into an analog GPU for CRTs. An emulator running on your PC sends
each frame over Ethernet and the FPGA scans it straight out, with no scaler and no buffered
frame in between. It is a fork of
[psakhis/Groovy_MiSTer](https://github.com/psakhis/Groovy_MiSTer), which is where the core
and the original design come from.

What this fork adds:

- **NLC compression.** YCoCg-R colour with Golomb-Rice coding, lossless or near lossless.
  Between 2.4 and 4.1 times smaller than raw at the default setting, depending on the
  content, which is what makes 480p stable.
  [Numbers below](#bandwidth).
- **Connection handling.** Reconnect, keepalive, and an idle timeout so a crashed emulator
  releases the display instead of freezing the last frame.
- **Full controller support**, including DualShock rumble and analog triggers.
- **A Controllers page in the OSD.** Per-pad profiles, single-button remaps, and per-profile
  rumble and stick inversion.

Builds are on the [Releases page](https://github.com/verbst/Groovy_MiSTer/releases). For
help or updates, find us on the MiSTer Discord.

## Requirements

- A MiSTer with a current MiSTer main install.
- Gigabit Ethernet between the PC and the MiSTer. A switch is fine. Wi-Fi is not.
- A static IP at each end.
- An emulator build with NLC support, listed under [Emulators](#emulators). Older Groovy
  clients still work, without NLC.

## Install

1. Download the latest release. Copy `GroovyNLC_*.rbf` to `/media/fat/_Utility` and
   `MiSTer_groovyNLC` to `/media/fat`. If you use FTP, transfer in binary mode.

2. Add this to `/media/fat/MiSTer.ini`:

   ```
   [GroovyNLC]
   main=MiSTer_groovyNLC
   ```

   The section name has to be `GroovyNLC`, which is the core's name, not the `.rbf`
   filename. You can rename the `.rbf` to anything. The original Groovy core can stay
   installed next to this one with its own `[Groovy]` section.

3. Start the core from `_Utility`. A bouncing logo means the core is running and waiting for
   an emulator to connect. It disappears as soon as frames start arriving.

The core listens on UDP **32100** for video and control, and UDP **32101** for inputs. The
emulator connects to both.

### MiSTer.ini keys worth knowing

| Key | What it does |
|---|---|
| `[Groovy*]` as the section heading | Prefix-matches both `Groovy` and `GroovyNLC`. Use it if you already had settings under a literal `[Groovy]` heading, otherwise they stop applying under the new name. |
| `player_1_controller=` left blank | In this build an empty value clears the assignment inherited from `[MiSTer]`, so that pad goes back to being picked by press order. Applies to players 1 to 6 and to `deadzone`. |
| `rumble=0` | Turns rumble off for every pad, overriding the per-profile Rumble setting on the Controllers page. |

### Upgrading from Groovy

Settings and button maps carry over on their own. If the GroovyNLC-named files are missing,
the binary reads the old Groovy-named ones and writes the new name the next time you save or
define a button.

Two things do not carry over. Any other keys under a literal `[Groovy]` heading in
`MiSTer.ini` need moving, as above. And scripts that key on the core name will now see
`GroovyNLC` in `/tmp/CORENAME`. The server log is `/tmp/groovynlc.log`.

## Emulators

These emulators have been built with NLC support:

| Emulator | Notes |
|---|---|
| [MiSTerCast](https://github.com/verbst/MiSTerCast) | Windows desktop mirroring. Thanks to @Shane. |
| [Fightcade - FBNeo](https://github.com/verbst/fightcade-fbneo) | |
| [Fightcade - Dojo Flycast](https://github.com/verbst/flycast-dojo) | |
| [PCSX2](https://github.com/verbst/pcsx2) | DualShock input with rumble. Set the pad to Analog. |
| [RPCS3](https://github.com/verbst/rpcs3) | DualShock input with rumble. Set the pad to Analog. |
| [RetroArch](https://github.com/verbst/RetroArch) | |
| Flycast (non-Dojo) | In progress. |

Older Groovy clients such as GroovyMAME still work. They connect and display normally, they
just fall back to raw or LZ4 and the original input set, so no NLC and no extended controller
support.

Install this release's `MiSTer_groovyNLC` before testing an NLC client. An older binary
reports version 1 and the client quietly falls back to the old input protocol, which means no
rumble and no analog triggers. The client log says `Core version 1 < 2` when that happens.

## Settings

Everything on the Server page is read when the server starts, so save and reload the core to
apply it. Verbose is the exception and takes effect immediately.

A fresh install with no saved config starts with Audio on and Joysticks set to Analog, so
sound and pads work before you open the menu.

Changes apply as soon as you make them, but they are not kept. Pick *Save settings* in the OSD
to write them out, or the core comes back on its defaults next time you load it. That is how
every MiSTer core works and is nothing specific to this one.

### Video

| Option | Default | What it does |
|---|---|---|
| Scandoubler Fx | None | Scanline effect on the scaler output. |
| Aspect ratio | Original | Picture aspect on the scaler output. Hidden with direct video. |
| Scale | Normal | Integer scaling on the scaler output. Hidden with direct video. |
| Orientation | Horz | Rotates the picture for a vertical monitor. Hidden with direct video. |
| 240p Crop | Off | Crops a 240p picture. Only offered with the scandoubler off, Scale at Normal and direct video off. |
| Crop Offset | 0 | Shifts the crop window. Only shown when 240p Crop is on. |
| CRT H offset | 0 | Nudges the analog picture horizontally. |
| CRT V offset | 0 | Nudges the analog picture vertically. |
| CRT scale enable | Off | Horizontal size adjustment on the analog output. Not supported on interlaced modes. |
| CRT scale factor | 0 | How much to adjust. Only shown when CRT scale is enabled. |
| PWM | Off | PWM mode on the analog video output. Leave off unless your output board needs it. |
| Volatile framebuffer | Off | (Off required for NLC) Off lets the core scan the framebuffer continuously, which is how NLC gets to the screen at all. On disables that path, and Framebuffer lead with it. |
| Framebuffer lead | 1 | How far ahead of the beam the core reads. Adds latency. See [below](#framebuffer-lead). |
| Vsync overlay | Off | Draws a vsync marker over the picture for checking sync timing. |
| RGB mode | 888 | Greyed out. Shows the pixel format the connected client negotiated. |
| LZ4 frames | Off | Greyed out. Shows the compression the connected client negotiated. |

### Audio

| Option | Default | What it does |
|---|---|---|
| Audio | On | Audio stream from the client. If there is no sound, check here first. |
| Desired buffer (ms) | 0 | Audio buffer depth. 0 is the lowest latency. Raise it if audio breaks up. |
| Rate | - | Greyed out. Shows the sample rate the client negotiated. |
| Channels | - | Greyed out. Shows the channel count the client negotiated. |

### Server

| Option | Default | What it does |
|---|---|---|
| Screensaver | On | The bouncing logo shown while nothing is connected. |
| ARM clock | Stock | Overclocks the MiSTer's CPU. Stock is 800 MHz, +200 is 1000, +400 is 1200. Reverted when you leave the core. |
| Jumbo frames (Max MTU) | Off | Sets the MiSTer's network MTU to 3800. Your PC's adapter and the emulator both have to be set to 3800 as well. |
| Idle timeout | 5s | Closes the session if the client stops sending, so the display is released when an emulator crashes or is killed. Clients that sit paused send a keepalive to hold it open. Off restores the old behaviour of holding the last frame indefinitely. |
| PS2 | Off | Streams keyboard, or keyboard and mouse, to the client. |
| Joysticks | Analog | Streams pads to the client. Analog is required for sticks and triggers. |
| Verbose | Off | Log detail in `/tmp/groovynlc.log`. The only option here that applies without a reload. |
| Blit at | ASAP | ASAP starts the FPGA reading as soon as data arrives. End Line waits for the line to finish. |
| Server type | UDP | Greyed out. Shows whether the running binary is the UDP or the XDP build. |

`Load Gmc`, at the top of the menu, sends a `.gmc` file from the SD card to a listener on UDP
32105. It is for launcher integrations and is not needed for normal emulator use.

### Framebuffer lead

This feature is seldomly required.

*OSD > Video > Debug options > Framebuffer lead*

How many lines ahead of the beam the core reads the framebuffer. On NLC the decoder is still
filling that framebuffer while the beam scans it, so every line is shown as it stood this far
in advance. A larger lead rides out longer memory stalls, and costs you exactly that delay.

| Framebuffer lead | 15 kHz (240p, 480i) | 31 kHz (480p) |
|---|---|---|
| 1 (default) | 0.06 ms | 0.03 ms |
| 4 | 0.25 ms | 0.13 ms |
| 8 | 0.51 ms | 0.25 ms |
| 16 | 1.02 ms | 0.51 ms |

Leave it at 1. Raise it one step at a time only if the picture smears under load. It is read
when a session starts, so reconnect the emulator after changing it, and it needs Volatile
framebuffer set to Off.

Note: This feature will not resolve network bandwidth issues! 

### Controllers

*OSD > Controllers*

Each pad gets a nickname, a type (Arcade stick, DualShock, Xbox or Gamepad, picked from the
USB vendor by default), and ten profiles. Left and right on a profile row switches profiles
without leaving the page, which is the quick way to swap between emulators that want
different layouts. Each profile carries its own button map, Rumble setting and Invert stick Y
setting, and you can redefine one button or all of them.

Reassign players clears the player slots so the next pads pressed take them in order. It also
suspends any `player_N_controller` assignment from `MiSTer.ini` until the core is reloaded.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Core sits on the logo | Nothing has connected. Check the MiSTer's IP and that the emulator is pointed at it. |
| No rumble or analog triggers | An older binary is installed. The client log will say `Core version 1 < 2`. Also check Joysticks is set to Analog and the pad's Rumble is On. |
| Garbage picture, no error | The client is set to Rice compression but the core cannot decode it. Use the current release `.rbf` paired with the related `MiSTer_groovyNLC`. |
| Muted, pads ignored, right after switching from Groovy | The config did not migrate. See [Upgrading from Groovy](#upgrading-from-groovy). |
| A second emulator takes over the display | The core does not reserve a session. Run one client at a time. |
| Picture freezes or goes black on NLC after the first frame | Volatile framebuffer is On. NLC is displayed by scanning the framebuffer, so it needs this Off. |

## Bandwidth

Two RPCS3 captures at 640x480p60, both measured the same way: a 3D title (120 frames) and
BlazBlue (600 frames across five sessions). All figures are Mbps. The worst column is the
single heaviest frame in the capture, which is what decides whether the link holds, and it is
where the codecs separate. The LZ4 rows compress the pixel buffer directly, as the client
does. Ratio is against raw RGB888 and spans the two captures.

| Codec | Format | Ratio vs raw | 3D mean | 3D worst | 2D mean | 2D worst |
|---|---|---|---|---|---|---|
| raw | RGB888 | 1.0 | 442.4 | 442.4 | 442.4 | 442.4 |
| lz4 | RGB888 | 1.1 to 1.9 | 393.3 | 397.3 | 231.2 | 369.4 |
| raw | RGB565 | 1.5 | 294.9 | 294.9 | 294.9 | 294.9 |
| nlc n0, lossless | RGB888 | 1.7 to 3.1 | 263.4 | 269.3 | 142.3 | 216.6 |
| lz4 | RGB565 | 2.1 to 4.2 | 213.8 | 218.4 | 106.6 | 189.0 |
| nlc n1, default | RGB888 | 2.4 to 4.1 | 188.3 | 193.2 | 109.3 | 151.8 |
| nlc n2 | RGB888 | 2.8 to 4.5 | 158.8 | 162.7 | 99.0 | 128.8 |

How much anything compresses depends heavily on the content, which is why both captures are
here. Flat 2D art roughly doubles every ratio over a busy 3D scene.

Compare the mean and worst columns rather than the means alone. On 2D content LZ4 averages
231.2 but spikes to 369.4 on its heaviest frame, and those spikes are what stall the link.
NLC holds a much tighter spread: near level 1 averages 109.3 and peaks at 151.8 on the same
frames.

NLC is RGB888 only, and the client rejects any other pixel format at connect time. Raw and
LZ4 can send RGB565 instead, which halves the data before compression and is why those rows
place well. It costs you 16 bit colour.

Near level 1 is the recommended setting. Its worst frame is 193.2 Mbps, about 24 MB/s, under
the roughly 38 MB/s the core can ingest, and its error bound of plus or minus 1 is invisible
on a CRT. LZ4 at 565 comes close on the 2D average, but its heaviest frame is worse, 189.0
against 151.8, and it gives up full colour to get there. Level 0 is lossless if you have the
headroom. At 240p the figures scale with the pixel count, so roughly a quarter of these.

## Thanks

@psakhis for all your work, making this all possible

@Calamity for hard testing core and implement GroovyMAME for it

@sorgelig for developing and maintaining MiSTer

@jotego, for analog adjustment module

@alanswx for their [lessons](https://github.com/alanswx/Tutorials_MiSTer)

@wickerwaka for their tips using ddr

@coolbho3k for their [overclock](https://github.com/coolbho3k/MiSTer-Overclock-Scripts)

The Mednafen, MAME and RetroArch teams

@alexxnr for testing it and encourage me in the project

[GroovyArcade Discord](https://discord.gg/YtQ6pJh) #nogpu, MiSTer Discord #dev-talk

[Upstream history](https://github.com/psakhis/Groovy_MiSTer/blob/main/history.txt)
