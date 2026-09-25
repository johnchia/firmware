#!/bin/bash
# Behaviour tests for sysupgrade-raptor, the updater raptor images ship.
#
# The property under test is the one the script exists for: nothing reaches the
# flash until every check has passed, and once the first write starts the run
# ends in a reboot. Every refusal case asserts that NOTHING WAS WRITTEN and that
# the services stopped for the run were started again; every success case
# asserts the write order and that the payload was deleted as it was consumed.
#
# Pure shell against a sandbox: the absolute paths the script hardcodes are
# rewritten under $SB, and everything that would touch hardware is a stub on
# PATH that records its argv. Runs in a few seconds, needs no root.
set -u

SRC=${SRC:-general/package/raptor-streaming/files/sysupgrade-raptor}
SH=${SH:-sh}
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }

[ -f "$SRC" ] || { echo "FAIL cannot find $SRC -- run me from the repo root"; exit 1; }
for t in od stat md5sum tar gzip awk; do
	command -v "$t" >/dev/null 2>&1 || { echo "FAIL required tool '$t' is missing"; exit 1; }
done

# --- sandbox ---------------------------------------------------------------
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp" "$SB/proc/sys/vm" "$SB/etc/init.d" "$SB/bin" "$SB/lib" "$SB/src"

# $SB itself lives under /tmp, so /tmp is staged through a sentinel: a plain
# s|/tmp|$SB/tmp| would rewrite the paths the earlier rules just produced.
sed -e 's|/tmp\b|@SB@/tmp|g' \
    -e 's|/etc/os-release|@SB@/etc/os-release|g' \
    -e 's|/etc/init.d/|@SB@/etc/init.d/|g' \
    -e 's|/proc/mtd|@SB@/proc/mtd|g' \
    -e 's|/sys/class/mtd/|@SB@/sys/class/mtd/|g' \
    -e 's|/proc/cmdline|@SB@/proc/cmdline|g' \
    -e 's|/proc/meminfo|@SB@/proc/meminfo|g' \
    -e 's|/proc/mounts|@SB@/proc/mounts|g' \
    -e 's|/proc/sys/vm/drop_caches|@SB@/proc/sys/vm/drop_caches|g' \
    -e 's|cp /bin/busybox |cp @SB@/bin/busybox |' \
    -e 's|ldd /bin/busybox|ldd @SB@/bin/busybox|' \
    -e 's|/lib/ld-\*|@SB@/lib/ld-*|g' \
    -e 's|/lib/libc.so\*|@SB@/lib/libc.so*|g' \
    -e 's|^\tPATH=/bin$|\tPATH=@SB@/bin:$PATH|' \
    -e "s|@SB@|$SB|g" \
    "$SRC" > "$SB/sysupgrade-raptor"
chmod +x "$SB/sysupgrade-raptor"
grep -q '@SB@' "$SB/sysupgrade-raptor" && { echo "FAIL sandbox rewrite left a sentinel"; exit 1; }
grep -q "PATH=$SB/bin" "$SB/sysupgrade-raptor" || { echo "FAIL PATH rewrite for phase 2 did not match"; exit 1; }

# The mini-root sources.
printf '#!/bin/bash\nexit 0\n' > "$SB/bin/busybox"; chmod +x "$SB/bin/busybox"
printf 'ld\n' > "$SB/lib/ld-musl-test.so.1"
printf 'libc\n' > "$SB/lib/libc.so"

for s in S95raptor S60crond S49ntpd S02klogd S02fakehwclock S01syslogd; do
	printf '#!/bin/bash\necho "%s $1" >> "$FLASH_LOG"\nexit 0\n' "$s" > "$SB/etc/init.d/$s"
	chmod +x "$SB/etc/init.d/$s"
done

set_osrel() { printf 'BUILD_PLATFORM=ssc333_raptor\nBUILD_OPTION=raptor\nBUILD_SENSOR=%s\nBUILD_CAMERA=%s\n' "${1:-}" "${2:-}" > "$SB/etc/os-release"; }
set_osrel

set_mtd() { cat > "$SB/proc/mtd"; }
set_mtd <<'EOF'
dev:    size   erasesize  name
mtd0: 00040000 00010000 "boot"
mtd1: 00010000 00010000 "env"
mtd2: 00200000 00010000 "kernel"
mtd3: 00510000 00010000 "rootfs"
mtd4: 000a0000 00010000 "rootfs_data"
EOF
set_mem() { printf 'MemTotal: 39048 kB\nMemFree: 5000 kB\nBuffers: 0 kB\nCached: 8000 kB\nMemAvailable: %s kB\n' "$1" > "$SB/proc/meminfo"; }
set_mem 20000
# The overlay as general/overlay/init mounts it: the jffs2 partition, and the
# root overlay whose upperdir the dev wipe reads back out of this line. Two
# flavours: "overlay" with a workdir (upperdir=/overlay/root), and the older
# "overlayfs" of the 3.10 t31 kernel, where the whole partition is the upper.
UP="$SB/overlay/root"
set_mounts() {
	case "${1:-overlay}" in
		overlay)   printf '/dev/mtdblock4 /overlay jffs2 rw,relatime 0 0\noverlay / overlay rw,relatime,lowerdir=/,upperdir=%s,workdir=%s/overlay/work 0 0\n' "$UP" "$SB" ;;
		overlayfs) printf '/dev/mtdblock4 /overlay jffs2 rw,relatime 0 0\noverlayfs / overlayfs rw,relatime,lowerdir=/,upperdir=%s 0 0\n' "$UP" ;;
		none)      printf '/dev/mtdblock4 /overlay jffs2 rw,relatime 0 0\n' ;;
	esac > "$SB/proc/mounts"
}
set_mounts
# What a development session leaves in the upper directory.
set_upper() {
	rm -rf "$UP"; mkdir -p "$UP/etc" "$UP/var/lib" "$UP/usr/bin" "$UP/root"
	echo conf > "$UP/etc/raptor.conf"; echo seed > "$UP/var/lib/seed"
	echo stale > "$UP/usr/bin/rvd"; echo hist > "$UP/root/.ash_history"; : > "$UP/crond.reboot"
}
upper_cleaned() { [ -f "$UP/etc/raptor.conf" ] && [ -f "$UP/var/lib/seed" ] && [ ! -e "$UP/usr" ] && [ ! -e "$UP/root" ] && [ ! -e "$UP/crond.reboot" ]; }
upper_intact()  { [ -f "$UP/usr/bin/rvd" ] && [ -f "$UP/root/.ash_history" ]; }

# --- stubs -----------------------------------------------------------------
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$SB/bin/$1"; chmod +x "$SB/bin/$1"; }
log_stub() { stub "$1" "echo \"$1 \$*\" >> \"\$FLASH_LOG\"; exit \${STUB_${1^^}_RC:-0}"; }

log_stub flashcp
log_stub flash_eraseall
log_stub fw_setenv
log_stub killall
log_stub reboot
stub id      'echo 0'
stub sync    'exit 0'
stub sleep   'exit 0'
stub ldd     'echo "	libc.so => '"$SB"'/lib/libc.so (0x0)"'
# bind mounts succeed silently; the read-only remount of the overlay is logged
# so a test can assert it happened, and happened before the erase.
stub mount   'case "$*" in *remount*) echo "remount $*" >> "$FLASH_LOG";; *bind*) echo "bind ${@: -1}" >> "$FLASH_LOG";; esac; exit 0'
log_stub umount
# The handover. A preflight (`-c :`) answers STUB_CHROOT_RC; the real entry runs
# the copy the script placed in its RAM root, with SU_PHASE=2 already exported.
stub chroot  'root=$1; shift
case "$*" in
	*" -c :") exit "${STUB_CHROOT_RC:-0}" ;;
esac
echo "chroot $root" >> "$FLASH_LOG"
exec sh "$root/sysupgrade-raptor"'
# --url: whatever is at STUB_CURL_FILE is "downloaded"; the URL asked for is
# logged so --github's composition can be asserted.
stub curl    'echo "curl ${@: -1}" >> "$FLASH_LOG"; cat "$STUB_CURL_FILE"'

# The shell under test is resolved before the stubs go on PATH: the sandbox
# carries a dummy `busybox`, and SH="busybox sh" must not find that one.
set -- $SH
SH_BIN=$(command -v "$1") || { echo "FAIL shell '$1' not found"; exit 1; }
shift; SH="$SH_BIN $*"
export PATH="$SB/bin:$PATH"

# --- fixtures --------------------------------------------------------------
make_uimage() { { printf '\x27\x05\x19\x56'; head -c 60 /dev/zero; } > "$1"; }
make_fit()    { { printf '\xd0\x0d\xfe\xed'; head -c 60 /dev/zero; } > "$1"; }
# A squashfs superblock whose bytes_used (little-endian u64 at 0x28) is the
# fixture's own size, as mksquashfs writes it; the file is 4 + $2 bytes.
make_rootfs() {
	local total=$((4 + ${2:-8188})) v=$((4 + ${2:-8188})) le= i
	for i in 1 2 3 4 5 6 7 8; do
		le="$le\\x$(printf '%02x' $((v & 255)))"; v=$((v >> 8))
	done
	{ printf 'hsqs'; head -c 36 /dev/zero; printf "$le"; head -c $((total - 48)) /dev/zero; } > "$1"
}

# Archive members named as the build names them, with an .md5sum beside each.
make_archive() {
	local out=$1 stage="$SB/stage"
	rm -rf "$stage"; mkdir -p "$stage"
	[ -n "${NO_KERNEL:-}" ] || make_uimage "$stage/uImage.ssc333"
	[ -n "${NO_ROOTFS:-}" ] || make_rootfs "$stage/rootfs.squashfs.ssc333" "${ROOTFS_BYTES:-8188}"
	# A build that packed a short rootfs: cut before the checksums are taken,
	# so the .md5sum matches the short file and only the superblock tells.
	if [ -n "${TRUNCATE_ROOTFS:-}" ]; then
		head -c "$TRUNCATE_ROOTFS" "$stage/rootfs.squashfs.ssc333" > "$stage/short" && mv "$stage/short" "$stage/rootfs.squashfs.ssc333"
	fi
	(cd "$stage" && for f in uImage.ssc333 rootfs.squashfs.ssc333; do
		[ -f "$f" ] && md5sum "$f" > "$f.md5sum"
	done)
	[ -n "${CORRUPT_MD5:-}" ] && (cd "$stage" && echo "00000000000000000000000000000000  rootfs.squashfs.ssc333" > rootfs.squashfs.ssc333.md5sum)
	[ -n "${NO_MD5:-}" ] && rm -f "$stage"/*.md5sum
	(cd "$stage" && tar cf - . | gzip > "$out")
}

# --- run helper ------------------------------------------------------------
# Every run starts from a clean /tmp and log. Output is kept for the failure
# message; the assertions read the log the stubs wrote.
run() {
	rm -rf "$SB/tmp"; mkdir -p "$SB/tmp"
	# PLACE puts a file into the fresh /tmp for the run that wants it there.
	[ -n "${PLACE:-}" ] && cp "$PLACE" "$SB/tmp/"
	export FLASH_LOG="$SB/flash.log"; : > "$FLASH_LOG"
	OUT=$($SH "$SB/sysupgrade-raptor" "$@" 2>&1); RC=$?
}
wrote()      { grep -q "^flashcp \|^flash_eraseall " "$FLASH_LOG"; }
# Either the services were never stopped (a refusal in argument handling) or
# every one that was stopped was started again.
restored()   { ! grep -q "^S95raptor stop" "$FLASH_LOG" || grep -q "^S95raptor start" "$FLASH_LOG"; }
lock_gone()  { [ ! -d "$SB/tmp/sysupgrade.lock" ]; }
log_order() {
	# The listed patterns must appear in this order among the log lines.
	local prev=0 n p
	for p in "$@"; do
		n=$(grep -n "$p" "$FLASH_LOG" | head -1 | cut -d: -f1)
		[ -n "$n" ] && [ "$n" -gt "$prev" ] || return 1
		prev=$n
	done
}
refused() {
	# $1 test name; the rest is a grep pattern the output must carry.
	local name=$1; shift
	if [ "$RC" -ne 0 ] && ! wrote && restored && lock_gone && echo "$OUT" | grep -q "$*"; then
		ok "$name"
	else
		bad "$name (rc=$RC)"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
	fi
}

# --- tests -----------------------------------------------------------------
echo "# archive"

make_archive "$SB/fw.tgz"
PLACE="$SB/fw.tgz" run --archive="$SB/tmp/fw.tgz"
if log_order "^S95raptor stop" "^fw_setenv upgrade_available 1" "^fw_setenv bootcount 0" \
		"^chroot " "^flashcp $SB/tmp/sysupgrade.pkg/uImage.ssc333 /dev/mtd2" \
		"^flashcp $SB/tmp/sysupgrade.pkg/rootfs.squashfs.ssc333 /dev/mtd3" "^killall dropbear" "^reboot -f" \
	&& [ ! -f "$SB/tmp/fw.tgz" ] && [ ! -f "$SB/tmp/sysupgrade.pkg/uImage.ssc333" ] && [ ! -f "$SB/tmp/sysupgrade.pkg/rootfs.squashfs.ssc333" ] \
	&& ! grep -q "^flash_eraseall" "$FLASH_LOG"; then
	ok "archive in /tmp: stop, arm, kernel then rootfs, dropbear killed, reboot; archive and payload deleted"
	echo "$OUT" | grep -q "^SoC OK: the archive is built for ssc333" && ok "archive names carry the SoC check" || bad "no SoC line for the archive"
else
	bad "archive flash order"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi
grep -q "^flashcp" "$FLASH_LOG" && ! log_order "^flashcp" "^S01syslogd start" \
	&& ok "services are not restarted after the flash starts" \
	|| bad "services restarted after a flash"

run --archive="$SB/fw.tgz"
if log_order "^flashcp $SB/tmp/sysupgrade.pkg/uImage.ssc333" "^flashcp $SB/tmp/sysupgrade.pkg/rootfs" && [ -f "$SB/fw.tgz" ]; then
	ok "archive outside /tmp is kept"
else
	bad "archive outside /tmp"; sed 's/^/     log: /' "$FLASH_LOG"
fi

NO_ROOTFS=1 make_archive "$SB/nofs.tgz"
run --archive="$SB/nofs.tgz"
refused "archive without rootfs.squashfs.<soc> is refused before any write" "holds no uImage.ssc333 and rootfs"
[ ! -e "$SB/tmp/sysupgrade.pkg" ] && ok "a refused archive leaves nothing in /tmp" || { bad "refused archive left files"; ls -R "$SB/tmp" | sed 's/^/     /'; }

CORRUPT_MD5=1 make_archive "$SB/badmd5.tgz"
run --archive="$SB/badmd5.tgz"
refused "checksum mismatch is refused before any write" "checksum mismatch"
run -f --archive="$SB/badmd5.tgz"
log_order "^flashcp .*uImage" "^flashcp .*rootfs" && ok "-f flashes past a checksum mismatch" || bad "-f did not skip the checksum"

NO_MD5=1 make_archive "$SB/nomd5.tgz"
run --archive="$SB/nomd5.tgz"
refused "archive without .md5sum files is refused" "ships no .md5sum"

ROOTFS_BYTES=$((0x510000)) make_archive "$SB/big.tgz"
run --archive="$SB/big.tgz"
refused "rootfs larger than its partition is refused before any write" "larger than the rootfs partition"

TRUNCATE_ROOTFS=4096 make_archive "$SB/short.tgz"
run --archive="$SB/short.tgz"
refused "rootfs shorter than its superblock says is refused before any write, checksums notwithstanding" "superblock says 8192"
TRUNCATE_ROOTFS=4096 make_archive "$SB/short-f.tgz"
run -f --archive="$SB/short-f.tgz"
refused "...and -f does not waive it" "the image is truncated"

set_mem 2000
run --archive="$SB/fw.tgz"
refused "too little RAM to unpack is refused before unpacking" "need .* KB of RAM"
[ ! -e "$SB/tmp/sysupgrade.pkg" ] && ok "nothing was unpacked" || bad "unpacked despite the RAM check"
set_mem 20000

run --archive="$SB/missing.tgz"
refused "missing archive" "not found"

echo "# raw files"

make_uimage "$SB/src/k.bin"; make_rootfs "$SB/src/r.bin"
run --kernel="$SB/src/k.bin" --rootfs="$SB/src/r.bin"
if log_order "^flashcp $SB/tmp/sysupgrade.pkg/k.bin /dev/mtd2" "^flashcp $SB/tmp/sysupgrade.pkg/r.bin /dev/mtd3" "^reboot" \
	&& [ -f "$SB/src/k.bin" ] && [ ! -f "$SB/tmp/sysupgrade.pkg/k.bin" ]; then
	ok "--kernel/--rootfs outside /tmp are copied in, flashed, and the copies deleted"
	echo "$OUT" | grep -q "^Warning: SoC not verified" && ok "raw files warn that the SoC is not verified" || bad "no SoC warning on the raw path"
else
	bad "raw files"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

make_fit "$SB/src/fit.bin"
run --kernel="$SB/src/fit.bin"
log_order "^flashcp $SB/tmp/sysupgrade.pkg/fit.bin /dev/mtd2" "^reboot" && ! grep -q "mtd3" "$FLASH_LOG" \
	&& ok "a FIT kernel alone is accepted and only the kernel is written" || bad "FIT kernel"

printf 'not a kernel at all' > "$SB/src/junk.bin"
run --kernel="$SB/src/junk.bin" --rootfs="$SB/src/r.bin"
refused "kernel with the wrong magic is refused before any write" "neither a uImage nor a FIT"
run --rootfs="$SB/src/junk.bin"
refused "rootfs with the wrong magic is refused" "not a squashfs"
head -c 4096 "$SB/src/r.bin" > "$SB/src/short.bin"
run --kernel="$SB/src/k.bin" --rootfs="$SB/src/short.bin"
refused "a raw rootfs cut short is refused, and the kernel beside it is not written" "the image is truncated"

run --rootfs="$SB/src/r.bin" -x
refused "-x with a rootfs write is refused" "cannot be honoured"
grep -q "^S95raptor stop" "$FLASH_LOG" && bad "-x refusal stopped services first" || ok "-x refusal happens before services are touched"

run --archive="$SB/fw.tgz" --rootfs="$SB/src/r.bin"
refused "two sources are refused" "give one of"

echo "# overlay"

run -n
if log_order "^S95raptor stop" "^remount .*ro" "^flash_eraseall -j /dev/mtd4" "^killall dropbear" "^reboot -f" \
	&& ! grep -q "^chroot\|^flashcp" "$FLASH_LOG"; then
	ok "-n alone: overlay quiesced, erased from the live root, dropbear killed, reboot"
else
	bad "-n alone"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

run -n -x
if [ "$RC" -eq 0 ] && log_order "^flash_eraseall -j /dev/mtd4" "^S01syslogd start" \
	&& ! grep -q "^reboot" "$FLASH_LOG" && lock_gone; then
	ok "-n -x: overlay erased, no reboot, services and lock released"
else
	bad "-n -x"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

run --archive="$SB/fw.tgz" -n
log_order "^remount .*ro" "^chroot" "^flashcp .*uImage" "^flashcp .*rootfs" "^flash_eraseall -j /dev/mtd4" "^reboot" \
	&& ok "-n with an archive: erase follows the rootfs write, inside the RAM root" \
	|| { bad "-n with archive"; sed 's/^/     log: /' "$FLASH_LOG"; }

echo "# dev wipe"

set_upper
run -d -x
if [ "$RC" -eq 0 ] && upper_cleaned && ! wrote && ! grep -q "^reboot" "$FLASH_LOG" && restored && lock_gone; then
	ok "-d -x: everything but etc and var removed from the upper directory, no reboot, services back"
else
	bad "-d -x"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; ls -R "$UP" | sed 's/^/     up: /'
fi

set_upper
run -d
upper_cleaned && log_order "^killall dropbear" "^reboot -f" && ! wrote \
	&& ok "-d alone cleans the upper directory and reboots" \
	|| { bad "-d alone"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; }

set_upper
set_mounts overlayfs
run -d -x
[ "$RC" -eq 0 ] && upper_cleaned && ok "-d on the older overlayfs (t31) finds the upper directory" \
	|| { bad "-d on overlayfs"; echo "$OUT" | sed 's/^/     /'; }
set_mounts none
set_upper
run -d --archive="$SB/fw.tgz"
refused "-d with no readable overlay mount is refused before anything is stopped" "cannot find the overlay upper"
upper_intact && ! grep -q "^S95raptor stop\|^bind " "$FLASH_LOG" && ok "...and before services or the RAM root were touched" || bad "overlay refusal came too late"
set_mounts

set_upper
run -d -n
refused "-d with -n is refused" "means nothing"
upper_intact && ok "refusing -d -n touched nothing" || bad "refusing -d -n removed files"

set_upper
run --archive="$SB/fw.tgz" -d
upper_cleaned && log_order "^chroot" "^flashcp .*uImage" "^flashcp .*rootfs" "^reboot" \
	&& ok "-d with an archive cleans the upper directory, then flashes" \
	|| { bad "-d with archive"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; }

set_upper
ROOTFS_BYTES=$((0x510000)) make_archive "$SB/big2.tgz"
run --archive="$SB/big2.tgz" -d
upper_intact && ! wrote && ok "a refused flash with -d leaves the upper directory alone" \
	|| bad "-d ran before a check refused the flash"

echo "# RAM root"

STUB_CHROOT_RC=1 run --archive="$SB/fw.tgz"
refused "a RAM root that will not run a shell refuses before any write" "will not run inside"
# build_ramroot clears a stale RAM root first, so there are unmounts before the
# binds too; the ones that matter are the last three, after the binds.
last_line() { grep -n "$1" "$FLASH_LOG" | tail -1 | cut -d: -f1; }
if [ "$(last_line "^bind .*/dev")" -lt "$(last_line "^umount .*/dev")" ] \
	&& [ "$(last_line "^bind .*/proc")" -lt "$(last_line "^umount .*/proc")" ] \
	&& [ "$(last_line "^bind .*/tmp")" -lt "$(last_line "^umount .*/tmp")" ] \
	&& [ ! -e "$SB/tmp/sysupgrade.root" ]; then
	ok "the RAM root's bind mounts come down before it is removed"
else
	bad "RAM root teardown order"; sed 's/^/     log: /' "$FLASH_LOG"
fi

echo "# url"

STUB_CURL_FILE="$SB/fw.tgz" run --url=http://example.invalid/fw.tgz
log_order "^flashcp .*uImage" "^flashcp .*rootfs" "^reboot" && ok "--url streams the archive and flashes it" \
	|| { bad "--url"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; }

STUB_CURL_FILE=/dev/null run --url=http://example.invalid/fw.tgz
refused "an empty download is refused" "cannot fetch\|holds no uImage"

echo "# github"

STUB_CURL_FILE="$SB/fw.tgz" run --github=johnchia/firmware
grep -q "^curl https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc333-nor-raptor-latest.tgz$" "$FLASH_LOG" \
	&& log_order "^curl " "^flashcp .*uImage" "^reboot" \
	&& ok "--github composes this board's -latest archive under raptor-nightly and flashes it" \
	|| { bad "--github"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; }

set_osrel sc3336
STUB_CURL_FILE="$SB/fw.tgz" run --github=johnchia/firmware@v2
grep -q "^curl https://github.com/johnchia/firmware/releases/download/v2/openipc.ssc333_sc3336-nor-raptor-latest.tgz$" "$FLASH_LOG" \
	&& ok "--github: the pinned sensor is part of the name, and @TAG picks the release" \
	|| { bad "--github with sensor and tag"; sed 's/^/     log: /' "$FLASH_LOG"; }

# A camera target's archive is named by the camera alone: the name already
# carries the SoC and the sensor, so neither is spelled again.
set_osrel sc3336 kd110_ssc333_sc3336_rtl8188fu
STUB_CURL_FILE="$SB/fw.tgz" run --github=johnchia/firmware
grep -q "^curl https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.kd110_ssc333_sc3336_rtl8188fu-nor-raptor-latest.tgz$" "$FLASH_LOG" \
	&& ok "--github: a camera target composes openipc.<camera>-nor-<variant>, sensor and SoC not repeated" \
	|| { bad "--github with a camera"; sed 's/^/     log: /' "$FLASH_LOG"; }

# An image from before the stamp existed has no BUILD_CAMERA line at all.
printf 'BUILD_PLATFORM=ssc333_raptor\nBUILD_OPTION=raptor\nBUILD_SENSOR=sc3336\n' > "$SB/etc/os-release"
STUB_CURL_FILE="$SB/fw.tgz" run --github=johnchia/firmware
grep -q "^curl https://github.com/johnchia/firmware/releases/download/raptor-nightly/openipc.ssc333_sc3336-nor-raptor-latest.tgz$" "$FLASH_LOG" \
	&& ok "--github: no BUILD_CAMERA line composes the SoC-and-sensor name" \
	|| { bad "--github without the camera stamp"; sed 's/^/     log: /' "$FLASH_LOG"; }
set_osrel

run --github=johnchia
[ "$RC" -ne 0 ] && ! wrote && echo "$OUT" | grep -q "wants OWNER/REPO" && ! grep -q "^S95raptor stop" "$FLASH_LOG" \
	&& ok "--github without a slash is refused before anything is touched" || bad "--github form check"
run --github=johnchia/firmware --url=http://x/y.tgz
refused "--github with --url is refused" "give one of"

echo "# full image"

# A whole-flash image is laid down by absolute offset, so the fixtures are
# random bytes with the image's own mtdparts= planted where the env sits, and
# the assertion is that each partition received exactly the image's bytes at
# its offset: the flashcp stub logs the md5 of what it was handed.
TABLE='256k(boot),64k(env),2048k(kernel),5184k(rootfs),640k(rootfs_data)'
MOVED='192k(boot),64k(env),2560k(kernel),4992k(rootfs),384k(rootfs_data)'
set_cmdline() { printf 'mem=36M console=ttyAMA0,115200 root=/dev/mtdblock3 mtdparts=sfc:%s mmz_allocator=ot\n' "$1" > "$SB/proc/cmdline"; }
set_cmdline "$TABLE"
set_offsets() {
	local n=0 off
	for off in "$@"; do
		mkdir -p "$SB/sys/class/mtd/mtd$n"; echo "$off" > "$SB/sys/class/mtd/mtd$n/offset"; n=$((n + 1))
	done
}
set_offsets 0 262144 327680 2424832 7733248
make_full() {
	# $1 file, $2 size in KB, $3 the table its env names.
	head -c $(($2 * 1024)) /dev/urandom > "$1"
	printf '\0\0\0\0mtdparts=sfc:%s\0' "$3" | dd of="$1" bs=1024 seek=256 conv=notrunc status=none
}
slice_md5() { dd if="$1" bs=1024 skip="$2" count="$3" status=none | md5sum | cut -c1-32; }
stub flashcp 'echo "flashcp $* $(md5sum < "$1" | cut -c1-32)" >> "$FLASH_LOG"; exit ${STUB_FLASHCP_RC:-0}'

make_full "$SB/src/full.bin" 7552 "$TABLE"
FULL="$SB/src/full.bin"; SLICE="$SB/tmp/sysupgrade.pkg/sysupgrade.slice"
run --full="$FULL"
if log_order "^S95raptor stop" "^chroot " \
		"^flashcp $SLICE /dev/mtd0 $(slice_md5 "$FULL" 0 256)$" \
		"^flashcp $SLICE /dev/mtd1 $(slice_md5 "$FULL" 256 64)$" \
		"^flashcp $SLICE /dev/mtd2 $(slice_md5 "$FULL" 320 2048)$" \
		"^flashcp $SLICE /dev/mtd3 $(slice_md5 "$FULL" 2368 5184)$" \
		"^killall dropbear" "^reboot -f" \
	&& ! grep -q "^fw_setenv\|^flash_eraseall\|mtd4" "$FLASH_LOG" \
	&& [ ! -f "$SB/tmp/sysupgrade.pkg/full.bin" ] && [ ! -f "$SLICE" ] && [ -f "$FULL" ]; then
	ok "--full: every partition gets the image's bytes at its offset, in order; no env arming, overlay untouched, reboot"
	echo "$OUT" | grep -q "^Warning: a whole-flash image is written as given" && ok "--full warns that nothing checks the image is for this camera" || bad "no --full warning"
else
	bad "--full same table"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

# The common case: the image was copied straight into /tmp, so nothing staged
# it and $PKG does not exist. The first H4 run stopped here.
PLACE="$FULL" run --full="$SB/tmp/full.bin"
SLICE_TMP="$SB/tmp/sysupgrade.slice"
if log_order "^flashcp $SLICE_TMP /dev/mtd0 $(slice_md5 "$FULL" 0 256)$" "^flashcp $SLICE_TMP /dev/mtd3 " "^reboot -f" \
	&& [ ! -f "$SB/tmp/full.bin" ] && [ ! -f "$SLICE_TMP" ]; then
	ok "--full on an image already in /tmp: used in place, slices cut beside it, both deleted"
else
	bad "--full from /tmp"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

# OpenIPC's U-Boot puts u-boot on the command line where the env says boot:
# a table that differs only in names is the same table.
make_full "$SB/src/renamed.bin" 7552 "${TABLE/(boot)/(u-boot)}"
run --full="$SB/src/renamed.bin"
log_order "^flashcp $SLICE /dev/mtd0 " "^flashcp $SLICE /dev/mtd3 " "^reboot -f" && ! echo "$OUT" | grep -q "moves the partition table" \
	&& ok "a table that differs from the camera's only in partition names is not a move" \
	|| { bad "renamed table"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"; }

make_full "$SB/src/moved.bin" 7552 "$MOVED"
run --full="$SB/src/moved.bin"
refused "an image with another partition table is refused without -n" "the overlay moves with it; -n is required"
echo "$OUT" | grep -q "^  image:  $MOVED" && echo "$OUT" | grep -q "^  camera: $TABLE" && ok "...and both tables are shown" || bad "tables not shown"

make_full "$SB/src/moved-over.bin" 7808 "$MOVED"
run -n --full="$SB/src/moved-over.bin"
if log_order "^remount .*ro" "^chroot " "^flashcp $SLICE /dev/mtd3 " "^flash_eraseall /dev/mtd4$" \
		"^flashcp $SLICE /dev/mtd4 $(slice_md5 "$SB/src/moved-over.bin" 7552 256)$" "^reboot -f" \
	&& ! grep -q "^flash_eraseall -j" "$FLASH_LOG"; then
	ok "-n --full reaching into the overlay: overlay erased whole, then the covered part written; no second erase"
else
	bad "-n --full into the overlay"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

make_full "$SB/src/over.bin" 7808 "$TABLE"
run --full="$SB/src/over.bin"
refused "an image reaching into the overlay is refused without -n" "reaches into the overlay partition; -n is required"

make_full "$SB/src/long.bin" 8256 "$TABLE"
run --full="$SB/src/long.bin"
refused "an image longer than the flash table is refused" "the flash table ends at 8388608"

head -c 1000 /dev/urandom > "$SB/src/odd.bin"
run --full="$SB/src/odd.bin"
refused "an image that is not whole kilobytes is refused" "not whole kilobytes"

set_offsets 0 262144 327680 2490368 7733248
run --full="$FULL"
refused "a partition table that does not lay out end to end is refused" "does not lay out end to end"
set_offsets 0 262144 327680 2424832 7733248

STUB_FLASHCP_RC=1 run --full="$FULL"
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -q "^Stopping WITHOUT a reboot: /dev/mtd0 (boot)" \
	&& [ "$(grep -c '^flashcp' "$FLASH_LOG")" -eq 1 ] && ! grep -q "^reboot" "$FLASH_LOG"; then
	ok "a slice flashcp cannot verify stops the run without a reboot, and nothing after it is written"
else
	bad "flashcp failure under --full"; echo "$OUT" | sed 's/^/     /'; sed 's/^/     log: /' "$FLASH_LOG"
fi

set_mem 5000
PLACE="$FULL" run --full="$SB/tmp/full.bin"
refused "too little RAM for the largest slice beside the image is refused" "need .* KB of RAM for the largest slice"
set_mem 20000

run --full="$FULL" --archive="$SB/fw.tgz"
refused "--full with another source is refused" "give one of"

log_stub flashcp

echo "# usage"

run
[ "$RC" -ne 0 ] && ! wrote && echo "$OUT" | grep -q "^Usage" && ok "no arguments prints usage" || bad "no arguments"
run --bogus
[ "$RC" -ne 0 ] && ! wrote && ok "unknown option is refused" || bad "unknown option"
run -h
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q -- "--archive=FILE" && ok "-h" || bad "-h"

echo
if [ "$fail" -eq 0 ]; then echo "all sysupgrade-raptor tests passed"; else echo "$fail sysupgrade-raptor test(s) FAILED"; exit 1; fi
