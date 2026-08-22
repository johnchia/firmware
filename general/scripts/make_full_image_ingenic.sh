#!/bin/sh
#
# A full NOR image for an Ingenic board, bootloader included.
#
# THIS IS FOR THE MAINLINE INGENIC U-BOOT, NOT OPENIPC'S 2013.07 TREE
#
# The sibling make_full_image.sh implements the layout OpenIPC uses on both
# SigmaStar and Ingenic -- 256k(boot),64k(env),2048k(kernel), rootfs at 2368k --
# which is what repack_firmware.sh and create() in .github/workflows/image.yml
# assemble, and what openipc/u-boot-ingenic compiles in
# (include/configs/isvp_common.h). Its rootmtd emulation is that bootloader's
# own rule, common/cmd_sf.c. For a board running that bootloader, use that
# script; nothing here is needed.
#
# What is different here is the bootloader. The two Ingenic U-Boot lineages are
# not interchangeable:
#
#   openipc/u-boot-ingenic         2013.07 ISVP. Has `sdcard`, `uknor`, `urnor`
#                                  -- but only as commands somebody types at a
#                                  prompt. No fatwrite, no DM/DT MMC, no
#                                  button-at-boot.
#   gtxaspec/u-boot ingenic-t-series
#                                  mainline. CONFIG_FAT_WRITE, DM MMC with
#                                  card-detect and a slot-power regulator, and
#                                  CONFIG_BUTTON_CMD.
#
# Only the second can run unattended recovery: `autoupdate` reflashes the whole
# chip from an SD card at boot and `loaduenv` imports uenv.txt, neither of which
# needs a console. That matters because a camera whose only interface is a radio
# it has not been told the password for has no prompt to type at.
#
# Its layout is its own -- 320k(boot),64k(env),64k(backup) before anything of
# ours -- so the offsets below are neither script's default, and folding a
# second bootloader into the first script would make both harder to read than
# either is worth.
#
# EVERY PIECE HERE IS BUILT
#
# The bootloader comes from BR2_TARGET_UBOOT pinned to a commit of the fork
# above (see br-ext-chip-ingenic/configs/t31_raptor_defconfig), and the
# environment from host-uboot-tools running mkenvimage over
# br-ext-chip-ingenic/board/t31/wyze-v3.env.txt. Nothing is spliced out of a
# vendor image.
#
# The environment is the half that is easy to underrate. It is data in mtd1,
# not compiled into U-Boot, and it carries the partition table, the boot
# command and the recovery verbs. An erased sector leaves U-Boot on its
# compiled-in default, which for this tree has no `autoupdate` at all -- so a
# board flashed without it comes up unrecoverable even though the bootloader is
# fine. It also carries `data_addr` and `data_size`, which are what the reset
# button erases; a layout change that misses them points the recovery button at
# the rootfs.
#
# The layout past the environment is OpenIPC's sizes rather than thingino's --
# a 2048k kernel where thingino has 1600k, because that is what this tree's
# repack step produces and an OpenIPC kernel does not fit in 1600k -- and the
# overlay partition is named rootfs_data, which OpenIPC's /init greps /proc/mtd
# for. The env file and this script have to agree; they are two halves of one
# statement.
#
# Usage:
#   make_full_image_ingenic.sh <images-dir> <soc> <out.bin>
set -eu

IMAGES=$1
SOC=$2
OUT=$3

UBOOT=${UBOOT_BIN:-$IMAGES/u-boot-with-tpl-lzma.bin}
UBENV=${UBOOT_ENV_BIN:-$IMAGES/uboot-env.bin}
KERNEL=$IMAGES/uImage.$SOC
ROOTFS=$IMAGES/rootfs.squashfs.$SOC

# The layout, in KiB. The first three are the bootloader's and cannot move:
# CONFIG_ENV_OFFSET=0x50000 and CONFIG_ENV_SIZE=0x10000 are compiled into
# U-Boot. Everything from 448k on is ours.
BOOT_OFF_KB=0
BOOT_KB=320
ENV_OFF_KB=320
ENV_KB=64
BACKUP_OFF_KB=384
BACKUP_KB=64
KERNEL_OFF_KB=448
KERNEL_MAX_KB=2048
ROOTFS_OFF_KB=2496
ROOTFS_MAX_KB=8192
IMAGE_KB=16384

for f in "$UBOOT" "$UBENV" "$KERNEL" "$ROOTFS"; do
	if [ ! -f "$f" ]; then
		echo "missing: $f" >&2
		exit 1
	fi
done

magic() { xxd -s "$2" -l 4 -p "$1"; }

# Each piece is identified before it is written, because every one of them is
# silent when it is wrong: a u-boot.bin that is really the ELF, a kernel that is
# really a vmlinux, a rootfs that is really a tar. None of that shows up until
# the board does not boot, and this board has no console to say why.
if [ "$(magic "$UBOOT" 0)" != "06050403" ]; then
	echo "- $UBOOT does not start with the Ingenic bootloader magic 06050403." >&2
	echo "  BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME should be u-boot-with-tpl-lzma.bin;" >&2
	echo "  u-boot.bin without the TPL will not boot." >&2
	exit 1
fi
if [ "$(magic "$KERNEL" 0)" != "27051956" ]; then
	echo "- $KERNEL is not a uImage (magic 27051956)." >&2
	exit 1
fi
if [ "$(magic "$ROOTFS" 0)" != "68737173" ]; then
	echo "- $ROOTFS is not a squashfs (magic 68737173)." >&2
	exit 1
fi

# mkenvimage output has no magic -- it is a CRC32 followed by NUL-separated
# key=value -- so size is the only check available, and it is the one that
# matters: U-Boot reads exactly CONFIG_ENV_SIZE bytes and CRCs them, so an
# image built for a different -s fails the CRC and the board falls back to the
# compiled-in default, which has no recovery verbs in it.
env_size=$(stat -c %s "$UBENV")
if [ "$env_size" -ne $(( ENV_KB * 1024 )) ]; then
	echo "- $UBENV is $env_size bytes, expected $(( ENV_KB * 1024 ))." >&2
	echo "  BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SIZE must be 0x$(printf %x $(( ENV_KB * 1024 )))." >&2
	exit 1
fi
# An environment without these is a bootloader that cannot be reached again.
for v in bootcmd autoupdate loaduenv mtdparts data_addr data_size; do
	if ! tr '\0' '\n' < "$UBENV" | grep -q "^$v="; then
		echo "- $UBENV has no $v. Refusing to build an image that cannot recover." >&2
		exit 1
	fi
done

check() {
	_name=$1
	_kb=$(( ($(stat -c %s "$2") + 1023) / 1024 ))
	_max=$3
	echo "- $_name    $_kb KB of $_max KB"
	if [ "$_kb" -gt "$_max" ]; then
		echo "  $_name exceeds its partition by $(( _kb - _max )) KB" >&2
		exit 1
	fi
}

check bootloader "$UBOOT" "$BOOT_KB"
check kernel "$KERNEL" "$KERNEL_MAX_KB"
check rootfs "$ROOTFS" "$ROOTFS_MAX_KB"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# 0xFF is erased flash, so every gap -- the backup sector, the tail of each
# partition, the whole overlay -- stays erased. The overlay in particular must
# be erased rather than zeroed: /init mounts it as JFFS2 and formats it when the
# magic is absent, and a region of zeroes is not an erased region to a NOR part.
dd if=/dev/zero bs=1K count="$IMAGE_KB" status=none | tr '\000' '\377' > "$tmp"

dd if="$UBOOT"  of="$tmp" bs=1K seek="$BOOT_OFF_KB"   conv=notrunc status=none
dd if="$UBENV"  of="$tmp" bs=1K seek="$ENV_OFF_KB"    conv=notrunc status=none
dd if="$KERNEL" of="$tmp" bs=1K seek="$KERNEL_OFF_KB" conv=notrunc status=none
dd if="$ROOTFS" of="$tmp" bs=1K seek="$ROOTFS_OFF_KB" conv=notrunc status=none

mv "$tmp" "$OUT"
trap - EXIT

echo "- full:   $OUT ($IMAGE_KB KB)"
echo "-         boot@${BOOT_OFF_KB}K env@${ENV_OFF_KB}K backup@${BACKUP_OFF_KB}K erased"
echo "-         kernel@${KERNEL_OFF_KB}K rootfs@${ROOTFS_OFF_KB}K"
echo "-         rootfs_data@$(( ROOTFS_OFF_KB + ROOTFS_MAX_KB ))K erased"
echo "-         copy to a FAT32 card as autoupdate-full.bin to flash it"
