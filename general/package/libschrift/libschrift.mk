################################################################################
#
# libschrift
#
################################################################################

LIBSCHRIFT_VERSION = 0.10.2
LIBSCHRIFT_SITE = $(call github,tomolt,libschrift,v$(LIBSCHRIFT_VERSION))
LIBSCHRIFT_LICENSE = ISC
LIBSCHRIFT_LICENSE_FILES = LICENSE

# Header and static archive only. Consumers link the .a, so there is nothing
# to install into the target.
LIBSCHRIFT_INSTALL_STAGING = YES
LIBSCHRIFT_INSTALL_TARGET = NO

# Build libschrift.a by name rather than invoking the default target: upstream's
# `all` also builds the demo and stress programs, and the demo needs X11.
#
# CFLAGS is overridden rather than appended to because upstream's config.mk
# assigns it unconditionally. That drops upstream's -pedantic -Wconversion,
# which are author warnings rather than anything the build depends on.
define LIBSCHRIFT_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" RANLIB="$(TARGET_RANLIB)" \
		CFLAGS="$(TARGET_CFLAGS) -std=c99" \
		libschrift.a
endef

define LIBSCHRIFT_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 644 $(@D)/libschrift.a $(STAGING_DIR)/usr/lib/libschrift.a
	$(INSTALL) -D -m 644 $(@D)/schrift.h $(STAGING_DIR)/usr/include/schrift.h
endef

$(eval $(generic-package))
