#!/bin/sh

set -eu

BINARIES_DIR="$1"
ROOTFS="$BINARIES_DIR/rootfs.squashfs"
ROOTFS_LIMIT=$((8 * 1024 * 1024))

if [ ! -f "$ROOTFS" ]; then
	echo "ERROR: ssc30kq_ultimate expected SquashFS image at $ROOTFS" >&2
	exit 1
fi

ROOTFS_SIZE=$(wc -c < "$ROOTFS")
if [ "$ROOTFS_SIZE" -gt "$ROOTFS_LIMIT" ]; then
	echo "ERROR: ssc30kq_ultimate rootfs.squashfs is $ROOTFS_SIZE bytes;" >&2
	echo "       the NOR rootfs allocation is limited to $ROOTFS_LIMIT bytes (8 MiB)." >&2
	exit 1
fi

echo "ssc30kq_ultimate rootfs.squashfs: $ROOTFS_SIZE / $ROOTFS_LIMIT bytes"
