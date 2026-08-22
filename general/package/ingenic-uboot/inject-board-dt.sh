#!/bin/sh
# Append this board's SD-slot and reset-button GPIOs to a U-Boot leaf .dts.
#
# The Ingenic U-Boot device tree is per-SoC while these lines are per-board, so
# they cannot live in the shared .dts and are appended to the build copy here
# instead. Getting them wrong is not cosmetic: without vmmc-supply and cd-gpios
# the MMC core never powers or detects the slot, `fatload mmc 0:1` fails, and
# the bootloader's SD-card recovery path -- the only way back into a camera with
# no Ethernet and no serial header -- silently does nothing.
#
# Numeric gpio flags are emitted (ACTIVE_LOW=1, PULL_UP=0x10) so the fragment
# needs no dt-bindings include; not every SoC .dts pulls in gpio.h.
#
# Usage: inject-board-dt.sh <leaf.dts> <mmc_cd> <mmc_power> <power_active_low> <button_reset>
#        A gpio of -1, or empty, skips that node.
set -e

DTS="$1"
CD="${2:--1}"
PWR="${3:--1}"
AL="${4:-0}"
BTN="${5:--1}"

[ -f "$DTS" ] || exit 0
for v in CD PWR BTN; do
	eval "[ -n \"\$$v\" ] || $v=-1"
done

# gpio number -> bank label letter (PA=a .. PE=e); empty if out of range
bank() {
	case $(( $1 / 32 )) in
	0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

# ---- vmmc-supply: slot power ----------------------------------------------
if [ "$PWR" -ge 0 ] && ! grep -q 'vmmc-supply' "$DTS"; then
	PB=$(bank "$PWR")
	if [ -n "$PB" ]; then
		if [ "$AL" = 1 ]; then POL=1; EAH=0; else POL=0; EAH=1; fi
		{
			printf '\n/ {\t/* MMC slot power, board gpio %s */\n' "$PWR"
			printf '\tvcc_mmc: regulator-mmc {\n'
			printf '\t\tcompatible = "regulator-fixed";\n'
			printf '\t\tregulator-name = "mmc-vcc";\n'
			printf '\t\tgpio = <&gp%s %s %s>;\n' "$PB" "$(( PWR % 32 ))" "$POL"
			[ "$EAH" = 1 ] && printf '\t\tenable-active-high;\n'
			printf '\t\tstartup-delay-us = <100000>;\n'
			printf '\t};\n};\n&msc0 {\n\tvmmc-supply = <&vcc_mmc>;\n};\n'
		} >> "$DTS"
		echo "U-Boot: injected vmmc-supply = <&gp$PB $(( PWR % 32 ))> (gpio $PWR)"
	fi
fi

# ---- cd-gpios: card detect -------------------------------------------------
# The PULL_UP flag is honoured by the gpio driver's set_flags from T31 on.
if [ "$CD" -ge 0 ] && ! grep -q 'cd-gpios' "$DTS"; then
	CB=$(bank "$CD")
	if [ -n "$CB" ]; then
		{
			printf '\n&msc0 {\t/* MMC card-detect, board gpio %s */\n' "$CD"
			printf '\t/delete-property/ broken-cd;\n'
			printf '\tcd-gpios = <&gp%s %s 0x11>;\t/* GPIO_ACTIVE_LOW | GPIO_PULL_UP */\n' "$CB" "$(( CD % 32 ))"
			printf '};\n'
		} >> "$DTS"
		echo "U-Boot: injected cd-gpios = <&gp$CB $(( CD % 32 ))> (gpio $CD)"
	fi
fi

# ---- gpio-keys: factory-reset button --------------------------------------
# CONFIG_BUTTON_CMD reads the button labelled "reset" once early in main_loop
# and runs button_cmd_0 if it is held.
if [ "$BTN" -ge 0 ] && ! grep -q 'gpio-keys' "$DTS"; then
	BB=$(bank "$BTN")
	if [ -n "$BB" ]; then
		{
			printf '\n/ {\t/* factory-reset button, board gpio %s */\n' "$BTN"
			printf '\tgpio-keys {\n'
			printf '\t\tcompatible = "gpio-keys";\n'
			printf '\t\treset {\n'
			printf '\t\t\tlabel = "reset";\n'
			printf '\t\t\tgpios = <&gp%s %s 0x11>;\t/* GPIO_ACTIVE_LOW | GPIO_PULL_UP */\n' "$BB" "$(( BTN % 32 ))"
			printf '\t\t\tlinux,code = <0x198>;\t/* KEY_RESTART */\n'
			printf '\t\t};\n'
			printf '\t};\n'
			printf '};\n'
		} >> "$DTS"
		echo "U-Boot: injected gpio-keys reset = <&gp$BB $(( BTN % 32 ))> (gpio $BTN)"
	fi
fi
exit 0
