#!/bin/sh
#
# Assemble a whole-flash image for the Hi3516CV6xx from the pieces the build
# already produced, plus the boot container: built here by hisilicon-cv6xx-boot
# for the targets on OpenIPC's U-Boot, taken off the part for the OEM ones.
#
# WHY THIS IS NOT make_full_image_hisilicon.sh. That one is for gen4: it writes
# its own environment with mkenvimage and spells the gen4 partition table into
# it. On cv6xx the environment is a build artifact of its own -- the board
# defconfig points BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SOURCE at a text file
# and Buildroot emits images/uboot-env.bin -- so the table is already decided
# before this script runs, and restating it here would be a second copy free to
# disagree with the one the camera actually boots.
#
# So the layout is READ BACK OUT of that environment image. Whatever mtdparts
# the camera will boot with is what this script partitions to, and a mismatch
# becomes impossible rather than merely unlikely.
#
# WHAT IS DELIBERATELY LEFT OUT. Trailing partitions with no build artifact are
# not written and the image stops before them, so a per-unit partition survives
# a full flash. On this family that is devinfo, which carries the encrypted
# device identity: baking one board's copy into an image that gets flashed to
# another is how a fleet ends up sharing an identity. rootfs_data drops out by
# the same rule, and that is wanted twice over: the image stays smaller, and a
# reflash leaves the overlay of a camera that has already been configured
# intact. Anything stale there is handled at boot -- general/overlay/init
# mounts it jffs2 and runs flash_eraseall when the magic is not found.
set -eu

UBOOT=$1
IMAGES=$2
OUT=$3

ENV_BIN=$IMAGES/uboot-env.bin
FIT=$IMAGES/fitImage
ROOTFS=$IMAGES/rootfs.squashfs
# repack renames it rootfs.squashfs.<soc> once the build has finished, which is
# when fullimage runs; there is one per images directory.
if [ ! -f "$ROOTFS" ]; then
	for f in "$IMAGES"/rootfs.squashfs.*; do
		case $f in *.md5sum) ;; *) [ -f "$f" ] && ROOTFS=$f ;; esac
	done
fi

for f in "$UBOOT" "$ENV_BIN" "$FIT" "$ROOTFS"; do
	[ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

# The environment is stored with a 4-byte CRC in front, so the body is just
# NUL-separated key=value and strings finds it. OpenIPC's environment keeps the
# table in a variable of its own, mtdparts=${mtdids}:<table>, and builds
# bootargs from it; the OEM-table environment spells it inside bootargs. Take
# the variable when there is one, since bootargs then only names it, and take
# only up to the next space so a trailing bootarg is not swallowed.
MTDPARTS=$(strings -n 8 "$ENV_BIN" | sed -n 's/^mtdparts=[^:]*:\([^ ]*\).*/\1/p' | head -1)
[ -n "$MTDPARTS" ] || MTDPARTS=$(strings -n 8 "$ENV_BIN" \
	| sed -n 's/.*mtdparts=[^:]*:\([^ ]*\).*/\1/p' | head -1)
[ -n "$MTDPARTS" ] || { echo "no mtdparts= in $ENV_BIN" >&2; exit 1; }
echo "- layout from $ENV_BIN"
echo "-   $MTDPARTS"

# name -> file for the partitions that have one. Everything else is a hole.
part_file() {
	case $1 in
		boot|uboot) echo "$UBOOT" ;;
		env)    echo "$ENV_BIN" ;;
		kernel) echo "$FIT" ;;
		rootfs) echo "$ROOTFS" ;;
		*)      echo "" ;;
	esac
}

# A size in K or M, or '-' for the rest of the chip, which needs FLASH_KB.
# Entries placed with @ (OpenIPC's firmware, which spans kernel and rootfs)
# overlap others and hold nothing of their own; the loops skip them.
part_kb() {
	case $1 in
		*K|*k) echo "${1%[Kk]}" ;;
		*M|*m) echo $(( ${1%[Mm]} * 1024 )) ;;
		-) [ -n "${FLASH_KB:-}" ] || { echo "'-' partition needs FLASH_KB" >&2; exit 1; }
		   echo $(( FLASH_KB - $2 )) ;;
		*) echo "cannot parse size '$1'" >&2; exit 1 ;;
	esac
}

# Pass one: where does the image end? Trailing partitions with no artifact are
# dropped, so devinfo is never written; a hole in the middle (rootfs_data) is.
TOTAL=0
END=0
OIFS=$IFS; IFS=,
for p in $MTDPARTS; do
	sz=${p%%(*}; name=${p#*(}; name=${name%)*}
	case $sz in *@*) continue ;; esac
	kb=$(part_kb "$sz" "$TOTAL")
	TOTAL=$(( TOTAL + kb ))
	[ -n "$(part_file "$name")" ] && END=$TOTAL
done
IFS=$OIFS

echo "- chip $TOTAL KB, image $END KB (trailing per-unit partitions left unwritten)"

# Erase pattern, not zeros: this is what unwritten NOR reads as, and it is what
# lets /init tell a virgin rootfs_data from a formatted one.
dd if=/dev/zero bs=1024 count="$END" status=none | tr '\000' '\377' > "$OUT"

OFF=0
OIFS=$IFS; IFS=,
for p in $MTDPARTS; do
	sz=${p%%(*}; name=${p#*(}; name=${name%)*}
	case $sz in *@*) continue ;; esac
	kb=$(part_kb "$sz" "$OFF")
	f=$(part_file "$name")
	if [ -n "$f" ]; then
		bytes=$(wc -c < "$f")
		if [ "$bytes" -gt $(( kb * 1024 )) ]; then
			echo "- $name: $(( bytes / 1024 ))KB does not fit ${kb}KB" >&2
			exit 1
		fi
		dd if="$f" of="$OUT" bs=1024 seek="$OFF" conv=notrunc status=none
		printf -- "- %-12s @ 0x%06X  %6d KB of %6d KB\n" \
			"$name" $(( OFF * 1024 )) $(( (bytes + 1023) / 1024 )) "$kb"
	else
		printf -- "- %-12s @ 0x%06X  %6s    %6d KB\n" \
			"$name" $(( OFF * 1024 )) "erased" "$kb"
	fi
	OFF=$(( OFF + kb ))
	[ "$OFF" -ge "$END" ] && break
done
IFS=$OIFS

echo "- image: $OUT ($(wc -c < "$OUT") bytes)"
