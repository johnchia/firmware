################################################################################
#
# divinus
#
################################################################################

DIVINUS_SITE = $(call github,openipc,divinus,$(DIVINUS_VERSION))
DIVINUS_VERSION = HEAD
DIVINUS_LICENSE = MIT
DIVINUS_LICENSE_FILES = LICENSE

# A developer checkout can contain products from a direct make invocation.
# Never copy those into Buildroot's clean override source tree.
DIVINUS_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = --exclude divinus --exclude '*.o'

# Keep the tested camera-specific streaming changes confined to the ssc30kq
# Divinus images. All other targets continue to build the OpenIPC source.
ifneq ($(filter ssc30kq-ultimate ssc30kq-divinus,$(OPENIPC_SOC_MODEL)-$(OPENIPC_VARIANT)),)
DIVINUS_SITE = $(call github,johnchia,divinus,$(DIVINUS_VERSION))
# johnchia/divinus master, hardware-verified on ssc30kq. This is the commit the
# staged Compy packaging below was waiting for: it carries the Compy + libevent
# RTSP rewrite and the three teardown fixes that followed it -- the double
# client_unregister() race (3207fe4), draining in-flight encoder sends before
# freeing the event base (52c2839), and the shutdown handle use-after-free
# inherited from upstream (94c7021).
DIVINUS_VERSION = 94c7021424672be65363c4ebee1a6a0e9c459a2e
DIVINUS_DEPENDENCIES += sigmastar-osdrv-infinity6e

# Compy (RTSP/RTP/SDP) plus its libevent-openipc event loop. Required to build
# the pinned Divinus above -- rtsp/rtsp.c and rtsp/compy_libevent.c include
# compy.h, so without these the package fails to compile rather than silently
# losing a feature. See general/package/compy.
DIVINUS_DEPENDENCIES += compy libevent-openipc
DIVINUS_SSC30KQ_RTSP_LIBS = -lcompy -levent_core -levent_pthreads
else
define DIVINUS_APPLY_CONFIG_COMPAT_PATCH
	$(APPLY_PATCHES) $(@D) $(DIVINUS_PKGDIR)/files/patches \
		0003-config-allow-omitted-web-whitelist.patch
endef
DIVINUS_POST_PATCH_HOOKS += DIVINUS_APPLY_CONFIG_COMPAT_PATCH
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	DIVINUS_OPTIONS = "-rdynamic -s -Os -lm $(DIVINUS_SSC30KQ_RTSP_LIBS)"
else
	DIVINUS_OPTIONS = "-rdynamic -s -Os $(DIVINUS_SSC30KQ_RTSP_LIBS)"
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
