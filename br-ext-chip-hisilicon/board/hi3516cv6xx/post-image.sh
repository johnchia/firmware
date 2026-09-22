#!/bin/bash

BINARIES_DIR=$1
BOARD_DIR="$(dirname "$0")"
ITS_SOURCE="fit-image.its"

ERASEBLOCK_SIZE=$((64 * 1024))


cp ${BINARIES_DIR}/hi35*.dtb ${BINARIES_DIR}/fdt.dtb
cp ${BOARD_DIR}/${ITS_SOURCE} ${BINARIES_DIR}/
mkimage -f ${BINARIES_DIR}/${ITS_SOURCE} ${BINARIES_DIR}/fitImage

FIT_SIZE=$(stat -c%s "${BINARIES_DIR}/fitImage")
OFFSET_BLOCKS=$(( (FIT_SIZE + ERASEBLOCK_SIZE - 1) / ERASEBLOCK_SIZE ))

cp ${BINARIES_DIR}/fitImage ${BINARIES_DIR}/firmware.bin

dd if=${BINARIES_DIR}/rootfs.squashfs of=${BINARIES_DIR}/firmware.bin \
   bs=${ERASEBLOCK_SIZE} seek=${OFFSET_BLOCKS} conv=notrunc

truncate -s %${ERASEBLOCK_SIZE} ${BINARIES_DIR}/firmware.bin

# The sysupgrade archive takes the FIT under the name every other NOR board
# uses for its kernel, so the camera-side updater has one archive shape and
# never splits firmware.bin (see the hi3516cv6xx repack rule in the Makefile).
cp ${BINARIES_DIR}/fitImage ${BINARIES_DIR}/uImage
