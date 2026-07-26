# ssc30kq Raptor image

`ssc30kq_raptor` is a Majestic-free, Divinus-free image in which Raptor owns the
camera. It exists so the SigmaStar Infinity6E backend can be soaked on its own
platform instead of being hand-staged onto another streamer's rootfs.

## Building

Raptor has no download site. It is developed as sibling repositories and its
SigmaStar backend is on unpushed branches, so a local checkout is currently the
only source. `RAPTOR_SRCDIR` is the **parent** directory holding them:

```
~/raptor
├── raptor          # the daemons
├── raptor-hal      # SoC backends (INFINITY6E lives here)
├── raptor-common   # librss_common.so
└── raptor-ipc      # librss_ipc.so
```

A developer checkout normally has `compy` alongside these too, but this package
does not use it from there — compy comes from the `compy` Buildroot package, so
the image never links a `build-arm/libcompy.a` that only exists because someone
built it by hand.

```sh
make BOARD=ssc30kq_raptor RAPTOR_SRCDIR=~/raptor
```

To iterate on the daemons without rebuilding the image, re-sync and rebuild just
this package:

```sh
make BOARD=ssc30kq_raptor RAPTOR_SRCDIR=~/raptor raptor-local
```

Forgetting `RAPTOR_SRCDIR` fails with an explanation rather than a missing-path
error.

## What is in the image

Five daemons, started in dependency order by `/etc/init.d/S95raptor`:

| daemon | role |
| --- | --- |
| `rvd` | video; owns the HAL and creates the SHM rings, so it starts first |
| `rsd` | RTSP |
| `rad` | audio |
| `rod` | OSD text rendering |
| `ric` | IR-cut day/night; exits immediately while `[ircut] enabled = false` |

plus `raptorctl` for runtime control, `librss_common.so`, `librss_ipc.so`, and
`/etc/raptor.conf` (the board file from the Raptor tree, comments included).

The vendor MI libraries are **not** installed by this package. The OSDRV package
installs its full bundle whenever Majestic is not selected, which is the case
here, and the HAL dlopens them from there.

## OSD needs rod

Worth knowing before debugging a blank overlay: `rvd` does not render text. It
discovers `/dev/shm/rss_osd_osd_<stream>_<name>` objects and uploads whatever
bitmap it finds to MI_RGN. `rod` is what reads the `[osd.*]` config sections,
expands templates like `%time%`, and rasterises glyphs with libschrift. With rod
absent or its font missing, rvd logs `0 regions created` and the picture is
clean no matter how the `[osd.*]` sections are written.

That font is why this package selects `majestic-fonts`: rod's built-in default
path (`/usr/share/fonts/default.ttf`) does not exist on OpenIPC, and a missing
font is fatal to rod. `/etc/raptor.conf` points at the UbuntuMono file that
package installs.

## Checking a running board

```sh
logread | grep -E 'rvd|rsd|rad|rod'   # the daemons log to syslog
/etc/init.d/S95raptor stop            # then run one in the foreground:
rvd -f -d -c /etc/raptor.conf
```

- `rtsp://CAMERA_IP:554/stream0` — 2560x1440 H.264 at 30 fps, overlays on
- `rtsp://CAMERA_IP:554/stream1` — 640x360 at 5 fps, overlays deliberately
  **off**, so that a region appearing on one stream and not the other confirms
  per-port attach
