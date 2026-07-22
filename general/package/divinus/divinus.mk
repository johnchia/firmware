################################################################################
#
# divinus
#
################################################################################

DIVINUS_SITE = $(call github,openipc,divinus,$(DIVINUS_VERSION))
DIVINUS_VERSION = HEAD
DIVINUS_LICENSE = MIT
DIVINUS_LICENSE_FILES = LICENSE

# Keep the tested camera-specific streaming changes confined to the ssc30kq
# Divinus images. All other targets continue to build the OpenIPC source.
ifneq ($(filter ssc30kq-ultimate ssc30kq-divinus,$(OPENIPC_SOC_MODEL)-$(OPENIPC_VARIANT)),)
DIVINUS_SITE = $(call github,johnchia,divinus,$(DIVINUS_VERSION))
DIVINUS_VERSION = 849f4e5bf7cecb3f9d54e4be9581347f05268129
DIVINUS_DEPENDENCIES += sigmastar-osdrv-infinity6e
else
define DIVINUS_APPLY_CONFIG_COMPAT_PATCH
	$(APPLY_PATCHES) $(@D) $(DIVINUS_PKGDIR)/files/patches \
		0003-config-allow-omitted-web-whitelist.patch
endef
DIVINUS_POST_PATCH_HOOKS += DIVINUS_APPLY_CONFIG_COMPAT_PATCH
endif

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
define DIVINUS_INSTALL_SSC30KQ_ULTIMATE_RUNTIME
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib \
		$(SIGMASTAR_OSDRV_INFINITY6E_PKGDIR)/files/lib/*
	$(INSTALL) -m 755 $(DIVINUS_PKGDIR)/files/divinus \
		$(TARGET_DIR)/etc/init.d/divinus
endef
DIVINUS_POST_INSTALL_TARGET_HOOKS += DIVINUS_INSTALL_SSC30KQ_ULTIMATE_RUNTIME
endif

# The Majestic-free target uses Divinus as its normal boot-time camera daemon.
# The OSDRV package installs its full library bundle automatically when
# Majestic is not selected.
ifeq ($(OPENIPC_SOC_MODEL)-$(OPENIPC_VARIANT),ssc30kq-divinus)
define DIVINUS_INSTALL_SSC30KQ_SERVICE
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 $(DIVINUS_PKGDIR)/files/divinus \
		$(TARGET_DIR)/etc/init.d/S95divinus
endef
DIVINUS_POST_INSTALL_TARGET_HOOKS += DIVINUS_INSTALL_SSC30KQ_SERVICE
endif

$(eval $(generic-package))
