################################################################################
#
# ipctool
#
################################################################################

# Pinned to a fork carrying the V5 (HISI_OT) die-ID reader: upstream's
# `ipcinfo -i` covers V4 and SigmaStar only, so every 3516CV608/CV610/CV613
# and 35x9DV500 answers with nothing and rcS's ethaddr_provision() falls
# through to the shared placeholder MAC. Revert to openipc/ipctool once the
# change lands there; the branch is v5-die-id.
IPCTOOL_SITE = $(call github,johnchia,ipctool,$(IPCTOOL_VERSION))
IPCTOOL_VERSION = 6cf619e0822338c3d36f865fe438fd89af3845c9

IPCTOOL_LICENSE = MIT
IPCTOOL_LICENSE_FILES = LICENSE
IPCTOOL_INSTALL_STAGING = YES

IPCTOOL_CONF_OPTS += -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -DSKIP_VERSION=ON
IPCTOOL_MAKE_OPTS += VERBOSE=1

define IPCTOOL_INSTALL_STAGING_CMDS
	$(INSTALL) -m 755 -t $(STAGING_DIR)/usr/lib $(@D)/libipchw.a
endef

define IPCTOOL_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/ipcinfo
endef

$(eval $(cmake-package))
