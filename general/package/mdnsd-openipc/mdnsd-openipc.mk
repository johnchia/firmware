################################################################################
#
# Copyright (c) OpenIPC  https://openipc.org  MIT License
#
# mdnsd-openipc — mdnsd-openipc Buildroot package
#
################################################################################

MDNSD_OPENIPC_SITE = $(call github,troglobit,mdnsd,$(MDNSD_OPENIPC_VERSION))
MDNSD_OPENIPC_VERSION = v0.12

MDNSD_OPENIPC_LICENSE = BSD-3-Clause
MDNSD_OPENIPC_LICENSE_FILES = LICENSE
MDNSD_OPENIPC_DEPENDENCIES = host-pkgconf
MDNSD_OPENIPC_AUTORECONF = YES

# Stage the library and its headers, so something other than the bundled daemon
# can use libmdnsd -- the query side of it (mdnsd_query, mdnsd_find,
# mdnsd_get_address) is how a client discovers a service on the LAN rather than
# being told where it is.
#
# The stock autotools staging install is enough: upstream already ships the
# public headers as nobase_include_HEADERS (libmdnsd/{mdnsd,1035,sdtxt,xht}.h),
# so they land under usr/include/libmdnsd/ with the directory kept, alongside a
# linkable usr/lib/libmdnsd.so. No INSTALL_STAGING_CMDS of our own, which is
# also why this does not repeat the mquery bug below: `make install` gates that
# binary on the ENABLE_MQUERY automake conditional, where the hand-written
# target install did not.
#
# Note for anyone linking it: there is no pkg-config file, so -lmdnsd has to be
# spelled out.
MDNSD_OPENIPC_INSTALL_STAGING = YES

ifeq ($(BR2_PACKAGE_MDNSD_MQUERY_OPENIPC),y)
MDNSD_OPENIPC_CONF_OPTS += --with-mquery --without-systemd
else
MDNSD_OPENIPC_CONF_OPTS += --without-mquery --without-systemd
endif

# mquery is only built when --with-mquery was passed, so installing it
# unconditionally makes the package fail to install whenever the sub-option is
# off -- which is every configuration that merely wants the daemon.
ifeq ($(BR2_PACKAGE_MDNSD_MQUERY_OPENIPC),y)
define MDNSD_OPENIPC_INSTALL_MQUERY
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/src/mquery
endef
endif

define MDNSD_OPENIPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(MDNSD_OPENIPC_PKGDIR)/files/S50mdnsd
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/mdns.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/mdns.d $(MDNSD_OPENIPC_PKGDIR)/files/rtsp.service
	$(MDNSD_OPENIPC_INSTALL_MQUERY)
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(@D)/libmdnsd/.libs/libmdnsd.so.1.0.0
	ln -sf libmdnsd.so.1.0.0 $(TARGET_DIR)/usr/lib/libmdnsd.so
	ln -sf libmdnsd.so.1.0.0 $(TARGET_DIR)/usr/lib/libmdnsd.so.1
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(@D)/src/mdnsd
endef

$(eval $(autotools-package))
