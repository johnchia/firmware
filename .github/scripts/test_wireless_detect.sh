#!/bin/sh
# Regression test for the generic-arm tables in /etc/wireless/usb and
# /etc/wireless/sdio, and the radio detection that reads them.
#
# The seven generic arms used to be seven near-identical `if` blocks. They are
# now one table, because /etc/wireless/detect has to enumerate them: it loads
# each module this image carries and keeps whichever one binds a device, which
# is the only way to find a dongle without shipping a USB id table that would
# go stale the first time a driver gained a device.
#
# What that collapse risks is an arm quietly changing or disappearing. A board
# whose wlandev names it then boots with no radio at all, and nothing in the
# build says so -- the arm is a string in a flash environment, matched at run
# time. So Part 1 pins every generic arm to the exact modprobe line it must
# produce, and Part 2 pins every board-specific arm's existence.
#
# /etc/wireless/sdio keeps its branches -- an SDIO arm has to rescan the MMC
# controller, and the ATBM ones stage calibration files, so it is not a pure
# modprobe -- and carries the arm list as a manifest beside them. Part 1 is
# what stops the two drifting: it runs each arm and checks it loads the module
# the manifest claims for it.
#
# Part 3 covers detect's own contract, which matters most on the boards that
# have no radio: it must load nothing at all on an image with no wifi driver
# in it, and must unload again when a driver loads but nothing binds.
#
# Pure shell, no device, no build. Run from the repository root.

set -eu

fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
T()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 -- want '$1', got '$2'"; fi; }

USB=general/overlay/etc/wireless/usb
DETECT=general/overlay/etc/wireless/detect
[ -r "$USB" ] || { echo "run me from the repository root"; exit 1; }

SH=sh
command -v busybox >/dev/null 2>&1 && SH="busybox ash"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/bin" "$tmp/net"

# Stub everything an arm can reach, so running one is inert and observable.
for t in modprobe gpio devmem sleep cp; do
	printf '#!/bin/sh\necho "%s $*"\n' "$t" > "$tmp/bin/$t"
done
chmod +x "$tmp/bin"/*

SDIO=general/overlay/etc/wireless/sdio

# stdout only: set_mmc cats a sysfs path that does not exist off-device, and
# its complaint is not the subject of any check here.
arm() { local h=$1; shift; PATH="$tmp/bin:$PATH" $SH "$h" "$@" 2>/dev/null; }

echo "=== Part 1: every generic arm produces its exact modprobe line ==="
# The parameters are not cosmetic. rtw_power_mgnt/rtw_ips_mode keep the
# Realtek radios awake -- with the defaults a cv608 dropped 5% of pings and
# stretched the rest to 60 ms -- rtw_ht_enable/rtw_led_enable are the 8812au's,
# and atbm_printk_mask=0 stops the ATBM driver logging every frame. Losing them
# in an edit is silent until someone pings the camera.
check_generic() {  # <helper> <arm> <expected modprobe args>
	local h=$1 a=$2 want=$3
	T "modprobe $want" "$(arm "$h" "$a" | grep '^modprobe ' | head -1)" "$a -> modprobe $want"
	# The manifest's module and the one the arm actually loads must agree,
	# because detect reads the first and rmmods what the second left behind.
	T "$(echo "$want" | cut -d' ' -f1)" "$(arm "$h" --module "$a")" "$a --module agrees with the branch"
}
check_generic "$USB" mt7601u-generic      "mt7601u"
check_generic "$USB" rtl8188eu-generic    "8188eu"
check_generic "$USB" rtl8188fu-generic    "8188fu"
check_generic "$USB" rtl8733bu-generic    "8733bu rtw_power_mgnt=0 rtw_ips_mode=0"
check_generic "$USB" rtl8811cu-generic    "8821cu"
check_generic "$USB" rtl8812au-generic    "88XXau rtw_ht_enable=0 rtw_led_enable=0"
check_generic "$USB" atbm603x-generic-usb "atbm603x_wifi_usb"
check_generic "$SDIO" atbm603x-generic    "atbm603x_wifi_sdio atbm_printk_mask=0"
check_generic "$SDIO" rtl8189fs-generic   "8189fs"
check_generic "$SDIO" xr829-generic       "xradio_wlan"

T "mt7601u-generic rtl8188eu-generic rtl8188fu-generic rtl8733bu-generic rtl8811cu-generic rtl8812au-generic atbm603x-generic-usb" \
  "$(arm "$USB" --list-generic | tr '\n' ' ' | sed 's/ $//')" \
  "usb --list-generic lists exactly the table, in table order"
T "atbm603x-generic rtl8189fs-generic xr829-generic" \
  "$(arm "$SDIO" --list-generic | tr '\n' ' ' | sed 's/ $//')" \
  "sdio --list-generic lists exactly the manifest, in manifest order"

echo "=== Part 2: no arm has gone missing ==="
# Board-specific arms cannot be table-driven -- each releases power with its own
# GPIO or register write -- so they stay as branches, and this only checks that
# each name still resolves. An unknown arm must exit 1, or S40network would
# take the wireless path on a board that has no radio.
missing=0
for h in "$USB" "$SDIO"; do
	for a in $(grep -oE '"\$1" = "[^"]+"' "$h" | sed 's/.*= "//;s/"//'); do
		PATH="$tmp/bin:$PATH" $SH "$h" "$a" >/dev/null 2>&1 || { bad "arm $a no longer dispatches"; missing=1; }
	done
	PATH="$tmp/bin:$PATH" $SH "$h" no-such-radio >/dev/null 2>&1 && bad "$h: unknown arm exits 0" || ok "$(basename "$h"): unknown arm exits 1"
done
[ "$missing" = 0 ] && ok "every board-specific arm still dispatches"
PATH="$tmp/bin:$PATH" $SH "$USB" --module rtl8733bu-gk7205v200-camhi >/dev/null 2>&1 \
	&& bad "--module answered for a board-specific arm" \
	|| ok "--module answers for generic arms only"
PATH="$tmp/bin:$PATH" $SH "$SDIO" --module atbm603x-t31-wyze-v3 >/dev/null 2>&1 \
	&& bad "sdio --module answered for a board-specific arm" \
	|| ok "sdio --module answers for generic arms only"

echo "=== Part 3: detect loads nothing it does not have, and unloads what does not bind ==="
# detect is redirected at a fake sysfs and a fake usb, because the paths it
# uses are absolute on the camera. The logic under test is unmodified.
sed -e "s#/etc/wireless/usb /etc/wireless/sdio#$tmp/usb $tmp/sdio#" \
    -e "s#/sys/class/net/#$tmp/net/#" "$DETECT" > "$tmp/detect"
cp "$USB" "$tmp/usb"; cp "$SDIO" "$tmp/sdio"
cat > "$tmp/bin/modprobe" <<'STUB'
#!/bin/sh
if [ "$1" = "-l" ]; then [ -n "${HAVE:-}" ] && [ "$2" = "$HAVE" ] && echo "extra/$2.ko"; exit 0; fi
echo "LOAD $*" >> "$LOG"
[ -n "${BINDS:-}" ] && touch "$NETDIR/wlan0"
exit 0
STUB
printf '#!/bin/sh\necho "RMMOD $*" >> "$LOG"\n' > "$tmp/bin/rmmod"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/usleep"
chmod +x "$tmp/bin"/*

run_detect() {  # HAVE= BINDS= -> "<arm>|<actions>"
	: > "$tmp/log"; rm -f "$tmp/net/wlan0"
	out=$(LOG=$tmp/log NETDIR=$tmp/net HAVE=$1 BINDS=$2 PATH="$tmp/bin:$PATH" $SH "$tmp/detect" 2>/dev/null || true)
	echo "$out|$(tr '\n' ';' < "$tmp/log")"
}

# The case that covers nearly every camera in the tree: no wifi driver in the
# image. Detection must be inert -- not one modprobe, and no answer, so
# S40network falls through to the wire exactly as it did before.
T "|" "$(run_detect '' '')" "image with no wifi driver: nothing loaded, no answer"

T "rtl8733bu-generic|LOAD 8733bu rtw_power_mgnt=0 rtw_ips_mode=0;" \
  "$(run_detect 8733bu 1)" "driver present and dongle binds: arm returned"

T "|LOAD 8733bu rtw_power_mgnt=0 rtw_ips_mode=0;RMMOD 8733bu;" \
  "$(run_detect 8733bu '')" "driver present, nothing binds: module unloaded, no answer"

# Arms are skipped on absence, not tried and failed, so a driver late in the
# table is still found without loading the ones before it.
T "rtl8812au-generic|LOAD 88XXau rtw_ht_enable=0 rtw_led_enable=0;" \
  "$(run_detect 88XXau 1)" "only the module the image carries is loaded"

# SDIO is reached only after the whole USB table has been walked and skipped,
# which is what keeps a USB-only camera from ever rescanning an MMC controller.
T "atbm603x-generic|LOAD atbm603x_wifi_sdio atbm_printk_mask=0;" \
  "$(run_detect atbm603x_wifi_sdio 1)" "an SDIO part is found after the USB table"

T "|LOAD atbm603x_wifi_sdio atbm_printk_mask=0;RMMOD atbm603x_wifi_sdio;" \
  "$(run_detect atbm603x_wifi_sdio '')" "SDIO driver present, nothing binds: unloaded, no answer"

echo
if [ "$fail" -eq 0 ]; then
	echo "All wireless detect checks passed."
else
	echo "$fail check(s) failed."
	exit 1
fi
