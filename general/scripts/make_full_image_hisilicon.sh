#!/bin/sh -e
#
# Assemble a full-chip NOR image for a HiSilicon gen4 part.
#
# Usage: FLASH_KB=16384 make_full_image_hisilicon.sh \
#            <boot-container> <images-dir> <soc> <out> [env-extra]
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

# THE WHOLE DEFAULT ENVIRONMENT, NOT JUST THE PARTS BEING CHANGED.
#
# U-Boot uses its compiled-in defaults only while the flash environment fails
# its CRC. Write a valid one and that is the environment -- the defaults are not
# a fallback layer underneath it, and every variable left out is simply gone.
#
# An env carrying mtdparts and bootcmd alone therefore boots to
# "VFS: cannot open root device (null)": bootcmd runs `setenv bootargs
# ${bootargs}`, bootargs is not defined here, it expands to nothing, and the
# kernel is handed a command line with no root= in it. The rootfs was fine and
# in the right place; nothing had told the kernel where to look.
#
# So this mirrors CONFIG_BOOTARGS and CONFIG_EXTRA_ENV_SETTINGS from
# include/configs/hi-common.h, with mtdparts pointed at the 16m table. Keeping
# the recovery recipes matters as much as the boot path: urnor16m and setnor8m
# are how someone with a serial console gets out of trouble, and dropping them
# would leave a board whose only recovery is the clip that wrote this image.
#
# It tracks a file in another repository, which is a real cost. The alternative
# -- write four variables and lose the rest -- is what produced the (null).
{
	echo "bootargs=mem=\${osmem} console=ttyAMA0,115200 panic=20 root=/dev/mtdblock3 rootfstype=squashfs init=/init mtdparts=\${mtdparts} \${extras}"
	echo "bootcmd=setenv setargs setenv bootargs \${bootargs}; run setargs; sf probe 0; sf read \${baseaddr} 0x50000 0x300000; bootm \${baseaddr}"
	echo "mtdparts=$MTDPARTS"
	echo "baseaddr=0x42000000"
	echo "osmem=32M"
	echo "soc=$SOC"

	# Recovery, straight from hi-common.h. TFTP a kernel or a rootfs into the
	# 16m offsets, or move the partition table between layouts.
	echo "uknor8m=mw.b \${baseaddr} ff 1000000; tftpboot \${baseaddr} uImage.\${soc} && sf probe 0; sf erase 0x50000 0x200000; sf write \${baseaddr} 0x50000 \${filesize}"
	echo "uknor16m=mw.b \${baseaddr} ff 1000000; tftpboot \${baseaddr} uImage.\${soc} && sf probe 0; sf erase 0x50000 0x300000; sf write \${baseaddr} 0x50000 \${filesize}"
	echo "urnor8m=mw.b \${baseaddr} ff 1000000; tftpboot \${baseaddr} rootfs.squashfs.\${soc} && sf probe 0; sf erase 0x250000 0x500000; sf write \${baseaddr} 0x250000 \${filesize}"
	echo "urnor16m=mw.b \${baseaddr} ff 1000000; tftpboot \${baseaddr} rootfs.squashfs.\${soc} && sf probe 0; sf erase 0x350000 0xa00000; sf write \${baseaddr} 0x350000 \${filesize}"
	echo "mtdpartsnor8m=setenv mtdparts hi_sfc:256k(boot),64k(env),2048k(kernel),5120k(rootfs),-(rootfs_data)"
	echo "mtdpartsnor16m=setenv mtdparts $MTDPARTS"
	echo "bootcmdnor=setenv setargs setenv bootargs \${bootargs}; run setargs; sf probe 0; sf read \${baseaddr} 0x50000 0x300000; bootm \${baseaddr}"
	echo "setnor8m=run mtdpartsnor8m; setenv bootcmd \${bootcmdnor}; saveenv; reset"
	echo "setnor16m=run mtdpartsnor16m; setenv bootcmd \${bootcmdnor}; saveenv; reset"
	echo "nfsroot=/srv/nfs/\${soc}"
	echo "bootargsnfs=mem=\${osmem} console=ttyAMA0,115200 panic=20 root=/dev/nfs rootfstype=nfs ip=\${ipaddr}:::255.255.255.0::eth0 nfsroot=\${serverip}:\${nfsroot},v3,nolock rw \${extras}"
	echo "bootnfs=setenv setargs setenv bootargs \${bootargsnfs}; run setargs; tftpboot \${baseaddr} uImage.\${soc}; bootm \${baseaddr}"

	if [ -n "$ENV_EXTRA" ]; then
		if [ ! -f "$ENV_EXTRA" ]; then
			echo "missing env-extra: $ENV_EXTRA" >&2
			exit 1
		fi
		cat "$ENV_EXTRA"
	fi
} > "$env_txt"

# The one variable whose absence is silent and fatal. Everything else here
# degrades into a missing convenience; without this the kernel has no root.
grep -q '^bootargs=.*root=' "$env_txt" || {
	echo "refusing to write an environment with no root= in bootargs" >&2
	exit 1
}

# -r is the redundant-env flag and is NOT wanted: hi-common.h defines a single
# CONFIG_ENV_OFFSET with no CONFIG_ENV_OFFSET_REDUND, so a redundant image would
# put a flag byte where u-boot expects environment.
"$MKENVIMAGE" -s $((ENV_MAX_KB * 1024)) -o "$env_bin" "$env_txt"

IMAGE_KB=$((ROOTFS_OFF_KB + ROOTFS_MAX_KB))

# Pad out to the whole chip when the caller says how big it is, because the
# consumer of this file is a programmer on a clip and that writes chips, not
# partitions. A file that stops after rootfs leaves rootfs_data as whatever the
# donor chip happened to hold -- a previous owner's overlay, or on a verify pass
# a mismatch against a buffer the tool padded differently. Neither is what
# "erase, write, verify" should mean.
#
# The tail is rootfs_data and it is meant to be erased: that is a camera with a
# fresh overlay, which is the state firstboot puts it in anyway.
if [ -n "$FLASH_KB" ]; then
	if [ "$FLASH_KB" -lt "$IMAGE_KB" ]; then
		echo "image is ${IMAGE_KB} KB but the flash is ${FLASH_KB} KB" >&2
		echo "  the 10240k rootfs layout does not fit this part" >&2
		exit 1
	fi
	IMAGE_KB=$FLASH_KB
fi

# 0xFF is erased flash, so everything not written above stays erased.
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
if [ -n "$FLASH_KB" ]; then
	echo "-         padded to the full ${FLASH_KB} KB chip; rootfs_data erased"
else
	echo "-         NOT padded to a chip size (no FLASH_KB); ends after rootfs."
	echo "-         Pass FLASH_KB to get an image a programmer can verify."
fi
