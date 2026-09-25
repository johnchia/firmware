# kd110_ssc333_sc3336_rtl8188fu

A KD110v2 camera: an SSC333 (Infinity6B0), a SmartSens SC3336 (3 MP) and a
Realtek RTL8188FU on USB, 8 MB NOR and 64 MB of DRAM. `camera.conf` layers
it on `ssc333_raptor`, which holds everything about the SoC, the flash
layout, the musl-only userland and the software stack; this directory holds
what is soldered around the chip.

## What is on the board

- **Sensor: SC3336**, pinned. The base ships the family's fifteen ISP tuning
  blobs (1387 KB on disk, about 130 KB squashed; the base measures 3828 KB
  of its 5120 KB partition), and the pin ships this one, which is what names
  the image for the part it was tuned for. raptor probes the sensor at
  runtime either way, so a unit with a different part still streams, with
  generic tuning and the colour wrong.
- **Radio: RTL8188FU** over USB, always powered. Nothing has to be driven
  before the dongle appears, so no environment is baked: `8188fu` is the only
  WiFi driver in the image and `/etc/wireless/detect` loads it at boot and
  keeps it once the dongle binds (cold detect measured at 0.62 s, a DHCP lease
  at 13 s of uptime). Setting `wlandev=rtl8188fu-generic` by hand still
  works and still wins; it skips the probe rather than being the only way to
  have a radio. `wlanssid` and `wlanpass` are the credentials and still have
  to be set. The vendor driver is a real cfg80211 phy that registers the AP
  entry point, which is what lets the supplicant raise the setup access point
  (`mode=2` needs `BR2_PACKAGE_WPA_SUPPLICANT_AP_SUPPORT`); nothing else in
  the image does AP mode.
- **Ethernet** is on the SoC but no socket is fitted. An unset `wlandev` used
  to read as "no radio" and fall through to `eth0`, which on this board is a
  camera with no network at all; detection is what closed that. `eth0` sits on
  the 192.168.2.10 static fallback, so pulling the radio out from under a
  test leaves nothing reachable on the bench subnet.
- **Memory.** The bootloader hands Linux about 27.7 MB of the 64 MB (an
  `LX_MEM` of 63.9 MB less a 32 MB MMA carveout, 2 MB of CMA and the kernel),
  and the shared-memory rings come out of that. A 3M + D1 pipeline needs
  about 28 MB of pool and pins userspace at 25 MB; the shipped raptor.conf
  targets 1080p at 20 fps on the main stream. Buffer cost scales with
  resolution and not with frame rate, throughput with frame rate; the SoC is
  rated 3 MP at 20 fps and 2304x1296 H.264 at 30 fps measures 901 frames in
  30 s with no drops.
- **No pin facts** are in the tree for this unit: the IR-cut GPIOs are not
  known, so `raptor.conf` is absent and the filter does not move until they
  are set.

## Verification log

- 2026-07-31: first streaming over RTSP on the Infinity6B0 port, on this
  unit, with zero backend code beyond the family's platform entries.
- 2026-09-09: radio detection verified here: cold `detect` finds the
  RTL8188FU in 0.62 s, and a boot with `wlandev` empty reaches a DHCP lease
  at 13.17 s of uptime.
- 2026-09-25: the camera-named image from this directory, built in a fresh
  tree at 2e36b6b0, flashed on this unit with `sysupgrade-raptor
  --kernel --rootfs`. Two things the flash taught: the unit has 27.7 MB of
  RAM and the updater refused `--archive` (it needs 9683 KB free to unpack
  the archive beside itself and had 7432 KB once raptor was stopped), so the
  kernel and rootfs went over as two files; and the WiFi link dropped during
  the rootfs write as it does on the Wyze, with the unit back 15 s after the
  reboot. Verified on the unit: `BUILD_CAMERA` in os-release names this
  directory, the kernel and rootfs partitions' md5s equal the built files,
  `/etc/sensors` holds `sc3336.bin` alone, the SC3336 is bound to sensor pad
  0, seven daemons up, wlan0 addressed through `detect` and the 8188fu
  module, and `/stream0` serves HEVC 2304x1296 at 15 fps (150 frames in
  10 s). The updater composes
  `openipc.kd110_ssc333_sc3336_rtl8188fu-nor-raptor-latest.tgz` for its next
  fetch. The pinned `ssc333_sc3336_raptor` target this replaced was deleted
  the same day.
