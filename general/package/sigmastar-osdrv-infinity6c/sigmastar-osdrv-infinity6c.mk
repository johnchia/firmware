################################################################################
#
# sigmastar-osdrv-infinity6c
#
################################################################################

SIGMASTAR_OSDRV_INFINITY6C_VERSION =
SIGMASTAR_OSDRV_INFINITY6C_SITE =
SIGMASTAR_OSDRV_INFINITY6C_LICENSE = MIT
SIGMASTAR_OSDRV_INFINITY6C_LICENSE_FILES = LICENSE

define SIGMASTAR_OSDRV_INFINITY6C_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/5.10.61/sigmastar
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/5.10.61/sigmastar $(SIGMASTAR_OSDRV_INFINITY6C_PKGDIR)/files/kmod/*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/firmware
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/firmware $(SIGMASTAR_OSDRV_INFINITY6C_PKGDIR)/files/sensor/firmware/*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensors
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensors $(SIGMASTAR_OSDRV_INFINITY6C_PKGDIR)/files/sensor/configs/$(if $(OPENIPC_SNS_MODEL),$(OPENIPC_SNS_MODEL),*).bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(SIGMASTAR_OSDRV_INFINITY6C_PKGDIR)/files/script/*
endef

define SIGMASTAR_OSDRV_INFINITY6C_LIBRARIES
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(SIGMASTAR_OSDRV_INFINITY6C_PKGDIR)/files/lib/*
endef

# WHO INSTALLS THE MI LIBRARIES
#
# The first condition below reads "Majestic brings its own copies, so skip
# ours". That is not true of this tree: general/package/majestic installs the
# binary, majestic.yaml and S95majestic, and no libraries at all. So an image
# selecting both Majestic and Raptor got the MI libraries from nowhere, and
# Raptor's HAL -- which dlopens them by name -- died at
#
#   i6c_sys: dlopen(libcam_os_wrapper.so) failed: No such file or directory
#   HAL init failed: -2
#
# ssc377qe_raptor is exactly that image, and it had been running only because an
# incremental build left the libraries in target/ from before Majestic was
# selected. The first clean rebuild dropped them and the camera came up with no
# pipeline. Nothing failed at build time, because a dlopen by name cannot be a
# link error -- the image builds, boots, and has no video.
#
# Raptor therefore asks for them on its own account rather than relying on
# Majestic's absence. There is nothing to collide with: Majestic installs no
# libraries, so this cannot overwrite one of its.
ifneq ($(BR2_PACKAGE_MAJESTIC),y)
SIGMASTAR_OSDRV_INFINITY6C_POST_INSTALL_TARGET_HOOKS += SIGMASTAR_OSDRV_INFINITY6C_LIBRARIES
else ifeq ($(BR2_PACKAGE_RAPTOR_STREAMING),y)
SIGMASTAR_OSDRV_INFINITY6C_POST_INSTALL_TARGET_HOOKS += SIGMASTAR_OSDRV_INFINITY6C_LIBRARIES
endif

$(eval $(generic-package))
