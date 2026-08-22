################################################################################
#
# atbm60xx
#
################################################################################

ATBM60XX_SITE = $(call github,openipc,atbm_60xx,$(ATBM60XX_VERSION))
ATBM60XX_VERSION = HEAD

# THE RADIO NEEDS A FIRMWARE FILE, AND THIS PACKAGE SHIPPED NONE
#
# `atbm_get_hw_type` in hal_apollo/fwio.c returns FIRMWARE_DEFAULT_PATH and
# nothing else -- the chip-version switch that would pick a per-part name is
# inside `#if 0` -- and with CONFIG_FW_NAME undefined that string is the bare
# "fw.bin". So the driver calls request_firmware() for /lib/firmware/fw.bin on
# every probe. The other build, which compiles the blob into the module through
# CONFIG_USE_FW_H, is not what this package selects and nothing here defines
# that symbol.
#
# Without the file the module loads, the probe fails and the interface never
# appears. On a camera whose only interface is that radio -- the Wyze v3 has no
# Ethernet PHY -- that is indistinguishable from a bad flash, and there is no
# console to tell the difference.
#
# The blobs are in the driver's own source tree, one per bus. Both are "Ares B",
# which is the family 603x belongs to; there is none here for 601x, 602x or
# 6041, so those models get no file and behave as before rather than getting a
# firmware for a different part.
ifeq ($(BR2_PACKAGE_ATBM60XX_INTERFACE_SDIO),y)
ATBM60XX_FIRMWARE = Ares_B_Chip_IPC_SDIO_svn14195_24M_6031_6031B.bin
endif
ifeq ($(BR2_PACKAGE_ATBM60XX_INTERFACE_USB),y)
ATBM60XX_FIRMWARE = Ares_B_Chip_NVR_IPC_USB_svn14195_24M_6012B_6032.bin
endif

ifneq ($(ATBM60XX_FIRMWARE),)
define ATBM60XX_INSTALL_FIRMWARE
	$(INSTALL) -D -m 644 $(@D)/firmware/$(ATBM60XX_FIRMWARE) \
		$(TARGET_DIR)/lib/firmware/fw.bin
endef
endif

define ATBM60XX_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/atbm60xx_conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/atbm60xx_conf $(ATBM60XX_PKGDIR)/files/*.txt
	$(ATBM60XX_INSTALL_FIRMWARE)
endef

ATBM60XX_MODULE_MAKE_OPTS = KSRC=$(LINUX_DIR)

# Set the module name based on the model and interface type
ATBM60XX_MODEL_NAME =

# Disable all models by default
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM601x=n CONFIG_ATBM602x=n CONFIG_ATBM603x=n CONFIG_ATBM6041=n

# Enable the selected model and set the interface type
ifeq ($(BR2_PACKAGE_ATBM60XX_MODEL_601X),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM601x=y
ATBM60XX_MODEL_NAME = atbm601x_wifi
endif
ifeq ($(BR2_PACKAGE_ATBM60XX_MODEL_602X),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM602x=y
ATBM60XX_MODEL_NAME = atbm602x_wifi
endif
ifeq ($(BR2_PACKAGE_ATBM60XX_MODEL_603X),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM603x=y
ATBM60XX_MODEL_NAME = atbm603x_wifi
endif
ifeq ($(BR2_PACKAGE_ATBM60XX_MODEL_6041),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM6041=y
ATBM60XX_MODEL_NAME = atbm6041_wifi
endif

# Set the interface type
ifeq ($(BR2_PACKAGE_ATBM60XX_INTERFACE_USB),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM_USB_BUS=y CONFIG_ATBM_SDIO_BUS=n
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM_MODULE_NAME="$(ATBM60XX_MODEL_NAME)_usb"
endif
ifeq ($(BR2_PACKAGE_ATBM60XX_INTERFACE_SDIO),y)
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM_USB_BUS=n CONFIG_ATBM_SDIO_BUS=y
ATBM60XX_MODULE_MAKE_OPTS += CONFIG_ATBM_MODULE_NAME="$(ATBM60XX_MODEL_NAME)_sdio"
endif

ATBM60XX_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
