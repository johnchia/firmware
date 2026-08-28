#!/bin/sh
#
# The SquashFS has to fit the rootfs partition, and the build is the cheap place
# to find out. `make br-<pkg>` never reaches repack, and flashcp refusing an
# oversized image leaves a camera to be recovered rather than a number to be
# read.
#
# The limit is BR2_OPENIPC_ROOTFS_PART_KB -- the same value the Makefile's
# ROOTFS_CAP_KB hands to CHECK_SIZE at repack. Stated once, in the board
# defconfig, so the two checks cannot come to different conclusions. It is a
# property of the partition table and not of the flash chip: a 16MB board can
# give the rootfs 5120KB and the rest to an overlay.
#
# Unset is an error rather than a guess. A default here would be a second copy
# of the Makefile's fallback, and two copies of a limit is the thing this file
# exists to remove.
#
# The kernel is deliberately not checked. Its cap lives at the PREPARE_REPACK
# call site rather than in a config symbol, so checking it here would invent the
# second home that the paragraph above is about.
set -eu

BINARIES_DIR=$1
ROOTFS=$BINARIES_DIR/rootfs.squashfs
NAME=${OPENIPC_SOC_MODEL:-image}_${OPENIPC_VARIANT:-image}

: "${OPENIPC_ROOTFS_PART_KB:?BR2_OPENIPC_ROOTFS_PART_KB is not set for this board}"
LIMIT=$((OPENIPC_ROOTFS_PART_KB * 1024))

if [ ! -f "$ROOTFS" ]; then
	echo "ERROR: $NAME expected a SquashFS image at $ROOTFS" >&2
	exit 1
fi

SIZE=$(wc -c < "$ROOTFS")
if [ "$SIZE" -gt "$LIMIT" ]; then
	echo "ERROR: $NAME rootfs.squashfs is $SIZE bytes; the partition holds" >&2
	echo "       $LIMIT ($OPENIPC_ROOTFS_PART_KB KB, BR2_OPENIPC_ROOTFS_PART_KB)." >&2
	exit 1
fi

echo "$NAME rootfs.squashfs: $SIZE / $LIMIT bytes ($(( (LIMIT - SIZE) / 1024 ))KB free)"
