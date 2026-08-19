# raptor-streaming

The Buildroot package that builds Raptor and installs it as the streamer.

## Where the source comes from

Raptor is developed as four sibling repositories, and its top-level Makefile
reaches the others through relative paths, so the tree this package builds is
the parent directory holding all four:

```
<build dir>
├── raptor          # the daemons
├── raptor-hal      # SoC backends (sigmastar-headers is a submodule of this)
├── raptor-common   # librss_common.so
└── raptor-ipc      # librss_ipc.so
```

Each is pinned by commit in `raptor-streaming.mk`, along with a fifth pin for
`sigmastar-headers` — GitHub's source archives omit submodule contents, so the
headers have to be fetched separately and moved into place. The pins are the
only source; to build a change, push it and move the pin.

A developer checkout normally has `compy` alongside these too, but this package
does not use it from there — compy comes from the `compy` Buildroot package, so
the image never links a `build-arm/libcompy.a` that only exists because someone
built it by hand.

> `$(@D)` is named after the **raptor** pin alone. Moving the HAL, common, IPC
> or headers pin does not change it, and the already-extracted build directory
> keeps the sibling sources the previous pins unpacked. Run
> `make BOARD=<board> br-raptor-streaming-dirclean` first whenever any pin other
> than raptor's moves.

## What is in the image

Daemons, started in dependency order by `/etc/init.d/S95raptor`:

| daemon | role |
| --- | --- |
| `rvd` | video; owns the HAL and creates the SHM rings, so it starts first |
| `rsd` | RTSP |
| `rad` | audio |
| `rod` | OSD text rendering |
| `ric` | IR-cut day/night; exits immediately while `[ircut] enabled = false` |
| `rhd` | HTTP: snapshots, MJPEG, audio, and the configuration console |
| `rcd` | owns `/etc/raptor.conf`; the other daemons are its clients |
| `rmq` | MQTT bridge with Home Assistant discovery |

plus `raptorctl` for runtime control, `librss_common.so`, `librss_ipc.so`, and
`/etc/raptor.conf` (the board file from the Raptor tree, comments included).

The console page is installed from `raptor/rhd/console.html` to
`/usr/share/raptor/index.html`, which is the path `rhd` reads at runtime.

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

- `rtsp://CAMERA_IP:554/stream0` — the main stream, overlays on
- `rtsp://CAMERA_IP:554/stream1` — the sub stream, overlays deliberately
  **off**, so that a region appearing on one stream and not the other confirms
  per-port attach
