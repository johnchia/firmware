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
HERE="$(dirname "$0")"

# The updater. Raptor images flash through sysupgrade-raptor (files/), a
# single-case rewrite of OpenIPC's sysupgrade for NOR cameras with separate
# kernel and rootfs partitions -- which every raptor board is. The upstream
# script stays in git for the images that are not raptor's, but it is not
# shipped here: /usr/sbin/sysupgrade becomes a symlink, so firstboot, rcd's
# recovery advice and the operator's habits keep working, and the 25 KB the
# upstream copy costs an 8 MB board comes back. Installed from this hook rather
# than a late overlay so test_shell_parse.sh finds it under files/ like every
# other shipped script.
install -m 0755 "${HERE}/files/sysupgrade-raptor" "${TARGET_DIR}/usr/sbin/sysupgrade-raptor"
ln -sfn sysupgrade-raptor "${TARGET_DIR}/usr/sbin/sysupgrade"
echo "raptor-streaming: /usr/sbin/sysupgrade -> sysupgrade-raptor"

if [ -f "${TARGET_DIR}/etc/init.d/S95majestic" ]; then
	mv -f "${TARGET_DIR}/etc/init.d/S95majestic" \
		"${TARGET_DIR}/etc/init.d/K95majestic"
	echo "raptor-streaming: majestic autostart disabled (S95majestic -> K95majestic)"
fi

# Pin the sensor in raptor.conf where the kernel cannot be asked for it.
#
# rvd learns the sensor from /proc/jz/sensor/sensor0/{name,i2c_addr,width,height}
# and falls back to nothing. The 3.10 Ingenic kernel in this tree has no such
# directory -- /proc/jz/sinfo/info answers "sensor not found" on a board whose
# sensor is demonstrably working -- so all four have to be supplied here.
#
# Without the name and address IMP_ISP_AddSensor is handed no sensor, returns
# -1, and rvd exits before it creates a ring. S95raptor waits five seconds for
# that ring and then stops without starting anything else, which on a camera
# that has not been set up yet also costs the setup portal: rhd never runs, and
# the only thing on the network is an access point with no page behind it.
#
# Without the resolution the camera streams, and the substream is quietly
# corrupt. rvd gates its whole crop-and-scaler step on knowing the sensor size
# (rvd_pipeline.c, "if (sensor_w > 0 && sensor_h > 0)"), because that is what
# it compares each stream against to decide whether the IPU has to downscale.
# Unknown means the step is skipped, so the sub framesource channel is created
# at its small picWidth/picHeight with scaler.enable = 0 and the IPU is never
# told to scale: full-width sensor rows land in a buffer sized for the small
# geometry. The result is a sheared, magenta-and-green substream -- the NV12
# chroma plane is read at w*h, which is inside the luma data -- while the main
# stream, whose size equals the sensor's and needs no scaler, is perfect. Every
# consumer of that channel inherits it, which is why /snap.jpg?stream=1 is
# corrupt and stream=0 is not: rvd gives a JPEG channel its parent's fs_chn.
#
# rvd has three fallbacks behind procfs and this board misses all of them. The
# HAL's isp_get_sensor_attr is compiled for T40/T41 only and returns -ENOTSUP
# on T31, though the SDK does have IMP_ISP_Tuning_GetSensorAttr -- see
# HANDOFF-t31-sensor-attr.md in the raptor tree, which is the fix that would
# retire this half of the hook. [stream0] is empty because stream 0 is meant to
# default to the sensor's own size. [sensor] is what is left.
#
# The image already carries the answer. OpenIPC ships one /etc/sensor/<name>.yaml
# per single-sensor target with the address and the resolution in it -- all 124
# of them across the six ingenic-osdrv packages have all three -- and this runs
# after every package, so it can be read. Doing the same from raptor-streaming's
# install step would race -- that file belongs to another package and Buildroot
# orders neither against the other, which is the reason this hook exists at all.
#
# Only on Ingenic, and only over a commented-out default: a SigmaStar image
# probes the sensor at runtime and must go on doing so.
CONF="${TARGET_DIR}/etc/raptor.conf"

if [ -f "${CONF}" ] && grep -q '^BR2_OPENIPC_SOC_VENDOR="ingenic"' "${BR2_CONFIG:-/dev/null}"; then
	set -- "${TARGET_DIR}"/etc/sensor/*.yaml
	# Exactly one, or the target is not single-sensor and guessing is worse
	# than leaving rvd to say what it could not find.
	#
	# Only ever on an unpinned raptor.conf, because the rewrite below is
	# not idempotent: on a second pass the real [sensor] keys are already
	# uncommented, so the first-match rules walk on and find the
	# multi-sensor [sensor0] example instead -- which opens with
	# "# [sensor0]", a comment, so section tracking never left [sensor].
	# That would uncomment the example's name and i2c_addr with this
	# board's values, putting a duplicate pair into the running config and
	# destroying the example.
	#
	# The ordinary build never gets there: /etc/raptor.conf comes from
	# general/overlay, Buildroot re-applies overlays on every rootfs
	# assembly, and the copy on disk is unpinned. This guards the case
	# where it does not -- a hand-edited target directory, or an overlay
	# that someone pins by hand -- where the damage is silent.
	if [ "$#" -eq 1 ] && [ -f "$1" ] && ! awk '
		/^\[/ { insection = ($0 == "[sensor]") }
		insection && /^name[[:space:]]*=/ { found = 1 }
		END { exit !found }
	' "${CONF}"; then
		SNS_NAME=$(sed -n 's/^[[:space:]]*name:[[:space:]]*//p' "$1" | head -1)
		SNS_ADDR=$(sed -n 's/^[[:space:]]*address:[[:space:]]*//p' "$1" | head -1)
		SNS_W=$(sed -n 's/^[[:space:]]*width:[[:space:]]*//p' "$1" | head -1)
		SNS_H=$(sed -n 's/^[[:space:]]*height:[[:space:]]*//p' "$1" | head -1)

		if [ -n "${SNS_NAME}" ] && [ -n "${SNS_ADDR}" ]; then
			# The first commented-out key of each name inside
			# [sensor], and only that one. raptor.conf carries a
			# multi-sensor example further down with the same key
			# names, and its blocks open with "# [sensor0]" -- a
			# comment, not a section header, so tracking sections
			# alone never leaves [sensor] and the example gets
			# uncommented too. That puts a second sensor into the
			# running config, which is worse than not pinning at all.
			# width and height are inserted after the [sensor]
			# header rather than uncommented in place, because
			# single-sensor [sensor] ships no commented pair to
			# uncomment -- the only "# width =" in the file belongs
			# to the multi-sensor [sensor0] example far below, and
			# that example opens with "# [sensor0]", a comment
			# rather than a section header. Tracking sections never
			# leaves [sensor], so a first-match rule of the kind
			# used for name and i2c_addr would reach down into the
			# example and uncomment its line instead. Inserting at
			# the top of the section cannot pick the wrong line.
			awk -v name="${SNS_NAME}" -v addr="${SNS_ADDR}" \
			    -v w="${SNS_W}" -v h="${SNS_H}" '
				/^\[/ { insection = ($0 == "[sensor]") }
				$0 == "[sensor]" {
					print
					if (w != "" && h != "") {
						print "width = " w
						print "height = " h
					}
					next
				}
				insection && !seen_name && /^#[[:space:]]*name[[:space:]]*=/ {
					print "name = " name; seen_name = 1; next
				}
				insection && !seen_addr && /^#[[:space:]]*i2c_addr[[:space:]]*=/ {
					print "i2c_addr = " addr; seen_addr = 1; next
				}
				{ print }
			' "${CONF}" > "${CONF}.new" && mv -f "${CONF}.new" "${CONF}"

			if [ -n "${SNS_W}" ] && [ -n "${SNS_H}" ]; then
				echo "raptor-streaming: sensor pinned in raptor.conf (${SNS_NAME} at ${SNS_ADDR}, ${SNS_W}x${SNS_H})"
			else
				# Streams, with a corrupt substream. Worth a line
				# of its own: the symptom points at the encoder,
				# not at a missing key in a yaml file.
				echo "raptor-streaming: sensor pinned in raptor.conf (${SNS_NAME} at ${SNS_ADDR}); no resolution in $1, substream scaling will be wrong"
			fi
		fi
	fi
fi

# Camera facts, from the camera directory (general/cameras.mk).
#
# A camera target may carry a partial raptor.conf beside its camera.conf: the
# pins that are facts about that circuit board and nothing else -- an IR-cut
# filter's GPIOs, a backlight, a speaker enable. They cannot live in the
# shared /etc/raptor.conf, which every image ships, and they must not live in
# a first-boot script that edits the running config, which is the failure mode
# OpenIPC/builder's customizer.sh has on 102 devices: state in the overlay that
# outlives an upgrade, run on a camera nobody has claimed. So they are merged
# here, at build time, into the copy of raptor.conf that ships in the
# squashfs. thingino does the same with thingino.json.
#
# Each key in the partial goes to the top of its section and the first
# commented-out or set line of the same name in that section is dropped, so
# the value wins and the default it replaces does not linger as a second
# setting. That is idempotent -- a second pass drops the line the first pass
# put there and puts it back -- which the sensor pin above is not, and which
# matters for the same reason it matters there. A section the file lacks is
# appended. Anything in the partial that is not a comment, a [section] or a
# key = value line fails the build here rather than shipping as a config the
# daemons cannot parse.
#
# Two passes: the partial is first read into "section<TAB>key<TAB>value"
# lines, so the checks run before anything is written, and then merged last
# key first, so that inserting each at the top of its section leaves them in
# the partial's own order.
CAMERA_PART="${OPENIPC_CAMERA_DIR:+${OPENIPC_CAMERA_DIR}/raptor.conf}"
if [ -f "${CONF}" ] && [ -n "${CAMERA_PART}" ] && [ -f "${CAMERA_PART}" ]; then
	merge_key() {
		awk -v sec="[$1]" -v key="$2" -v val="$3" '
			/^\[/ { insec = ($0 == sec) }
			$0 == sec { print; print key " = " val; found = 1; next }
			insec && !dropped && $0 ~ ("^#?[[:space:]]*" key "[[:space:]]*=") { dropped = 1; next }
			{ print }
			END { if (!found) { print ""; print sec; print key " = " val } }
		' "${CONF}" > "${CONF}.new" && mv -f "${CONF}.new" "${CONF}"
	}
	sec=; keys=
	while IFS= read -r line || [ -n "${line}" ]; do
		case "${line}" in
			'' | '#'* | ' '* | '	'*) continue ;;
			'['*']') sec=${line#\[}; sec=${sec%\]}; continue ;;
			*=*) ;;
			*) echo "raptor-streaming: ${CAMERA_PART}: cannot read '${line}' (want [section] or key = value)"; exit 1 ;;
		esac
		key=$(printf '%s' "${line%%=*}" | tr -d ' \t')
		val=$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
		case "${key}" in
			'' | *[!A-Za-z0-9_]*) echo "raptor-streaming: ${CAMERA_PART}: bad key in '${line}'"; exit 1 ;;
		esac
		[ -n "${sec}" ] || { echo "raptor-streaming: ${CAMERA_PART}: '${line}' comes before any [section]"; exit 1; }
		keys=$(printf '%s\t%s\t%s\n%s' "${sec}" "${key}" "${val}" "${keys}")
	done < "${CAMERA_PART}"
	printf '%s\n' "${keys}" | while IFS='	' read -r sec key val; do
		[ -n "${key}" ] || continue
		merge_key "${sec}" "${key}" "${val}"
		echo "raptor-streaming: raptor.conf [${sec}] ${key} = ${val} (from ${OPENIPC_CAMERA})"
	done
fi
