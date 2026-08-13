################################################################################
#
# slice99
#
################################################################################

SLICE99_VERSION = 0.7.8
SLICE99_SITE = $(call github,Hirrolot,slice99,v$(SLICE99_VERSION))

SLICE99_LICENSE = MIT
SLICE99_LICENSE_FILES = LICENSE

# No build step of its own: this package exists to give dependent CMake
# projects (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_SLICE99 target.
# It does, however, need to stage its single public header: compy.h itself
# includes <slice99.h>, so a plain-Makefile consumer of libcompy (Divinus)
# needs it on the include path too, not just CMake consumers pulling it in
# via FetchContent.
SLICE99_INSTALL_STAGING = YES

define SLICE99_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/slice99.h $(STAGING_DIR)/usr/include/slice99.h
endef

$(eval $(generic-package))
