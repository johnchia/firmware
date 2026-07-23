################################################################################
#
# slice99
#
################################################################################

SLICE99_VERSION = 0.7.8
SLICE99_SITE = $(call github,Hirrolot,slice99,v$(SLICE99_VERSION))

SLICE99_LICENSE = MIT
SLICE99_LICENSE_FILES = LICENSE

# Source-only: this package exists to give dependent CMake projects
# (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_SLICE99 target, so
# it deliberately has no build or install step of its own.

$(eval $(generic-package))
