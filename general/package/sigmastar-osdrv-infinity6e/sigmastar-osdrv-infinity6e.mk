################################################################################
#
# sigmastar-osdrv-infinity6e
#
################################################################################

SIGMASTAR_OSDRV_INFINITY6E_VERSION =
SIGMASTAR_OSDRV_INFINITY6E_SITE =
SIGMASTAR_OSDRV_INFINITY6E_LICENSE = MIT
SIGMASTAR_OSDRV_INFINITY6E_LICENSE_FILES = LICENSE

define SIGMASTAR_OSDRV_INFINITY6E_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/4.9.84/sigmastar
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/4.9.84/sigmastar $(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/kmod/*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/firmware
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/firmware $(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/sensor/firmware/*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensors
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensors $(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/sensor/configs/$(if $(OPENIPC_SNS_MODEL),$(OPENIPC_SNS_MODEL),*).bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/script/*
endef

define SIGMASTAR_OSDRV_INFINITY6E_LIBRARIES
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/lib/*
endef

# The same guard as the Infinity6C package, and wrong for the same reason:
# general/package/majestic installs a binary, a yaml and an init script, and no
# libraries, so gating these on its absence leaves an image carrying both
# Majestic and Raptor with no MI libraries at all. That cost a debugging session
# on ssc377qe -- see the long note in sigmastar-osdrv-infinity6c.mk.
#
# It does not bite ssc30kq today, because that defconfig carries no Majestic and
# so takes the first branch. Fixed here anyway: the trap is that selecting
# Majestic on this SoC would silently remove Raptor's pipeline, with a build
# that succeeds and a camera that has no video.
ifneq ($(BR2_PACKAGE_MAJESTIC),y)
SIGMASTAR_OSDRV_INFINITY6E_POST_INSTALL_TARGET_HOOKS += SIGMASTAR_OSDRV_INFINITY6E_LIBRARIES
else ifeq ($(BR2_PACKAGE_RAPTOR_STREAMING),y)
SIGMASTAR_OSDRV_INFINITY6E_POST_INSTALL_TARGET_HOOKS += SIGMASTAR_OSDRV_INFINITY6E_LIBRARIES
endif

$(eval $(generic-package))
