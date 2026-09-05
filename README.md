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

Every board here is tested on hardware and in service, but none is widely
tested. Flash at your own risk.

## Installing

These images are ordinary OpenIPC `sysupgrade` archives. Upgrading an existing
OpenIPC camera may or may not work depending on which variant it runs
(`lite`, `ultimate`) and the partition layout it was flashed with.

```sh
ssh root@<board> 'sysupgrade --url=<link from the table>'
```

## Configuring a running camera

The configuration console is at `http://<camera>:8080/`.

A new camera ships unclaimed and has to be claimed over SSH before anything
else: log in as `root` with an empty password, and it will prompt you to set
one. That password is what protects the console.

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
[f-377]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc377qe-nor-full.bin
[f-377d]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc377d-nor-full.bin
[f-30k]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-ssc30kq-nor-full.bin
[f-t31]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc-t31-nor-full.bin
[opencollective]: https://opencollective.com/openipc
[project]: https://github.com/openipc
[raptor]: https://github.com/gtxaspec/raptor
[upstream]: https://github.com/OpenIPC/firmware
[website]: https://openipc.org
[wiki]: https://github.com/openipc/wiki
