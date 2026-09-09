# Finding the radio: `/etc/wireless/detect`

How a camera decides which WiFi driver to load, why detection exists, and — more
important — the cases it deliberately refuses to handle.

Read this before changing `general/overlay/etc/wireless/usb`,
`general/overlay/etc/wireless/sdio`, `general/overlay/etc/wireless/detect` or the
`wlandev` handling in `general/overlay/etc/init.d/S40network`. All four are in the shared
overlay, so they reach every camera the tree builds.

## The problem

A camera with a USB or SDIO radio has to be told which driver to load. `wlandev` in the
U-Boot environment names an *arm* — a labelled bring-up sequence in `/etc/wireless/usb`
or `/etc/wireless/sdio` — and `S40network` reads it at boot:

```sh
dev=$(fw_printenv -n wlandev)
```

That is exactly right for the arms that carry board knowledge. Of the 39 board-specific
arms in `usb`, 36 release VBUS with a GPIO or a register write before the `modprobe`;
3 of the 9 in `sdio` do the same. Which pin, and which polarity, is a fact about a
circuit board. Nothing can discover it.

It is pure friction for the *generic* arms — 7 in `usb`, 3 in `sdio` — which carry no
wiring at all. There, `wlandev` is a string somebody has to know, and the only thing
standing between a working dongle and a working camera was knowing it.

Getting it wrong is not a soft failure. `S40network` read an unset `wlandev` as "this
board has no radio" and fell through to `ifup eth0`. On a board whose EMAC has no socket
wired to it — `ssc333_sc3336_raptor` is one, the Wyze v3 has no PHY at all — that is a
camera with no network and no way to reach it.

## What detection does

`S40network` consults `detect` only when `wlandev` is unset:

```sh
[ -n "$dev" ] || dev=$(/etc/wireless/detect)
```

**An explicit `wlandev` always wins and never reaches detection.** That is the property
that makes this safe to put in a shared overlay: no configured board can be
second-guessed, so the 48 board-specific arms are untouched by design, not by luck.

`detect` walks the generic arms of both helpers and, for each one:

1. Asks whether this image even carries the module (`modprobe -l`, below). If not, skip —
   nothing is loaded.
2. Runs the arm, which loads the driver.
3. Waits up to 3 s (30 × 100 ms) for a `wlan*` interface to appear.
4. If one does, prints the arm name and exits 0.
5. If none does, `rmmod`s the driver and moves on.

USB is walked before SDIO because probing USB costs nothing, whereas an SDIO arm tells
the MMC controller to rescan and the ATBM arms stage two calibration files — they touch
the machine whether or not a card is fitted.

## Why there is no USB/SDIO id table

The obvious design maps a USB vendor/product id to a driver. It is the wrong one. Every
driver already ships that table, and a copy in the overlay would be wrong the first time
any driver gained a device — silently, on cameras nobody can reach.

So the test used instead is the only one that cannot go stale: **load what this image
carries, and see whether an interface appears.** The kernel's own matching decides. A new
dongle that its driver already supports simply works, with no change here.

This has a pleasant consequence. Images carry zero or one WiFi driver in practice, so the
probe usually degenerates to "load the one you have, keep it if it binds" — the same cost
as the old unconditional `modprobe`, plus the wait.

### `modprobe -l` is the cheap half

`modprobe -l <mod>` prints the module's path if the image has it and nothing if it does
not. **Its exit status is 0 either way**, so the output is the test, not the status:

```sh
[ -n "$(modprobe -l "$mod")" ] || continue
```

This is what keeps detection free on the overwhelming majority of cameras, which ship no
WiFi driver at all: they walk both tables and load nothing.

It requires busybox's full `modprobe`. `general/package/busybox/busybox.config` has
`# CONFIG_MODPROBE_SMALL is not set`, and the applet was confirmed present on hi3516cv608,
t31 and ssc333 builds. A board that ever switches to `MODPROBE_SMALL` loses `-l`, and
detection would silently find nothing — it would not misbehave, but it would stop working.

## The two helpers are shaped differently, on purpose

`/etc/wireless/usb` — a generic arm is *only* a module plus its parameters, so the seven
of them are a table, and the table is the implementation:

```
GENERIC_ARMS="mt7601u-generic mt7601u
rtl8188eu-generic 8188eu
rtl8733bu-generic 8733bu rtw_power_mgnt=0 rtw_ips_mode=0
..."
```

`/etc/wireless/sdio` — an SDIO arm is not a pure `modprobe`. The card sits on a bus that
does not hotplug, so the controller must be told to look again, and the ATBM arms copy
two calibration files into `/tmp` first. Its branches therefore stay, and the table beside
them is only a **manifest** naming the arms and their modules.

That split creates a drift risk the USB side does not have: the manifest could name a
module the branch no longer loads. `.github/scripts/test_wireless_detect.sh` closes it by
running every arm named in the manifest and asserting it loads the module claimed for it.
Do not add an SDIO arm to one without the other; the test is a merge gate.

Both helpers answer `--list-generic` and `--module <arm>`, and both reject a
board-specific arm from `--module`.

## Two contracts that are easy to break

**`detect`'s stdout is its answer.** `S40network` reads it as the arm name, so anything an
arm prints must not reach it:

```sh
$helper "$arm" >/dev/null 2>&1 || continue
```

This is not defensive tidiness. The ATBM arms `cp` two files into place; one `cp` that
complained would have been spliced into the returned string and handed to
`/etc/wireless/sdio` as an arm name. The test deliberately keeps a *noisy* `cp` stub so
the redirection stays proven rather than assumed.

**Driver parameters are not cosmetic.** `rtw_power_mgnt=0 rtw_ips_mode=0` keeps the
Realtek radios awake — with the driver defaults a cv608 dropped 5% of pings outright and
stretched the rest to 60 ms against 0.6 ms on the wire. `rtw_ht_enable=0 rtw_led_enable=0`
belong to the 8812au, `atbm_printk_mask=0` stops the ATBM driver logging every frame. The
test pins each generic arm to its exact `modprobe` line for this reason.

## What detection cannot do, and must not be asked to

**A part has to be findable before anything can find it.** The 36 power-gated USB arms and
the 3 power-gated SDIO arms release power *first*; until that happens there is nothing on
the bus. Those stay configured. This is a property of the hardware, not a gap to close.

**A generic arm is not a substitute for a board arm that happens to bind.** Five of the
nine SDIO board-specific arms differ from the generic one only by driver parameters
(`rtw_power_mgnt=0 rtw_enusbss=0`) rather than by a GPIO. Detection would still find those
cards — but with the generic arm, and therefore without those parameters. Prefer the
configured arm; detection is the fallback for boards that configure nothing.

**Boards that bake their environment never reach detection at all.** Only three defconfigs
build a U-Boot environment into the image (`grep -l ENVIMAGE_SOURCE br-ext-chip-*/configs/*`):

| defconfig | env source | `wlandev` |
| --- | --- | --- |
| `t31_raptor` | `board/t31/wyze-v3.env.txt` | `atbm603x-t31-wyze-v3` |
| `hi3516cv608_os04d10_raptor` | `board/hi3516cv6xx/hi3516cv608.env.txt` | no `wlandev` line (wired build) |
| `hi3516cv608_os04d10_raptorwifi` | same | no `wlandev` line — detection finds it |

Every other board's `wlandev` is set by hand, which is what detection removes. On
`t31_raptor` it is baked, so `detect` never runs — and could not substitute if it did,
because that arm opens by power-cycling the radio on GPIO 57. Note where the two halves
live: **the environment names the arm; the arm knows the pin.** Neither half is derivable
from the other.

## Cost

`detect` is 461 bytes once `general/scripts/strip-shell-comments.awk` has run over it,
plus a small table in each helper. On squashfs that rounded to one 4 KB block on the
cv608.

At runtime, on a camera with no WiFi driver: a handful of `modprobe -l` calls and nothing
else. On a camera with a driver and no radio fitted: one load, the 3 s wait, one `rmmod` —
and the memory comes back, which the old unconditional `modprobe` never did (8733bu alone
is 1276 KB resident).

## Evidence

Measured, not estimated:

| board | cold `detect` | boot with `wlandev` empty |
| --- | --- | --- |
| cv608 (`hi3516cv608_os04d10_raptorwifi`, RTL8733BU/USB) | 0.76 s | wlan0 addressed at 19.56 s uptime |
| ssc333 (`ssc333_sc3336_raptor`, RTL8188FU/USB) | 0.62 s | DHCP lease at 13.17 s uptime |

On the cv608 the `dmesg` order confirms the mechanism: the USB device enumerates, *then*
`detect` loads `8733bu` onto it and `usbcore` registers the interface driver. The 3 s
budget has roughly 4× headroom over the worst observed bind.

**The SDIO path has never been run on hardware.** The only SDIO camera on the bench is the
Wyze v3, and its baked environment makes it precisely the board detection never runs on.
That half is covered by `test_wireless_detect.sh` against stubs only. The boards it would
actually serve — `v851s_lite`, `t31_ultimate`, `t20_ultimate`, `hi3518ev300_ultimate` and
the two `ssc33x_ultimate` targets — carry an SDIO driver and bake no environment, and none
of them has been tested here.

`t31_ultimate` is also the tree's only two-driver image (ATBM60XX SDIO *and* RTL8189FS).
The manifest order makes the outcome deterministic, but it is untested.

`SSW101B` has no arm in `/etc/wireless/sdio` at all, so the two `ssc33x_ultimate` targets
that select it are brought up some other way. Unexamined.

## Changing this

Run `bash .github/scripts/test_wireless_detect.sh` — 33 assertions, no device, no build.
It runs in CI as the `wireless-detect` job in `.github/workflows/shell-tests.yml`.

- Adding a generic USB arm: one line in `GENERIC_ARMS` in `usb`, one `check_generic` line
  in the test, and update the `--list-generic` assertion.
- Adding a generic SDIO arm: a branch *and* a manifest line in `sdio`, plus the same two
  test edits. The manifest-agreement check will fail if you do only one.
- Adding a board-specific arm: a branch, nothing else. Part 2 of the test will pick it up
  automatically and assert it still dispatches.
- Changing driver parameters: change the test's expected `modprobe` line in the same
  commit, and say in the commit message what the parameter buys.

Anything here can take a camera off the network permanently, and on a radio-only board
there is no second way in. See `best_practices.md` §1 on blast radius.
