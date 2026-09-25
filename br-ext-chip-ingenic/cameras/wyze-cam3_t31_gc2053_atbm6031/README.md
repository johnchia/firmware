# wyze-cam3_t31_gc2053_atbm6031

The Wyze Cam v3: an Ingenic T31X, a GalaxyCore GC2053 (2 MP) and an AltoBeam
ATBM6031 on SDIO, 16 MB NOR. `camera.conf` layers it on `t31_raptor`, which
holds everything about the SoC, the uClibc userland the vendor libraries
need, the bootloader build and the flash layout; this directory holds what
is soldered around the chip.

## What is on the board

- **Sensor: GC2053**, pinned. This 3.10 kernel has no `/proc/jz/sensor` for
  rvd to ask, so raptor-streaming's post-build hook pins the sensor's name,
  I2C address and size into `/etc/raptor.conf` from the one yaml the pin
  installs. The size matters as much as the address: without it rvd cannot
  tell whether the substream needs the IPU scaler, and it streams sheared
  magenta-and-green while the main stream is perfect.
- **Radio: ATBM6031** over SDIO, and the only network interface: the board
  has no Ethernet PHY. `wlandev=atbm603x-t31-wyze-v3` in `uboot.env.txt`
  selects the bring-up sequence in the shared `/etc/wireless/sdio`, which
  opens by power-cycling the radio on GPIO 57 and stages the two calibration
  files. Detection never runs here and could not stand in: a part with no
  power is not on the bus to be found. `wlanssid` and `wlanpass` are the
  credentials. The driver advertises AP mode, so the supplicant alone serves
  the setup access point.
- **No serial header.** A unit that boots but fails to associate is
  indistinguishable from one that never booted, so the family overlay's
  `sddiag` writes a boot report to the SD card at S01 and S99, and which
  reports appear is the signal.
- **The SD slot is the recovery path,** and the bootloader's pins for it are
  in `camera.conf`: slot power on GPIO 48 (active low), card detect on 59,
  the reset button on 51. Without the first two U-Boot cannot read the card.
  The environment's `autoupdate` verb rewrites the whole chip from
  `autoupdate-full.bin` on a FAT32 card and `loaduenv` imports `uenv.txt`,
  which is how WiFi credentials reach a camera with no other interface;
  holding the button at boot runs `overlay_wipe`. Those verbs are
  transcribed from a working unit and are the only way back in, so the
  environment is changed only against a unit reachable another way.
- **The bootloader** is gtxaspec's mainline U-Boot port for the T-series,
  pinned by commit in the base. The 2013.07 ISVP tree is not interchangeable:
  no `fatwrite`, no device-tree MMC, no button at boot, so it cannot run the
  recovery path above.
- **The root is the older `overlayfs`** on this kernel, with the whole
  `rootfs_data` partition as the upper directory, not `/overlay/root`.

## Flashing

`sysupgrade-raptor` over WiFi works, with one thing to expect: the link drops
during the rootfs write, because the supplicant pages from the squashfs
being erased. The flash completes from the RAM root and the unit is back in
about a minute. The whole-flash image
(`openipc-wyze-cam3_t31_gc2053_atbm6031-nor-raptor-full.bin`) carries the
bootloader and the environment above at 0x50000, so a unit flashed with it
comes up with no WiFi keys and raises its setup access point. A full 16 MB
dump of the bench unit was taken before its first flash.

## Verification log

- 2026-09-22: running the nightly `nightly-20260922-95a2ca2` of `t31_raptor`,
  flashed with `sysupgrade-raptor --github`; the link drop during the write
  observed and the unit back within a minute.
- Earlier, on `t31_raptor` after the move to uClibc: eight daemons, zero
  faults, H.264 1920x1080 and 640x360 over RTSP, JPEG snapshots, 16 kHz audio.
- 2026-09-25: the camera-named image from this directory, built in a fresh
  tree at 2e36b6b0, flashed with `sysupgrade-raptor` over WiFi. The link
  dropped during the rootfs write as above and the unit was back in about
  10 s of the reboot. Verified on the unit: `BUILD_CAMERA` in os-release names
  this directory, the sensor is pinned (gc2053 at 0x37, 1920x1080), seven
  daemons up, wlan0 associated, and the rootfs partition's md5 equals the
  built squashfs. The updater composes
  `openipc.wyze-cam3_t31_gc2053_atbm6031-nor-raptor-latest.tgz` for its next
  fetch. The base without the fragment is now an SoC target with no radio,
  every sensor's yaml, and no baked environment; it has not been flashed on
  its own.
