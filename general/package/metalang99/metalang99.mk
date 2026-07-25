################################################################################
#
# metalang99
#
################################################################################

METALANG99_VERSION = 1.13.5
METALANG99_SITE = $(call github,Hirrolot,metalang99,v$(METALANG99_VERSION))

METALANG99_LICENSE = MIT
METALANG99_LICENSE_FILES = LICENSE

# No build step of its own: this package exists to give dependent CMake
# projects (transitively, via Datatype99/Interface99) an offline
# FETCHCONTENT_SOURCE_DIR_METALANG99 target. It does, however, need to stage
# its public headers (a top-level metalang99.h plus a metalang99/ tree) --
# see slice99.mk for why (compy.h transitively includes <metalang99.h>).
METALANG99_INSTALL_STAGING = YES

define METALANG99_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/metalang99.h $(STAGING_DIR)/usr/include/metalang99.h
	cp -a $(@D)/include/metalang99 $(STAGING_DIR)/usr/include/
endef

$(eval $(generic-package))
