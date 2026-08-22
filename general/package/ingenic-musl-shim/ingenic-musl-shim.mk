################################################################################
#
# ingenic-musl-shim
#
################################################################################

INGENIC_MUSL_SHIM_VERSION = be103c48b47ce5491c4ae051793124f877d32f45
INGENIC_MUSL_SHIM_SITE = $(call github,gtxaspec,ingenic-musl,$(INGENIC_MUSL_SHIM_VERSION))
INGENIC_MUSL_SHIM_LICENSE = MIT

# Static archive only, and only in staging. The whole point of the shim is to
# be linked *into* the executable that loads libimp: the vendor library leaves
# its uClibc symbols undefined for the dynamic loader to satisfy from the
# global scope, and an executable that linked the archive with
# --whole-archive --export-dynamic is what puts them there. A shared shim
# would work too, but it is a second .so in the image to no purpose --
# raptor's Makefile prefers the archive and only falls back to the .so.
INGENIC_MUSL_SHIM_INSTALL_STAGING = YES
INGENIC_MUSL_SHIM_INSTALL_TARGET = NO

define INGENIC_MUSL_SHIM_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) STATIC=1 \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		static
endef

define INGENIC_MUSL_SHIM_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 644 $(@D)/libmuslshim.a $(STAGING_DIR)/usr/lib/libmuslshim.a
endef

$(eval $(generic-package))
