
## MPD Bare Control (PS)

### Overview

* MPD Bare Control is a minimal Music Player Daemon (MPD) controller providing only basic features (queue all songs, limited playlist support, playback control).
* MPD Bare Control is _not_ a complete MPD control application; it is intended for casual background music listening.
* MPD Bare Control is written in PowerShell and uses a console‑based user interface with keyboard‑driven controls.
* MPD Bare Control is a toy project (for now).
* Tested with Music Player Daemon 0.24.4 running on a Raspberry Pi 2B, with connections from Windows 10/11.


### Installation

1. Download or clone the repository:

2. Run `mpd_control.ps1` or modify and run `mpd_control.bat` (batch file also relaxes local execution policy) :

   ```
   PS C:\MPD-Bare-Control> .\mpd_control.ps1  192.168.1.1
                                                ^- MPD Server Address
   ```


### Screenshots

**Full Dashboard**

![](./mpd-control-full.png)

**Simple Dashboard**

![](./mpd-control-simple.png)


### Known Bugs

 * Elapsed time of the song is an estimate during playback


### Contact:

 Web    : [GitHub](https://github.com/kk-sw/MPD-Bare-Control.git)
 
 Email  : kksw@gmx.com

 
 
