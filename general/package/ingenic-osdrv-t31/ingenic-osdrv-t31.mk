################################################################################
#
# ingenic-osdrv-t31
#
################################################################################

INGENIC_OSDRV_T31_VERSION =
INGENIC_OSDRV_T31_SITE =
INGENIC_OSDRV_T31_LICENSE = MIT
INGENIC_OSDRV_T31_LICENSE_FILES = LICENSE

# The vendor libraries have to be linkable, not just present in the image.
# Majestic never needed this -- it arrives prebuilt -- but anything compiled
# here against the IMP SDK carries -limp -lalog on its link line and looks for
# them in the sysroot. Only the libraries go to staging: the sensor blobs and
# the load scripts are runtime files with nothing to link against.
INGENIC_OSDRV_T31_INSTALL_STAGING = YES

define INGENIC_OSDRV_T31_INSTALL_STAGING_CMDS
	$(INSTALL) -m 755 -d $(STAGING_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(STAGING_DIR)/usr/lib $(INGENIC_OSDRV_T31_PKGDIR)/files/lib/*.so
endef

ifeq ($(OPENIPC_SNS_MODEL),)
define INGENIC_OSDRV_T31_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/*.yaml

	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/gc2053-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/gc2083-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/gc4023-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/gc4653-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/imx307-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/imx327-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/jxf37-t31.bin
  $(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/jxf37p-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/jxh62-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/jxq03-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/jxq03p-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/os03b10-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc200ai-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc2232h-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc2335-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc2336-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc3335-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc3338-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc4236-t31.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/sc5235-t31.bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T31_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(INGENIC_OSDRV_T31_PKGDIR)/files/lib/*.so
endef
else
define INGENIC_OSDRV_T31_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/$(OPENIPC_SNS_MODEL).yaml
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T31_PKGDIR)/files/sensor/params/$(OPENIPC_SNS_MODEL)-$(OPENIPC_SOC_MODEL).bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T31_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(INGENIC_OSDRV_T31_PKGDIR)/files/lib/*.so
endef
endif

$(eval $(generic-package))
