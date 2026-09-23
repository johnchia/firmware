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

set_osrel() { printf 'BUILD_PLATFORM=ssc333_raptor\nBUILD_OPTION=raptor\nBUILD_SENSOR=%s\n' "${1:-}" > "$SB/etc/os-release"; }
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
make_rootfs() { { printf 'hsqs'; head -c "${2:-8188}" /dev/zero; } > "$1"; }

# Archive members named as the build names them, with an .md5sum beside each.
make_archive() {
	local out=$1 stage="$SB/stage"
	rm -rf "$stage"; mkdir -p "$stage"
	[ -n "${NO_KERNEL:-}" ] || make_uimage "$stage/uImage.ssc333"
	[ -n "${NO_ROOTFS:-}" ] || make_rootfs "$stage/rootfs.squashfs.ssc333" "${ROOTFS_BYTES:-8188}"
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
set_osrel

run --github=johnchia
[ "$RC" -ne 0 ] && ! wrote && echo "$OUT" | grep -q "wants OWNER/REPO" && ! grep -q "^S95raptor stop" "$FLASH_LOG" \
	&& ok "--github without a slash is refused before anything is touched" || bad "--github form check"
run --github=johnchia/firmware --url=http://x/y.tgz
refused "--github with --url is refused" "give one of"

echo "# usage"

run
[ "$RC" -ne 0 ] && ! wrote && echo "$OUT" | grep -q "^Usage" && ok "no arguments prints usage" || bad "no arguments"
run --bogus
[ "$RC" -ne 0 ] && ! wrote && ok "unknown option is refused" || bad "unknown option"
run -h
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q -- "--archive=FILE" && ok "-h" || bad "-h"

echo
if [ "$fail" -eq 0 ]; then echo "all sysupgrade-raptor tests passed"; else echo "$fail sysupgrade-raptor test(s) FAILED"; exit 1; fi
