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

# Source-only: this package exists to give dependent CMake projects
# (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_INTERFACE99
# target, so it deliberately has no build or install step of its
# own.

$(eval $(generic-package))
