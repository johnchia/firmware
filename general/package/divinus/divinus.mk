################################################################################
#
# divinus
#
################################################################################

DIVINUS_SITE = $(call github,openipc,divinus,$(DIVINUS_VERSION))
DIVINUS_VERSION = HEAD
DIVINUS_LICENSE = MIT
DIVINUS_LICENSE_FILES = LICENSE

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	DIVINUS_OPTIONS = "-rdynamic -s -Os -lm"
else
	DIVINUS_OPTIONS = "-rdynamic -s -Os"
endif

define DIVINUS_BUILD_CMDS
	$(MAKE) CC=$(TARGET_CC) OPT=$(DIVINUS_OPTIONS) -C $(@D)/src
endef

define DIVINUS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(@D)/divinus.yaml

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/divinus
endef

# Majestic normally owns the small Infinity6E library subset, so install the
# complete vendor bundle here without changing any other SigmaStar image.
ifeq ($(OPENIPC_SOC_MODEL)-$(OPENIPC_VARIANT),ssc30kq-ultimate)
DIVINUS_DEPENDENCIES += sigmastar-osdrv-infinity6e

define DIVINUS_INSTALL_SSC30KQ_ULTIMATE_RUNTIME
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib \
		$(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/lib/*
	$(INSTALL) -m 755 $(DIVINUS_PKGDIR)/files/divinus \
		$(TARGET_DIR)/etc/init.d/divinus
endef
DIVINUS_POST_INSTALL_TARGET_HOOKS += DIVINUS_INSTALL_SSC30KQ_ULTIMATE_RUNTIME
endif

$(eval $(generic-package))
