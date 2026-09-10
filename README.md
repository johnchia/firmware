# openipc-raptor

A fork of [OpenIPC/firmware][upstream] that builds camera images running
**[Raptor][raptor]** as the streamer instead of Majestic.

## Differences from OpenIPC

- **Raptor replaces Majestic** as the streamer: a set of small daemons sharing
  frames through shared memory, all GPL-3.0 and rebuildable, where the stock
  image runs one closed binary.
- **Retuned ISP calibration** -- IMX335 on infinity6c, GC4653 on infinity6e,
  IMX335 on hi3516ev300.
- **Sensor driver fixes.** SC450AI reports its model ID, so the ISP loads its
  IQ tuning instead of none; and mirror/flip is applied on nine SigmaStar
  drivers that staged the register and then dropped it.
- **Wi-Fi setup portal.** A camera with no network configured raises its own
  access point and serves a setup page instead of sitting unreachable.
- **A MAC address per camera,** derived from the flash unique ID or the SoC die
  ID, so two cameras on one network do not arrive sharing one.
- **A hostname per camera,** derived from the SoC and the sensor.
- **mDNS announcement,** on the SigmaStar and Ingenic boards.

![The Raptor configuration console](docs/console.png)

## Boards

| Board | SoC · family | Rootfs | Download |
|---|---|---|---|
| `ssc377qe_raptor` | SSC377QE · infinity6c | 8192 KB | [sysupgrade][t-377] · [whole-flash][f-377] |
| `ssc377d_raptor` | SSC377D · infinity6c | 8192 KB | [sysupgrade][t-377d] · [whole-flash][f-377d] |
| `ssc30kq_raptor` | SSC30KQ · infinity6e | 8192 KB | [sysupgrade][t-30k] · [whole-flash][f-30k] |
| `ssc333_sc3336_raptor` | SSC333 · infinity6b0 | 5120 KB | [sysupgrade][t-333] |
| `t31_raptor` | T31X · ingenic | 8192 KB | [sysupgrade][t-t31] · [whole-flash][f-t31] |
| `hi3516ev300_raptor` | Hi3516EV300 · hi3516ev200 | 10240 KB | [sysupgrade][t-ev300] |
| `hi3516ev200_raptor` | Hi3516EV200 · hi3516ev200 | 5120 KB | [sysupgrade][t-ev200] |
| `hi3516cv608_os04d10_raptor` | Hi3516CV608 · hi3516cv6xx | 5184 KB | [sysupgrade][t-cv608] |
| `hi3516cv608_os04d10_raptorwifi` | Hi3516CV608 · hi3516cv6xx | 5184 KB | [sysupgrade][t-cv608w] |

## Before you flash

> **These are experimental builds. Have a recovery path before you write one
> to a camera.**

A recovery path means a way to get the camera booting again when the image you
just wrote does not: soldered UART leads you have already used once, or a SPI
flash clip and a programmer. Not a plan to acquire one afterwards. Nothing in
this fork is widely deployed, several targets have run on exactly one unit, and
a rootfs is only discovered to be bad after it has been written to flash.

Read the wiki on [flashing][wiki-flash] and [serial/UART][wiki-uart] first if
you have not done this before.

## Installing

These images are ordinary OpenIPC `sysupgrade` archives. Upgrading an existing
OpenIPC camera may or may not work depending on which variant it runs
(`lite`, `ultimate`) and the partition layout it was flashed with.

```sh
ssh root@<board> 'sysupgrade --url=<link from the table>'
```

## Configuring a running camera

The configuration console is at `http://<camera>:8080/`.

A new camera ships **unclaimed**: root has no password, so nothing can be
configured and anyone who can reach the camera can take it. Claiming it means
setting that password, and it is what protects the console afterwards. Three
doors do it, and any one is enough:

- the console at `http://<camera>:8080/`, which draws a claim card instead of
  its settings while the camera has no password;
- the setup page on the camera's own access point, if it has no network yet;
- SSH -- log in as `root` with an empty password and it prompts for one.

They all write the same file and read it live, so whichever you use, the other
two see it immediately. `sysupgrade -n` wipes the overlay and returns the
camera to unclaimed, which is also the way back from a forgotten password.

## Licence and credit

This build tree is MIT, inherited from upstream OpenIPC. **Raptor itself is
GPL-3.0** -- all four of its repositories are -- so an image built here mixes
the two, and the Raptor daemons carry GPLv3 obligations that the rest of the
tree does not.

OpenIPC is the reason any of this boots at all: kernel, bootloader, vendor
packaging and the Buildroot tree are theirs. See the [project][project], the
[website][website] and the [wiki][wiki], and consider supporting them at
[Open Collective][opencollective].

[t-377]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc377qe-nor-raptor-latest.tgz
[t-377d]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc377d-nor-raptor-latest.tgz
[t-30k]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc30kq-nor-raptor-latest.tgz
[t-333]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc333_sc3336-nor-raptor-latest.tgz
[t-t31]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.t31_gc2053-nor-raptor-latest.tgz
[t-ev200]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.hi3516ev200-nor-raptor-latest.tgz
[t-ev300]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.hi3516ev300-nor-raptor-latest.tgz
[t-cv608]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.hi3516cv608-nor-raptor-latest.tgz
[t-cv608w]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.hi3516cv608-nor-raptorwifi-latest.tgz
[f-377]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc377qe-nor-full.bin
[f-377d]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc377d-nor-full.bin
[f-30k]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc30kq-nor-full.bin
[f-t31]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-t31-nor-full.bin
[opencollective]: https://opencollective.com/openipc
[project]: https://github.com/openipc
[wiki-flash]: https://github.com/OpenIPC/wiki/blob/master/en/equipment-flashing.md
[wiki-uart]: https://github.com/OpenIPC/wiki/blob/master/en/serial_pins_uart.md
[raptor]: https://github.com/gtxaspec/raptor
[upstream]: https://github.com/OpenIPC/firmware
[website]: https://openipc.org
[wiki]: https://github.com/openipc/wiki
