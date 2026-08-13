#!/bin/sh
# Raptor owns the camera on any image that carries it.
#
# Majestic is present on some Raptor images as a reference encoder -- it is the
# thing to cross-check against when the MI stack refuses something and it is not
# clear whether the fault is Raptor's or the SoC's. But it must not start on its
# own: both it and rvd open the MI devices, and /etc/init.d runs in name order,
# so S95majestic would take the hardware before S95raptor ever ran and leave the
# camera with a streamer nobody configured.
#
# So the binary stays and the init script is defused, by renaming rather than
# deleting: majestic is then one `sh /etc/init.d/K95majestic start` away for a
# comparison run, and `/etc/init.d/S95raptor stop` first is the whole protocol.
# A K-prefix is inert to Buildroot's rcS, which globs S*.
#
# Runs from rootfs_script.sh, gated on BR2_PACKAGE_RAPTOR_STREAMING (see
# general/scripts/late-post-build-hooks.list), and therefore after every package
# has installed -- which is the point. Doing this from a package's own install
# step would race: Buildroot does not order two packages that have no dependency
# between them, and Raptor deliberately does not depend on Majestic.
set -eu

TARGET_DIR="${1:?target dir required}"

if [ -f "${TARGET_DIR}/etc/init.d/S95majestic" ]; then
	mv -f "${TARGET_DIR}/etc/init.d/S95majestic" \
		"${TARGET_DIR}/etc/init.d/K95majestic"
	echo "raptor-streaming: majestic autostart disabled (S95majestic -> K95majestic)"
fi
