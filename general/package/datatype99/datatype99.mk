################################################################################
#
# datatype99
#
################################################################################

DATATYPE99_VERSION = 1.6.5
DATATYPE99_SITE = $(call github,Hirrolot,datatype99,v$(DATATYPE99_VERSION))

DATATYPE99_LICENSE = MIT
DATATYPE99_LICENSE_FILES = LICENSE

DATATYPE99_DEPENDENCIES = metalang99

# No build step of its own: this package exists to give dependent CMake
# projects (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_DATATYPE99 target.
# It does, however, need to stage its single public header -- see slice99.mk
# for why (compy.h transitively includes <datatype99.h>).
DATATYPE99_INSTALL_STAGING = YES

define DATATYPE99_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/datatype99.h $(STAGING_DIR)/usr/include/datatype99.h
endef

$(eval $(generic-package))
