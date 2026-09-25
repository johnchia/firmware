# h4cx-a0_hi3516cv608_os04d10_rtl8733bu

A Hi3516CV608 camera module, 8 MB NOR, an OmniVision OS04D10 (4 MP) and a
Realtek RTL8733BU on USB. `camera.conf` layers it on `hi3516cv608_raptor`,
which holds everything about the SoC, the flash layout, the kernel and the
software stack; this directory holds what is soldered around the chip.

## Names

The identity is what is printed on the main board, because that is what a
person holding the unit can read:

| Where | Name |
| --- | --- |
| Silkscreen on the main board | **H4CX-A0** |
| The vendor's product name | H438-36 |
| Its stock firmware | H4-52POX-S |

## What is on the board

- **Sensor: OS04D10**, pinned. The 8 MB flash has room for one sensor's ISP
  tuning, and the pin is what puts only that one in the image (the wired
  `hi3516cv608_raptor` carries the family's set and finds its sensor at boot).
  `sensor=os04d10` is set in the unit's U-Boot environment as well; the
  hisilicon load script reads it there.
- **Radio: RTL8733BU** over USB, driven by the generic `rtl8733bu` arm through
  `/etc/wireless/detect`. No `wlandev` is baked: nothing has to be powered
  before the dongle can be found. The USB port on this module supplies no
  VBUS on its own, though. Measured on the bench with every GPIO toggled, the
  pad never leaves 0 V, and the stock firmware ships no USB stack at all, so
  the factory never powered one either. The unit here has 5 V wired to the
  pad; with that the dongle enumerates as `0bda:b733`, `8733bu` binds it and
  `wlan0` scans both bands. A module without the jumper has no USB.
- **Ethernet** is on the SoC but no socket is fitted; `eth0` never has a
  carrier. The radio is the only way in.
- **IR-cut and IR LED pins**, in `raptor.conf`: `gpio_ircut = 61`,
  `gpio_ircut2 = 60`, `gpio_irled = 8`. These are what the unit's own
  `/etc/raptor.conf` carried in its overlay on 2026-09-25, read off the
  running camera. Whether the filter switches on those pins has not been
  watched from the bench; that is the open item on this camera.
- **The LED comes on at boot** under OpenIPC's U-Boot. GPIO 63 idles high. The
  stock bootloader's board init drives it low (GPIO7_7 through the pad
  controller at 0x11097000) before Linux starts; OpenIPC's U-Boot touches no
  GPIO, so the pad sits at its reset default until the daemons take it. Not
  fixed: the per-unit workaround is a `bootcmd` that writes the pad, and the
  proper one is a board hook in the U-Boot tree.

## Layout and bootloader

The unit runs OpenIPC's layout on a source-built U-Boot since 2026-09-25:
`256k(u-boot),64k(env),2048k(kernel),5120k(rootfs),-(rootfs_data)`, the
environment on `mtd1` found by autosearch, the overlay on `mtd5`. Before that
it ran the vendor's table with the stock bootloader in place and the
overlay in the vendor's `rootfs_data`; the `devinfo` partition that table
had is gone (it sits inside `rootfs_data` now) and the stock bootloader,
environment and devinfo were dumped before the move. The whole-flash image
this camera builds (`openipc-h4cx-a0_hi3516cv608_os04d10_rtl8733bu-nor-raptor-full.bin`)
carries a fresh environment, so a unit flashed with it loses its WiFi keys
and comes up as a new camera; the unit here had `ethaddr`, `wlanssid`,
`wlanpass` and `netaddr_fallback` carried across by hand.

The boot image is the same one `hi3516cv608_raptor` builds, with the DMEB
DDR2-1333 64 MB table every CV608 seen so far runs.

## Memory

`osmem=44M` on this unit, set by hand, against the family env's 36M. With
the full 4 MP pipeline running (2560x1440 H.265 at 25 fps) the MMZ is the
tight side: a 20480 KB zone with 18936 KB used after five and a half hours,
while Linux still had 13 MB of its 39 MB available and no OOM kills. That is
the reverse of what the 36M figure was measured for, and 44M is a candidate
for the family default once the pipeline has proven it.

## Verification log

- 2026-09-25: flashed with `sysupgrade-raptor --full -n` from build
  `bd0a6d0c-dirty` (the `hi3516cv608_os04d10_raptorwifi` target this camera
  replaces, with the single sensor pin and the source-built U-Boot). Boots
  on the new layout, rejoins the WiFi network from the carried keys, streams
  2560x1440 H.265 at 25 fps with zero encoder skips.
- Earlier, on the vendor's table with the stock bootloader: booted to a root
  shell from an environment saved to `mtd1` with no serial console attached,
  the overlay mounting jffs2, a root password surviving reboot; then the
  4 MP pipeline at 25 fps on build `94cc31b0` (2026-09-24).
- Not yet verified on this camera's own image: the IR-cut pins above.
