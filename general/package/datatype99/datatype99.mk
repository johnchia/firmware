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

# Source-only: this package exists to give dependent CMake projects
# (e.g. compy) an offline FETCHCONTENT_SOURCE_DIR_DATATYPE99 target,
# so it deliberately has no build or install step of its own.

$(eval $(generic-package))
