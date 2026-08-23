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

# Pin the sensor in raptor.conf where the kernel cannot be asked for it.
#
# rvd learns the sensor from /proc/jz/sensor/sensor0/{name,i2c_addr} and falls
# back to nothing. The 3.10 Ingenic kernel in this tree has no such directory
# -- /proc/jz/sinfo/info answers "sensor not found" on a board whose sensor is
# demonstrably working -- so IMP_ISP_AddSensor is handed no sensor, returns -1,
# and rvd exits before it creates a ring. S95raptor waits five seconds for that
# ring and then stops without starting anything else, which on a camera that
# has not been set up yet also costs the setup portal: rhd never runs, and the
# only thing on the network is an access point with no page behind it.
#
# The image already carries the answer. OpenIPC ships one /etc/sensor/<name>.yaml
# per single-sensor target with the i2c address in it, and this runs after every
# package, so it can be read. Doing the same from raptor-streaming's install step
# would race -- that file belongs to another package and Buildroot orders neither
# against the other, which is the reason this hook exists at all.
#
# Only on Ingenic, and only over a commented-out default: a SigmaStar image
# probes the sensor at runtime and must go on doing so.
CONF="${TARGET_DIR}/etc/raptor.conf"

if [ -f "${CONF}" ] && grep -q '^BR2_OPENIPC_SOC_VENDOR="ingenic"' "${BR2_CONFIG:-/dev/null}"; then
	set -- "${TARGET_DIR}"/etc/sensor/*.yaml
	# Exactly one, or the target is not single-sensor and guessing is worse
	# than leaving rvd to say what it could not find.
	if [ "$#" -eq 1 ] && [ -f "$1" ]; then
		SNS_NAME=$(sed -n 's/^[[:space:]]*name:[[:space:]]*//p' "$1" | head -1)
		SNS_ADDR=$(sed -n 's/^[[:space:]]*address:[[:space:]]*//p' "$1" | head -1)

		if [ -n "${SNS_NAME}" ] && [ -n "${SNS_ADDR}" ]; then
			# The first commented-out key of each name inside
			# [sensor], and only that one. raptor.conf carries a
			# multi-sensor example further down with the same key
			# names, and its blocks open with "# [sensor0]" -- a
			# comment, not a section header, so tracking sections
			# alone never leaves [sensor] and the example gets
			# uncommented too. That puts a second sensor into the
			# running config, which is worse than not pinning at all.
			awk -v name="${SNS_NAME}" -v addr="${SNS_ADDR}" '
				/^\[/ { insection = ($0 == "[sensor]") }
				insection && !seen_name && /^#[[:space:]]*name[[:space:]]*=/ {
					print "name = " name; seen_name = 1; next
				}
				insection && !seen_addr && /^#[[:space:]]*i2c_addr[[:space:]]*=/ {
					print "i2c_addr = " addr; seen_addr = 1; next
				}
				{ print }
			' "${CONF}" > "${CONF}.new" && mv -f "${CONF}.new" "${CONF}"

			echo "raptor-streaming: sensor pinned in raptor.conf (${SNS_NAME} at ${SNS_ADDR})"
		fi
	fi
fi
