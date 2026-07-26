#!/bin/bash
DATE=$(date +%y.%m.%d)
FILE=${TARGET_DIR}/usr/lib/os-release
LATE_OVERLAY_LIST="${BR2_EXTERNAL_GENERAL_PATH}/scripts/late-overlays.list"
LATE_POST_BUILD_HOOKS="${BR2_EXTERNAL_GENERAL_PATH}/scripts/late-post-build-hooks.list"

# Build identity, and the one place it is decided.
#
# CI exports BUILD_ID and GIT_HASH; a local build has neither and used to end up
# with BUILD_ID=local-<date>-build -- true, and useless for telling two builds
# apart. Derive it from the checkout instead and record it in the rootfs as
# /etc/openipc-build-id, so a running camera can be asked which image it has:
#
#   cat /etc/openipc-build-id
#
# The top-level Makefile reads this same file back when it names the release
# tarball (see REPACK_FIRMWARE), which is the point: the name of the artefact and
# the stamp inside it are one string rather than two computations that can drift
# apart. They did drift, and flashing the wrong one of two same-named images cost
# an evening.
#
# `status --porcelain` rather than `diff --quiet HEAD`, because it reports
# untracked files too. The change that motivated all this was a whole new package
# directory that git had never seen, and a diff against HEAD calls that clean.
OPENIPC_BUILD_ID=${OPENIPC_BUILD_ID:-${BUILD_ID}}
OPENIPC_BUILD_SHA=${GIT_HASH:-$(git -C "${BR2_EXTERNAL_GENERAL_PATH}" rev-parse --short HEAD 2>/dev/null)}
OPENIPC_BUILD_SHA=${OPENIPC_BUILD_SHA:-nogit}
if [ -n "$(git -C "${BR2_EXTERNAL_GENERAL_PATH}" status --porcelain 2>/dev/null)" ]; then
	OPENIPC_BUILD_SHA="${OPENIPC_BUILD_SHA}-dirty"
fi
OPENIPC_BUILD_ID=${OPENIPC_BUILD_ID:-${OPENIPC_BUILD_SHA}-$(date -u +%Y%m%dT%H%M%SZ)}

mkdir -p ${TARGET_DIR}/etc
printf '%s\n' "${OPENIPC_BUILD_ID}" > ${TARGET_DIR}/etc/openipc-build-id

echo OPENIPC_VERSION=${DATE:0:1}.${DATE:1} >> ${FILE}
date +GITHUB_VERSION="\"${GIT_BRANCH-local}+${GIT_HASH-build}, %Y-%m-%d"\" >> ${FILE}
echo BUILD_OPTION=${OPENIPC_VARIANT} >> ${FILE}
echo BUILD_ID=${OPENIPC_BUILD_ID} >> ${FILE}
echo BUILD_SHA=${BUILD_SHA:-${OPENIPC_BUILD_SHA}} >> ${FILE}
echo BUILD_PLATFORM=${BUILD_PLATFORM:-${OPENIPC_SOC_MODEL}_${OPENIPC_VARIANT}} >> ${FILE}
date +TIME_STAMP=%s >> ${FILE}

CONF="USES_GLIBC=y|OSDRV_T30=y|OSDRV_V85X=y|LIBV4L=y|MAVLINK_ROUTER=y|RUBYFPV=y|ONYXFPV=y|WIFIBROADCAST=y|WIFIBROADCAST_NG=y|AUDIO_PROCESSING_OPENIPC=y"
if ! grep -qP ${CONF} ${BR2_CONFIG}; then
	rm -f ${TARGET_DIR}/usr/lib/libstdc++*
fi

if grep -q "USES_MUSL=y" ${BR2_CONFIG}; then
	ln -sf libc.so ${TARGET_DIR}/lib/ld-uClibc.so.0
	ln -sf ../../lib/libc.so ${TARGET_DIR}/usr/bin/ldd
fi

# Per-variant exclusions. Comments and blank lines are skipped, so a list can
# record *why* a path is safe to drop -- which is the only thing a future reader
# needs from it, and the difference between a considered exclusion and a
# superstition.
LIST="${BR2_EXTERNAL_GENERAL_PATH}/scripts/excludes/${OPENIPC_SOC_MODEL}_${OPENIPC_VARIANT}.list"
if [ -f ${LIST} ]; then
	grep -vE '^[[:space:]]*(#|$)' ${LIST} | xargs -I % rm -f ${TARGET_DIR}%
fi

if [ -f "${LATE_OVERLAY_LIST}" ]; then
	while IFS=: read -r symbol overlay_relpath; do
		[ -n "${symbol}" ] || continue
		case "${symbol}" in
			\#*) continue ;;
		esac

		if grep -q "^${symbol}=y" "${BR2_CONFIG}"; then
			overlay_dir="${BR2_EXTERNAL_GENERAL_PATH}/${overlay_relpath}"
			if [ -d "${overlay_dir}" ]; then
				rsync -a "${overlay_dir}/" "${TARGET_DIR}/"
			fi
		fi
	done < "${LATE_OVERLAY_LIST}"
fi

if [ -f "${LATE_POST_BUILD_HOOKS}" ]; then
	while IFS=: read -r symbol hook_relpath; do
		[ -n "${symbol}" ] || continue
		case "${symbol}" in
			\#*) continue ;;
		esac

		if grep -q "^${symbol}=y" "${BR2_CONFIG}"; then
			hook_script="${BR2_EXTERNAL_GENERAL_PATH}/${hook_relpath}"
			if [ -x "${hook_script}" ]; then
				"${hook_script}" "${TARGET_DIR}"
			fi
		fi
	done < "${LATE_POST_BUILD_HOOKS}"
fi
