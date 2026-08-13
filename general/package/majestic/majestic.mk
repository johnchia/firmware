################################################################################
#
# majestic
#
################################################################################

MAJESTIC_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_SOURCE = majestic.$(MAJESTIC_FAMILY).$(MAJESTIC_VARIANT).master.tar.bz2
MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

MAJESTIC_FAMILY = $(OPENIPC_SOC_FAMILY)
MAJESTIC_VARIANT = $(OPENIPC_MAJESTIC)

# libyaml is listed because majestic links it (it parses majestic.yaml with it),
# not because anything here uses it directly. It was missing for years without
# showing, since every image that carried Majestic also carried yaml-cli, which
# selects libyaml and installed it as a side effect. An image with Majestic and
# no yaml-cli -- ssc377qe_raptor is the first -- ships a binary that dies at
# startup on "Error loading shared library libyaml-0.so.2".
MAJESTIC_DEPENDENCIES += \
	libevent-openipc \
	libogg-openipc \
	libyaml \
	mbedtls-openipc \
	opus-openipc \
	json-c

define MAJESTIC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(@D)/majestic.yaml

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(MAJESTIC_PKGDIR)/files/S95majestic

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/majestic
endef

$(eval $(generic-package))
