################################################################################
#
# metalang99
#
################################################################################

METALANG99_VERSION = 1.13.5
METALANG99_SITE = $(call github,Hirrolot,metalang99,v$(METALANG99_VERSION))

METALANG99_LICENSE = MIT
METALANG99_LICENSE_FILES = LICENSE

# Source-only: this package exists to give dependent CMake projects
# (transitively, via Datatype99/Interface99) an offline
# FETCHCONTENT_SOURCE_DIR_METALANG99 target, so it deliberately has
# no build or install step of its own.

$(eval $(generic-package))
