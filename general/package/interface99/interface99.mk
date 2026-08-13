################################################################################
#
# interface99
#
################################################################################

INTERFACE99_VERSION = 1.0.2
INTERFACE99_SITE = $(call github,Hirrolot,interface99,v$(INTERFACE99_VERSION))

INTERFACE99_LICENSE = MIT
INTERFACE99_LICENSE_FILES = LICENSE

INTERFACE99_DEPENDENCIES = metalang99

# No build step of its own: this package exists to give dependent CMake
# projects (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_INTERFACE99
# target. It does, however, need to stage its single public header -- see
# slice99.mk for why (compy.h transitively includes <interface99.h>).
INTERFACE99_INSTALL_STAGING = YES

define INTERFACE99_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/interface99.h $(STAGING_DIR)/usr/include/interface99.h
endef

$(eval $(generic-package))
