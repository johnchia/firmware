################################################################################
#
# compy
#
################################################################################

# compy has no tagged releases yet; pin a specific commit for
# reproducible builds, the same way this tree pins other
# actively-developed forks (see divinus.mk, libevent-openipc.mk).
COMPY_VERSION = 0649f6b73835ab216cc6110736f044fb338c2eb6
COMPY_SITE = $(call github,gtxaspec,compy,$(COMPY_VERSION))

COMPY_LICENSE = MIT
COMPY_LICENSE_FILES = LICENSE

# compy's own CMakeLists.txt pulls these via FetchContent; providing
# them as Buildroot packages and pointing FETCHCONTENT_SOURCE_DIR_*
# at their extracted sources below keeps the build fully offline
# instead of reaching GitHub mid-configure.
COMPY_DEPENDENCIES = slice99 metalang99 datatype99 interface99

# Static build-time dependency only: nothing needs to land in the
# target rootfs, only in the staging sysroot for a future consumer
# (e.g. a Divinus RTSP rewrite) to link against.
COMPY_INSTALL_STAGING = YES
COMPY_INSTALL_TARGET = NO

COMPY_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release \
	-DCOMPY_SHARED=OFF \
	-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
	-DFETCHCONTENT_SOURCE_DIR_SLICE99=$(SLICE99_DIR) \
	-DFETCHCONTENT_SOURCE_DIR_METALANG99=$(METALANG99_DIR) \
	-DFETCHCONTENT_SOURCE_DIR_DATATYPE99=$(DATATYPE99_DIR) \
	-DFETCHCONTENT_SOURCE_DIR_INTERFACE99=$(INTERFACE99_DIR)

$(eval $(cmake-package))
