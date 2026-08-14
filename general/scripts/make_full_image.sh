#!/bin/sh
#
# Assemble a full NOR image from *locally built* pieces.
#
# WHY THIS EXISTS
#
# The two paths that already make a full .bin -- general/scripts/repack_firmware.sh
# and create() in .github/workflows/image.yml -- both fetch their bootloader with
#
#   wget https://github.com/openipc/firmware/releases/download/latest/u-boot-<soc>-nor.bin
#
# and the workflow that produces that artefact clones openipc/u-boot-sigmastar.
# So a locally modified bootloader can never appear in an image either builds:
# they publish upstream's, and repack_firmware.sh downloads the *firmware* from
# the release server too, so a locally built rootfs does not appear either. That
# is the right default for reproducing a release and the wrong one for testing a
# change, which is what this script is for. Every byte here comes from this
# working tree.
#
# THE ENVIRONMENT IS DELIBERATELY BLANK
#
# The image spans boot..rootfs, so writing it clears the environment sector that
# sits between them. That is intended rather than tolerated: a blank environment
# is how a board with a derived MAC gets a correct one. U-Boot fills ethaddr from
# the NOR part's unique ID when it is empty or still the vendor default, so a
# board flashed with this comes up with an address of its own. Preserving a stale
# environment would carry the shared 00:00:23:34:45:66 forward instead.
#
# ON THE FLASH DESCRIPTOR (SNI)
#
# The boot container carries a description of the fitted flash part at offset
# 0x9000. A build from source writes a placeholder there -- "default sni", ID
# 05 ee ee -- and so does the u-boot-<soc>-nor.bin OpenIPC publishes, which is
# what these boards run today, so the placeholder is evidently not fatal.
# A board whose factory image holds a real descriptor (FUDANMICRO / FM25Q128A on
# the SSC377QE here) is nonetheless safer served by keeping the bytes already
# proven on that unit: pass SNI_REF=<dump of its mtd0> and the 4K sector at
# 0x9000 is taken from there instead. Without it the built container is used
# whole.
#
# Usage:
#   make_full_image.sh <uboot.bin> <images-dir> <soc-model> <output.bin> [sni-ref]
#

set -e

if [ $# -lt 4 ]; then
	echo "Usage: $0 <uboot.bin> <images-dir> <soc-model> <output.bin> [sni-ref]" >&2
	exit 1
fi

UBOOT=$1
IMAGES=$2
SOC=$3
OUT=$4
SNI_REF=$5

KERNEL=$IMAGES/uImage.$SOC
ROOTFS=$IMAGES/rootfs.squashfs.$SOC

# The SigmaStar NOR layout, in KiB, as the running kernel reports it:
#
#   mtdparts=NOR_FLASH:256k(boot),64k(env),2048k(kernel),5120k(rootfs),-(rootfs_data)
#
# Offsets are what the bootloader and the kernel command line both already
# assume; they are named here so the size checks below have something to check
# against rather than being spelled as bare numbers in dd calls.
BOOT_OFF_KB=0
BOOT_MAX_KB=256
ENV_OFF_KB=256
KERNEL_OFF_KB=320
KERNEL_MAX_KB=2048
ROOTFS_OFF_KB=2368
ROOTFS_MAX_KB=5120
IMAGE_KB=$((ROOTFS_OFF_KB + ROOTFS_MAX_KB))

for f in "$UBOOT" "$KERNEL" "$ROOTFS"; do
	if [ ! -f "$f" ]; then
		echo "missing: $f" >&2
		exit 1
	fi
done

# Check every piece against the partition it lands in, here rather than on the
# flash. An oversized rootfs written at its offset runs into rootfs_data and the
# failure surfaces as a camera that boots to nothing.
check() {
	_name=$1; _file=$2; _max=$3
	_kb=$(( ( $(wc -c < "$_file") + 1023 ) / 1024 ))
	printf -- "- %-8s %5d KB / %5d KB\n" "$_name" "$_kb" "$_max"
	if [ "$_kb" -gt "$_max" ]; then
		echo "  $_name exceeds its partition by $((_kb - _max)) KB" >&2
		exit 1
	fi
}

check uboot  "$UBOOT"  "$BOOT_MAX_KB"
check kernel "$KERNEL" "$KERNEL_MAX_KB"
check rootfs "$ROOTFS" "$ROOTFS_MAX_KB"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# 0xFF is erased flash, so anything not written stays erased -- including the
# environment sector between boot and kernel.
dd if=/dev/zero bs=1K count="$IMAGE_KB" status=none | tr '\000' '\377' > "$tmp"

dd if="$UBOOT"  of="$tmp" bs=1K seek="$BOOT_OFF_KB"   conv=notrunc status=none
dd if="$KERNEL" of="$tmp" bs=1K seek="$KERNEL_OFF_KB" conv=notrunc status=none
dd if="$ROOTFS" of="$tmp" bs=1K seek="$ROOTFS_OFF_KB" conv=notrunc status=none

if [ -n "$SNI_REF" ]; then
	if [ ! -f "$SNI_REF" ]; then
		echo "missing SNI reference: $SNI_REF" >&2
		exit 1
	fi
	dd if="$SNI_REF" of="$tmp" bs=4096 skip=9 seek=9 count=1 conv=notrunc status=none
	echo "- sni      taken from $SNI_REF"
fi

mv "$tmp" "$OUT"
trap - EXIT

echo "- full:   $OUT ($IMAGE_KB KB, env sector left erased)"
echo "-         boot@${BOOT_OFF_KB}K env@${ENV_OFF_KB}K kernel@${KERNEL_OFF_KB}K rootfs@${ROOTFS_OFF_KB}K"
