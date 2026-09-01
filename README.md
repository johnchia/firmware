# openipc-raptor

A fork of [OpenIPC/firmware][upstream] that builds camera images running
**[Raptor][raptor]** as the streamer instead of Majestic. Raptor is fully open
source under the **GPL-3.0**, so unlike the closed binary it replaces,
everything that touches the camera here can be read, patched and rebuilt. Where
the stock image runs one `majestic` process, these run a set of small daemons
that share frames through POSIX shared-memory rings: a crash in the RTSP parser
cannot take recording down with it, and nothing that reads from the network
shares an address space with the vendor SDK.

Everything that is not Raptor is upstream's -- this tracks `OpenIPC/firmware`
master and merges from it. Bug reports about anything else belong there.

![The Raptor configuration console](docs/console.png)

## Boards

| Board | SoC · family | Rootfs | Download |
|---|---|---|---|
| `ssc377qe_raptor` | SSC377QE · infinity6c | 8192 KB | [sysupgrade][t-377] · [whole-flash][f-377] |
| `ssc377d_raptor` † | SSC377D · infinity6c | 8192 KB | [sysupgrade][t-377d] · [whole-flash][f-377d] |
| `ssc30kq_raptor` | SSC30KQ · infinity6e | 8192 KB | [sysupgrade][t-30k] · [whole-flash][f-30k] |
| `ssc333_sc3336_raptor` | SSC333 · infinity6b0 | 5120 KB | [sysupgrade][t-333] |
| `t31_raptor` | T31X · ingenic | 8192 KB | [sysupgrade][t-t31] · [whole-flash][f-t31] |

† `ssc377d_raptor` builds and is published like the rest, but has never been
booted on hardware. It is `ssc377qe_raptor` with the SoC model and the kernel
config changed, so its rootfs partition size is inherited rather than read off a
board: check `cat /proc/mtd` against the 8192 KB above before trusting a write.

Those links are rolling: each is the `-latest` asset on the
[`raptor-nightly`][nightly] release, rewritten by every nightly that publishes,
with the dated build kept alongside it. `sysupgrade` takes a `.tgz` straight
off the URL:

```sh
ssh root@<board> 'sysupgrade --url=<link from the table>'
```

The `.bin` is a whole-flash image, bootloader included, for a camera running
factory firmware or whose flash is in an unknown state; it needs a programmer
or U-Boot rather than `sysupgrade`.

`ssc333_sc3336_raptor` is an 8MB part where the other two are 16MB. U-Boot's
two-layout rule cannot hand out the larger rootfs on a chip that small, so
5120 KB is the partition rather than a policy, and the image is built against
that ceiling -- one sensor tuning blob, no WireGuard, exFAT or vtund. Its only
interface is a USB radio (RTL8188FU), which is also why it publishes no
whole-flash image: the credentials it joins a network with live in the U-Boot
environment a full write erases.

`t31_raptor` is the first Ingenic board here and the reason for one is the
radio: the SigmaStar bench boards are wired, so nothing about credentials or
the setup portal can be developed on them. A Wyze Cam v3 -- T31X, GC2053,
AltoBeam ATBM6031 over SDIO, 16MB of NOR, no Ethernet at all. It publishes a
whole-flash image where `ssc333_sc3336_raptor` does not, and the difference is
recovery rather than layout: a full write erases its environment too, but an
unprovisioned unit raises its own access point and serves the setup page, and
its bootloader can be driven from an SD card. It is also the only board here
that builds its own toolchain -- uClibc, because the Ingenic vendor libraries
are uClibc builds and musl gets the ABI wrong in ways a shim cannot fix.

These are the boards that get tested, not the limit of what works. The backend
is picked from `BR2_OPENIPC_SOC_FAMILY` and the HAL is written per family
rather than per board, so **any infinity6c, 6e or 6b0 board should build and
run**, and on Ingenic the same holds for T31. Adding one is a defconfig: copy the stock `_lite_defconfig` for that
board, swap `BR2_PACKAGE_MAJESTIC` for `BR2_PACKAGE_RAPTOR_STREAMING`, and set
`BR2_OPENIPC_VARIANT="raptor"`. Sensor, i2c bus, IR-cut GPIO and audio codec
live in `raptor.conf` rather than in code, and the sensor is probed at runtime.
`make list` shows every board in the tree, upstream's included.

## Daemons in these images

Raptor is modular and each image installs only what it needs. These boards
ship:

| | Role |
|---|---|
| `rvd` | Owns the ISP, sensor and encoders. Publishes the `main`, `sub`, `jpeg0` and `jpeg1` rings. The only daemon that touches the vendor SDK. |
| `rsd` | RTSP/RTSPS, Digest auth, ONVIF Profile T audio backchannel. |
| `rad` | Audio capture and encode (G.711, L16, AAC, Opus), speaker output. |
| `rod` | Renders OSD text and logos into shared buffers; no hardware dependency. |
| `ric` | IR-cut day/night control -- luma plus gain-ratio, or an ADC or GPIO sensor. |
| `rhd` | HTTP: JPEG snapshots, MJPEG, audio, and the configuration console. |
| `rcd` | Owns `raptor.conf`. Validates against a published schema, applies what a running daemon can take live, and sequences the restarts for what it cannot. |
| `rmq` | MQTT bridge with Home Assistant discovery. |
| `raptorctl` | Command-line client for all of the above. |

## Building

```sh
make BOARD=ssc377qe_raptor all        # kernel, rootfs, and the sysupgrade .tgz
make BOARD=ssc377qe_raptor fullimage  # the whole-flash .bin, from those pieces
```

Output is in `output/images/`, with `openipc.<soc>-nor-raptor-latest.tgz`
symlinked to the build just made. `make help` covers the rest.

The nightly (`.github/workflows/raptor-nightly.yml`) builds all four boards
on a schedule, but only when the image would actually differ: Raptor is
commit pins rather than a moving branch, so an image is a function of HEAD plus
the pin list, and both are compared against what the last nightly recorded in
its own release notes. A quiet week publishes nothing.

Raptor itself is four pinned commits from `github.com/johnchia` -- `raptor`,
`raptor-hal`, `raptor-common`, `raptor-ipc` -- so a build needs no checkout. A
fifth pins the vendor headers `raptor-hal` reaches through a submodule, since
GitHub's source archives omit submodule contents; re-read it from the gitlink
whenever the HAL pin moves:

```sh
git -C raptor-hal ls-tree <hal-pin> sigmastar-headers
```

All five live in `general/package/raptor-streaming/raptor-streaming.mk`, which
documents the coupling at length. The build directory is named after the
**raptor** pin alone, so run `make BOARD=<board> br-raptor-streaming-dirclean`
whenever any of the other four moves.

Everything else in this tree is upstream's, and so is the guide to it:
[CLAUDE.md](CLAUDE.md) (also readable as `AGENTS.md`) explains how the Buildroot
tree is put together and which changes belong in which repository, with the
review standards in [best_practices.md](best_practices.md). A change to
anything but Raptor is a change to send there.

## Installing

`sysupgrade` checks the md5 of each part and the SoC each was stamped for, then
pivots into a ramfs so it is not reading from the partition it is about to
write:

```sh
scp -O output/images/openipc.ssc377qe-nor-raptor-latest.tgz root@<board>:/tmp/fw.tgz
ssh root@<board> 'sysupgrade --archive=/tmp/fw.tgz'
```

The board reboots itself. `cat /etc/os-release` afterwards says which build
actually came up -- worth checking, because a kernel whose build id matches the
running one is skipped with `Same version, nothing to update` and the reboot
happens anyway. `--force_ver` reflashes an identical build.

`flashcp` writes a single partition, for a kernel-only change or a board that
will not boot far enough to run `sysupgrade`:

```sh
scp -O output/images/uImage.ssc377qe          root@<board>:/tmp/uImage
scp -O output/images/rootfs.squashfs.ssc377qe root@<board>:/tmp/rootfs.sq

ssh root@<board> '/etc/init.d/S95raptor stop'
ssh root@<board> 'flashcp /tmp/uImage /dev/mtd2'       # kernel
ssh root@<board> 'flashcp /tmp/rootfs.sq /dev/mtd3'    # rootfs
ssh root@<board> 'head -c <bytes> /dev/mtd3 | md5sum'  # verify, then reboot
```

Verify with `head -c` and the exact byte count, never `dd bs=<size> count=1`:
reading past the image returns 0xff padding, and `dd` takes one short read from
an mtd character device and hashes a partial block.

## Configuring a running camera

`rcd` owns `/etc/raptor.conf`. Three clients reach it, none of which writes the
file itself: the **web console** at `http://<camera>:8080/`, rendered from
`rcd`'s own schema so the form comes from the camera rather than a second copy
of the key table; **`raptorctl config get|set|apply|pending`** on the camera;
and **MQTT**, through `rmq`.

A `set` never restarts anything. Keys a running daemon can take live are
applied immediately; the rest are written and their owner recorded as running
behind, and `apply` is the explicit step that enacts the difference.

### Authentication

Two credentials, deliberately separate:

- **The system account** (`/etc/shadow`) authenticates the configuration API,
  `POST /api/v1/rcd`, and nothing else authenticates it. That route can rewrite
  the network stanza and restart the pipeline, so it takes the one secret on
  the camera that is not also handed out to watch video.
- **`[rtsp]` and `[http]` username/password** are the media credential -- RTSP
  Digest and HTTP Basic for snapshots and MJPEG. `rcd` writes both sections
  from one value so a camera has one viewing account rather than two that
  drift. This credential does **not** open the configuration API.

Both are unset in a fresh image: media is served without authentication until
you set it, and the configuration API is protected by whatever the root
password is. **Change the root password.** The stock image ships the hash
published in OpenIPC's repository.

## Licence and credit

This build tree is MIT, inherited from upstream OpenIPC. **Raptor itself is
GPL-3.0** -- all four of its repositories are -- so an image built here mixes
the two, and the Raptor daemons carry GPLv3 obligations that the rest of the
tree does not.

OpenIPC is the reason any of this boots at all: kernel, bootloader, vendor
packaging and the Buildroot tree are theirs. See the [project][project], the
[website][website] and the [wiki][wiki], and consider supporting them at
[Open Collective][opencollective].

[nightly]: https://github.com/johnchia/firmware/releases/tag/raptor-nightly
[t-377]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc377qe-nor-raptor-latest.tgz
[t-377d]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc377d-nor-raptor-latest.tgz
[t-30k]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc30kq-nor-raptor-latest.tgz
[t-333]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc333_sc3336-nor-raptor-latest.tgz
[t-t31]: https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.t31_gc2053-nor-raptor-latest.tgz
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
