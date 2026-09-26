#!/bin/bash
# The rules a camera directory keeps: br-ext-chip-<vendor>/cameras/<camera>/.
#
# A camera is a fragment (camera.conf) layered on an SoC defconfig by
# general/cameras.mk, plus at most a raptor.conf partial, a baked U-Boot
# environment, an add-only overlay and a README. Four rules keep that from
# turning back into what OpenIPC/builder does -- a copied defconfig and shared
# files pasted over the tree, once per device -- and each is checked here so
# that drift is a test failure rather than a review comment:
#
#   1. camera.conf sets camera-level symbols only. The allowlist is ALLOWED
#      below; extending it is a reviewed change. A fragment that wants a
#      kernel config, a toolchain or a variant is an SoC target in disguise.
#   2. The overlay only adds files: a path that also exists in general/overlay
#      or the family overlay is refused, and so is customizer.sh by name.
#   3. The camera names its base, in the same vendor tree, and the base exists.
#      The name itself is <identity>_<soc>_<sensor>_<radio>, and the SoC and
#      sensor fields have to agree with the base and the fragment.
#   4. camera.conf is sorted, so two cameras diff.
#
# Pure shell, no build. Run from the repository root; --self-test proves each
# rule fires on a fixture tree.
set -u

fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }

# Rule 1. Camera facts: the two camera symbols, the sensor pin, the rootfs
# size for a camera whose flash differs from its base's, the env image trio,
# the pins the Ingenic bootloader takes as symbols, the supplicant group, and
# the WiFi drivers this tree carries.
ALLOWED='^BR2_(OPENIPC_(CAMERA|CAMERA_BASE|SNS_MODEL|ROOTFS_PART_KB)|PACKAGE_(HOST_UBOOT_TOOLS_ENVIMAGE(_SIZE|_SOURCE)?|HISILICON_CV6XX_BOOT_REGS|WIRELESS_TOOLS|WPA_SUPPLICANT(_[A-Z0-9_]+)?|INGENIC_UBOOT_GPIO_[A-Z0-9_]+|RTL[0-9A-Z]+_OPENIPC|RTL8812AU|ATBM60XX(_[A-Z0-9_]+)?|ATBM_WIFI|AIC8800_OPENIPC|MT7601U_OPENIPC|SSV6[0-9A-Z]+_OPENIPC|TXW8301_OPENIPC|WQ9001))=(y|"[^"]*")$'
# Rule 2. Refused by name wherever they sit in the overlay.
REFUSED_FILES='customizer.sh'
# Rule 3. Hyphens are allowed inside the identity and nowhere else, so the
# name splits back into its four fields on underscores.
NAME='^[a-z0-9][a-z0-9-]*_[a-z0-9]+_[a-z0-9]+_[a-z0-9]+$'
# What a camera directory may hold.
MEMBERS='camera.conf raptor.conf uboot.env.txt boot-regs.txt overlay README.md'

value() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$2" | head -1; }

check_camera() {  # <root> <camera dir>
	local root=$1 dir=$2 name=${2##*/} vendor_dir conf base base_conf soc sensor family lines line f rel
	vendor_dir=${dir%/cameras/*}
	conf=$dir/camera.conf
	[ -f "$conf" ] || { bad "$name: has no camera.conf"; return; }
	[ -f "$dir/README.md" ] || bad "$name: has no README.md (where the pins came from, what is verified)"
	for f in "$dir"/* "$dir"/.[!.]*; do
		[ -e "$f" ] || continue
		case " $MEMBERS " in *" ${f##*/} "*) ;; *) bad "$name: carries ${f##*/}; a camera holds only: $MEMBERS" ;; esac
	done

	[[ $name =~ $NAME ]] || bad "$name: not <identity>_<soc>_<sensor>_<radio> (identity may carry hyphens, nothing else may)"

	lines=$(grep -v '^[[:space:]]*#' "$conf" | grep -v '^[[:space:]]*$')
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[[ $line =~ $ALLOWED ]] || bad "$name: camera.conf sets '$line', which is an SoC or variant fact; it belongs in the base, or this camera wants another base"
	done <<<"$lines"
	printf '%s\n' "$lines" | LC_ALL=C sort -c 2>/dev/null || bad "$name: camera.conf is not sorted (LC_ALL=C sort)"

	[ "$(value BR2_OPENIPC_CAMERA "$conf")" = "$name" ] || bad "$name: BR2_OPENIPC_CAMERA is not the directory's name"
	base=$(value BR2_OPENIPC_CAMERA_BASE "$conf")
	[ -n "$base" ] || { bad "$name: no BR2_OPENIPC_CAMERA_BASE"; return; }
	base_conf=$vendor_dir/configs/${base}_defconfig
	[ -f "$base_conf" ] || { bad "$name: base '$base' has no ${vendor_dir##*/}/configs/${base}_defconfig"; return; }
	IFS=_ read -r _ soc sensor _ <<<"$name"
	[ "$(value BR2_OPENIPC_SOC_MODEL "$base_conf")" = "$soc" ] || bad "$name: SoC field '$soc' is not the base's BR2_OPENIPC_SOC_MODEL"
	[ "$(value BR2_OPENIPC_SNS_MODEL "$conf")" = "$sensor" ] || bad "$name: sensor field '$sensor' is not the fragment's BR2_OPENIPC_SNS_MODEL"
	family=$(value BR2_OPENIPC_SOC_FAMILY "$base_conf")

	if [ -d "$dir/overlay" ]; then
		while IFS= read -r f; do
			rel=${f#"$dir/overlay/"}
			case " $REFUSED_FILES " in *" ${f##*/} "*) bad "$name: overlay ships ${f##*/}; a camera never ships a script" ;; esac
			[ -e "$root/general/overlay/$rel" ] && bad "$name: overlay/$rel shadows general/overlay/$rel"
			[ -n "$family" ] && [ -e "$vendor_dir/board/$family/overlay/$rel" ] && bad "$name: overlay/$rel shadows board/$family/overlay/$rel"
		done < <(find "$dir/overlay" -type f -o -type l)
	fi

	if [ -f "$dir/raptor.conf" ]; then
		while IFS= read -r line; do
			case "$line" in
				'' | '#'* | ' '* | '	'*) ;;
				'['*']') ;;
				*=*) [[ ${line%%=*} =~ ^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*$ ]] || bad "$name: raptor.conf: bad key in '$line'" ;;
				*) bad "$name: raptor.conf: '$line' is not a [section] or key = value line" ;;
			esac
		done < "$dir/raptor.conf"
	fi
}

check_tree() {  # <root>
	local root=$1 dir n=0
	for dir in "$root"/br-ext-chip-*/cameras/*; do
		[ -d "$dir" ] || continue
		n=$((n + 1))
		check_camera "$root" "$dir"
	done
	echo "checked $n camera director$( [ "$n" -eq 1 ] && echo y || echo ies )"
}

# --- self-test: each rule fires on a fixture ------------------------------
self_test() {
	local tmp good
	tmp=$(mktemp -d)
	# Expanded now: the trap runs after this function's locals are gone.
	trap "rm -rf '$tmp'" EXIT
	good=$tmp/good
	mkdir -p "$good/general/overlay/etc" "$good/br-ext-chip-x/configs" "$good/br-ext-chip-x/board/fam/overlay/etc"
	: > "$good/general/overlay/etc/passwd"
	: > "$good/br-ext-chip-x/board/fam/overlay/etc/fw_env.config"
	printf 'BR2_OPENIPC_SOC_VENDOR="x"\nBR2_OPENIPC_SOC_MODEL="soc"\nBR2_OPENIPC_SOC_FAMILY="fam"\n' > "$good/br-ext-chip-x/configs/soc_raptor_defconfig"
	local cam=$good/br-ext-chip-x/cameras/cam-1_soc_sns_radio
	mkdir -p "$cam/overlay/etc"
	cat > "$cam/camera.conf" <<-'EOF'
	# a comment
	BR2_OPENIPC_CAMERA="cam-1_soc_sns_radio"
	BR2_OPENIPC_CAMERA_BASE="soc_raptor"
	BR2_OPENIPC_SNS_MODEL="sns"
	BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE=y
	BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SIZE="0x10000"
	BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SOURCE="$(OPENIPC_CAMERA_DIR)/uboot.env.txt"
	BR2_PACKAGE_RTL8192EU_OPENIPC=y
	BR2_PACKAGE_WPA_SUPPLICANT=y
	EOF
	printf '[ircut]\ngpio_ircut = 1\n' > "$cam/raptor.conf"
	printf 'wlandev=x\n' > "$cam/uboot.env.txt"
	printf '# cam\n' > "$cam/README.md"
	: > "$cam/overlay/etc/extra"

	local out; out=$(check_tree "$good")
	if echo "$out" | grep -q '^FAIL'; then bad "self-test: the good fixture fails:"; echo "$out" | sed 's/^/     /'; else ok "self-test: a well-formed camera passes"; fi

	# Each mutation of the good tree must produce a FAIL line with the phrase.
	local case_no=0
	mutate() {  # <what> <phrase> <shell to apply under $t>
		local what=$1 phrase=$2 t=$tmp/case$((++case_no)) c
		cp -r "$good" "$t"
		c=$t/br-ext-chip-x/cameras/cam-1_soc_sns_radio
		(cd "$t" && c=$c eval "$3")
		out=$(check_tree "$t")
		if echo "$out" | grep '^FAIL' | grep -q -- "$phrase"; then ok "self-test: $what is refused"
		else bad "self-test: $what was not refused (wanted '$phrase')"; echo "$out" | sed 's/^/     /'; fi
	}
	mutate "a variant or SoC symbol"   "SoC or variant fact"      'echo "BR2_TARGET_UBOOT=y" >> "$c/camera.conf"'
	mutate "a kernel config line"      "SoC or variant fact"      'echo "BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=\"x\"" >> "$c/camera.conf"'
	mutate "an unsorted fragment"      "not sorted"               'printf "BR2_PACKAGE_WIRELESS_TOOLS=y\nBR2_PACKAGE_ATBM60XX=y\n" >> "$c/camera.conf"'
	mutate "a shadowing overlay file"  "shadows general/overlay"  'mkdir -p "$c/overlay/etc"; : > "$c/overlay/etc/passwd"'
	mutate "a family overlay shadow"   "shadows board/fam/overlay" 'mkdir -p "$c/overlay/etc"; : > "$c/overlay/etc/fw_env.config"'
	mutate "a customizer script"       "never ships a script"     'mkdir -p "$c/overlay/etc"; : > "$c/overlay/etc/customizer.sh"'
	mutate "a missing base"            "has no br-ext-chip-x/configs" 'sed -i "s/soc_raptor/other_raptor/" "$c/camera.conf"'
	mutate "a name with an underscore in the identity" "not <identity>_<soc>" 'mv "$c" "${c%/*}/cam_1_soc_sns_radio"; sed -i "s/cam-1_soc_sns_radio/cam_1_soc_sns_radio/" "${c%/*}/cam_1_soc_sns_radio/camera.conf"'
	mutate "a wrong SoC field"         "not the base"             'mv "$c" "${c%/*}/cam-1_other_sns_radio"; sed -i "s/cam-1_soc_sns_radio/cam-1_other_sns_radio/" "${c%/*}/cam-1_other_sns_radio/camera.conf"'
	mutate "a sensor field the fragment does not pin" "not the fragment" 'sed -i "s/SNS_MODEL=\"sns\"/SNS_MODEL=\"other\"/" "$c/camera.conf"'
	mutate "a camera symbol naming another directory" "not the directory" 'sed -i "s/CAMERA=\"cam-1_soc_sns_radio\"/CAMERA=\"cam-2_soc_sns_radio\"/" "$c/camera.conf"'
	mutate "a directory with no camera.conf" "no camera.conf"    'mkdir -p "${c%/*}/cam-2_soc_sns_radio"'
	mutate "a stray file"              "holds only"               ': > "$c/notes.txt"'
	mutate "a raptor.conf line that parses as nothing" "not a \[section\] or key" 'echo "gpio_ircut 1" >> "$c/raptor.conf"'
	mutate "a missing README"          "no README.md"             'rm "$c/README.md"'
}

case "${1:-}" in
	--self-test) self_test ;;
	*)
		[ -d general/overlay ] || { echo "run me from the repository root"; exit 1; }
		check_tree . ;;
esac

if [ "$fail" -ne 0 ]; then echo "$fail failure(s)"; exit 1; fi
echo "all camera checks passed"
