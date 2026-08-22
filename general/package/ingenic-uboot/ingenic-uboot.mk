################################################################################
#
# ingenic-uboot -- per-board device-tree hooks for Buildroot's U-Boot package
#
# Not a package: it builds nothing and installs nothing. It exists so the
# board's SD-slot and reset-button gpios reach the U-Boot device tree, which
# is what makes the bootloader's SD-card recovery path work.
#
# The guard mirrors the one Buildroot itself needs: external.mk is parsed once
# before .config is loaded, when every BR2_ symbol is still empty, so the hook
# must only be registered on the second parse.
#
################################################################################

ifeq ($(BR2_PACKAGE_INGENIC_UBOOT)$(BR_BUILDING),yy)

# Buildroot's UBOOT_COPY_OLD_LICENSE_FILE hook copies COPYING over
# Licenses/gpl-2.0.txt "prior to u-boot 2013.10, [when] the license info was in
# COPYING". Mainline reversed that years ago: Licenses/gpl-2.0.txt is the real
# file and COPYING is a symlink to it, so install refuses -- "are the same
# file" -- and the extract step fails before anything is compiled. Dropping the
# hook loses nothing; legal-info reads Licenses/gpl-2.0.txt either way. This
# external is included last (buildroot/Makefile line 545, after boot/common.mk),
# so the override wins.
UBOOT_COPY_OLD_LICENSE_FILE =

INGENIC_UBOOT_INJECT = $(BR2_EXTERNAL_GENERAL_PATH)/package/ingenic-uboot/inject-board-dt.sh

define INGENIC_UBOOT_INJECT_BOARD_DT
	@DT=$$(sed -n 's/^CONFIG_DEFAULT_DEVICE_TREE="\(.*\)"/\1/p' $(@D)/.config); \
	if [ -z "$$DT" ]; then \
		echo "ingenic-uboot: no CONFIG_DEFAULT_DEVICE_TREE in the U-Boot .config" >&2; \
		exit 1; \
	fi; \
	if [ ! -f $(@D)/arch/mips/dts/$$DT.dts ]; then \
		echo "ingenic-uboot: arch/mips/dts/$$DT.dts not found" >&2; \
		exit 1; \
	fi; \
	$(INGENIC_UBOOT_INJECT) $(@D)/arch/mips/dts/$$DT.dts \
		$(call qstrip,$(BR2_PACKAGE_INGENIC_UBOOT_GPIO_MMC_CD)) \
		$(call qstrip,$(BR2_PACKAGE_INGENIC_UBOOT_GPIO_MMC_POWER)) \
		$(if $(BR2_PACKAGE_INGENIC_UBOOT_GPIO_MMC_POWER_ACTIVE_LOW),1,0) \
		$(call qstrip,$(BR2_PACKAGE_INGENIC_UBOOT_GPIO_BUTTON_RESET))
endef
UBOOT_PRE_BUILD_HOOKS += INGENIC_UBOOT_INJECT_BOARD_DT

endif
