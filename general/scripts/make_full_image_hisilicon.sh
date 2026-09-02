#!/bin/sh -e
#
# Assemble a full-chip NOR image for a HiSilicon gen4 part.
#
# Usage: make_full_image_hisilicon.sh <boot-container> <images-dir> <soc> <out> [env-extra]
#
# THIS SCRIPT WRITES THE ENVIRONMENT, AND THAT IS THE WHOLE POINT.
#
# The SigmaStar script beside this one deliberately leaves the env sector
# erased, because that bootloader decides the rootfs partition for itself: it
# reads the squashfs superblock and picks 5120k or 8192k (common/cmd_sf.c).
# u-boot-hi3516ev200 does no such thing. Its mtdparts is a plain environment
# variable with a compiled-in default (include/configs/hi-common.h):
#
#   mtdparts=hi_sfc:256k(boot),64k(env),2048k(kernel),5120k(rootfs),-(rootfs_data)
#
# and the larger layout exists only as a command a human runs at the prompt:
#
#   setnor16m -> mtdparts=hi_sfc:256k(boot),64k(env),3072k(kernel),10240k(rootfs),-(rootfs_data)
#
# So an image built for the 16m layout that left the env erased would boot on
# the 8m table, look for its rootfs at 0x250000 instead of 0x350000, and find
# the tail of the kernel partition there. Leaving the env alone is not the safe
# option here; it is the broken one.
#
# The cost of writing it is that the board's own environment is gone --
# ethaddr, wlanmac, serial, anything a vendor or a previous owner set. Pass a
# file as the fifth argument and its lines are merged in, which is where a MAC
# read off the old env goes.
#
# NOTE ON THE BOOTLOADER. Nothing in this repository builds one for HiSilicon:
# .github/workflows/uboot.yml covers allwinner, ingenic and sigmastar only, so
# there is no release asset to fetch and no br-uboot to run. The container comes
# from OpenIPC/u-boot-hi3516ev200's own build.sh, which pairs config-<soc> with
# reg_info_<soc>.bin -- the DDR init table. That table is the reference design's.
# A board whose DDR differs will not reach the u-boot prompt at all, and the
# only way back is a programmer on the flash. Write the bootloader region only
# when you can clip the chip.

BOOT=$1
IMAGES=$2
SOC=$3
OUT=$4
ENV_EXTRA=$5

if [ -z "$BOOT" ] || [ -z "$IMAGES" ] || [ -z "$SOC" ] || [ -z "$OUT" ]; then
	echo "usage: $0 <boot-container> <images-dir> <soc> <out> [env-extra]" >&2
	exit 1
fi

KERNEL=$IMAGES/uImage.$SOC
ROOTFS=$IMAGES/rootfs.squashfs.$SOC

# The nor16m layout, in KiB. These are not free choices: they are what
# mtdpartsnor16m spells, and the env written below says the same thing to the
# kernel. Change one without the other and the rootfs is not where mtd3 points.
BOOT_OFF_KB=0
BOOT_MAX_KB=256
ENV_OFF_KB=256
ENV_MAX_KB=64
KERNEL_OFF_KB=320
KERNEL_MAX_KB=3072
ROOTFS_OFF_KB=3392
ROOTFS_MAX_KB=10240

MTDPARTS="hi_sfc:256k(boot),64k(env),3072k(kernel),10240k(rootfs),-(rootfs_data)"

for f in "$BOOT" "$KERNEL" "$ROOTFS"; do
	if [ ! -f "$f" ]; then
		echo "missing: $f" >&2
		exit 1
	fi
done

# Check every piece against the partition it lands in, here rather than on the
# flash. This is the check that was missing when a 5356KB rootfs went onto a
# 5120k mtd3 and produced a camera that could not mount root.
check() {
	_name=$1; _file=$2; _max=$3
	_kb=$(( ( $(wc -c < "$_file") + 1023 ) / 1024 ))
	printf -- "- %-8s %5d KB / %5d KB\n" "$_name" "$_kb" "$_max"
	if [ "$_kb" -gt "$_max" ]; then
		echo "  $_name exceeds its partition by $((_kb - _max)) KB" >&2
		exit 1
	fi
}

check uboot  "$BOOT"   "$BOOT_MAX_KB"
check kernel "$KERNEL" "$KERNEL_MAX_KB"
check rootfs "$ROOTFS" "$ROOTFS_MAX_KB"

MKENVIMAGE=${MKENVIMAGE:-mkenvimage}
command -v "$MKENVIMAGE" >/dev/null 2>&1 || {
	echo "no mkenvimage on PATH; set MKENVIMAGE=<path>" >&2
	echo "  one is built at \$(TARGET)/host/bin/mkenvimage" >&2
	exit 1
}

tmp=$(mktemp)
env_txt=$(mktemp)
env_bin=$(mktemp)
trap 'rm -f "$tmp" "$env_txt" "$env_bin"' EXIT

# Only what the boot path actually reads. bootargs is compiled in and expands
# ${mtdparts} and ${osmem} from here; bootcmd is spelled out rather than left to
# the compiled-in default so that a board arriving from the nand or ubi settings
# comes back to NOR.
{
	echo "mtdparts=$MTDPARTS"
	echo "bootcmd=setenv setargs setenv bootargs \${bootargs}; run setargs; sf probe 0; sf read \${baseaddr} 0x50000 0x300000; bootm \${baseaddr}"
	echo "baseaddr=0x42000000"
	echo "osmem=32M"
	echo "soc=$SOC"
	if [ -n "$ENV_EXTRA" ]; then
		if [ ! -f "$ENV_EXTRA" ]; then
			echo "missing env-extra: $ENV_EXTRA" >&2
			exit 1
		fi
		cat "$ENV_EXTRA"
	fi
} > "$env_txt"

# -r is the redundant-env flag and is NOT wanted: hi-common.h defines a single
# CONFIG_ENV_OFFSET with no CONFIG_ENV_OFFSET_REDUND, so a redundant image would
# put a flag byte where u-boot expects environment.
"$MKENVIMAGE" -s $((ENV_MAX_KB * 1024)) -o "$env_bin" "$env_txt"

IMAGE_KB=$((ROOTFS_OFF_KB + ROOTFS_MAX_KB))

# 0xFF is erased flash, so rootfs_data past the end of this image stays erased,
# which is what an unclaimed camera wants: a fresh overlay.
dd if=/dev/zero bs=1K count="$IMAGE_KB" status=none | tr '\000' '\377' > "$tmp"

dd if="$BOOT"    of="$tmp" bs=1K seek="$BOOT_OFF_KB"   conv=notrunc status=none
dd if="$env_bin" of="$tmp" bs=1K seek="$ENV_OFF_KB"    conv=notrunc status=none
dd if="$KERNEL"  of="$tmp" bs=1K seek="$KERNEL_OFF_KB" conv=notrunc status=none
dd if="$ROOTFS"  of="$tmp" bs=1K seek="$ROOTFS_OFF_KB" conv=notrunc status=none

mv "$tmp" "$OUT"
trap - EXIT
rm -f "$env_txt" "$env_bin"

echo "- full:   $OUT ($IMAGE_KB KB)"
echo "-         boot@${BOOT_OFF_KB}K env@${ENV_OFF_KB}K kernel@${KERNEL_OFF_KB}K rootfs@${ROOTFS_OFF_KB}K"
echo "-         mtdparts written: $MTDPARTS"
