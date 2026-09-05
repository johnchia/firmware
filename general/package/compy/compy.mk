################################################################################
#
# compy
#
################################################################################

# Pinned rather than tracked at HEAD (which is what Raptor's own
# build-standalone.sh does) so an image can be rebuilt identically later.
#
# Bumped past a783835 ("rtcp: anchor sender reports to the media clock"), which
# adds Compy_RtpTransport_set_clock_reference. rsd calls it from
# rsd_ring_reader.c as of raptor's own "rsd: anchor audio sender reports on the
# capture clock" -- the two landed upstream together, so a pin older than this
# fails the image build on an implicit declaration rather than on a link error.
#
# Bumped again, for the same reason and the same shape of failure. rsd now
# reports reception back to the sender: 6003176 ("receiver: reception statistics
# and RTCP receiver reports") adds Compy_RtpReceiver_feed_at and _write_rr, and
# e677bd7 ("receiver: a leave compound") adds _write_bye. rsd_server.c and
# rsd_session.c call all three, so the previous pin failed the image build on
# three implicit declarations.
COMPY_VERSION = 55797ad685e651825c60d50a8038a0ce9e1f910d
COMPY_SITE = $(call github,gtxaspec,compy,$(COMPY_VERSION))
COMPY_LICENSE = MIT
COMPY_LICENSE_FILES = LICENSE

# Static archive plus headers for rsd to link against; nothing on the target.
COMPY_INSTALL_STAGING = YES
COMPY_INSTALL_TARGET = NO

COMPY_SUPPORTS_IN_SOURCE_BUILD = NO

# compy's CMakeLists pulls four header-only dependencies with FetchContent, and
# CMake cannot fetch them here: Buildroot's host-cmake links a libcurl built
# without TLS, so any https URL fails at configure time with
# 'Protocol "https" not supported or disabled in libcurl'. That is not a network
# problem and no amount of retrying fixes it.
#
# So Buildroot downloads them (its downloader does speak https), the post-extract
# hook unpacks them, and CMake is pointed at the unpacked trees with
# FETCHCONTENT_SOURCE_DIR_* while FETCHCONTENT_FULLY_DISCONNECTED stops it from
# trying to fetch anything at all.
#
# metalang99 is not declared by compy: datatype99 and interface99 each pull it,
# and they agree on the version. One source dir serves both.
COMPY_SLICE99_VERSION = 0.7.8
COMPY_DATATYPE99_VERSION = 1.6.5
COMPY_INTERFACE99_VERSION = 1.0.2
COMPY_METALANG99_VERSION = 1.13.5

COMPY_EXTRA_DOWNLOADS = \
	https://github.com/Hirrolot/slice99/archive/refs/tags/v$(COMPY_SLICE99_VERSION).tar.gz \
	https://github.com/Hirrolot/datatype99/archive/refs/tags/v$(COMPY_DATATYPE99_VERSION).tar.gz \
	https://github.com/Hirrolot/interface99/archive/refs/tags/v$(COMPY_INTERFACE99_VERSION).tar.gz \
	https://github.com/hirrolot/metalang99/archive/refs/tags/v$(COMPY_METALANG99_VERSION).tar.gz

COMPY_DEPS_DIR = $(@D)/deps

define COMPY_EXTRACT_DEPS
	mkdir -p $(COMPY_DEPS_DIR)
	for v in v$(COMPY_SLICE99_VERSION) v$(COMPY_DATATYPE99_VERSION) \
		 v$(COMPY_INTERFACE99_VERSION) v$(COMPY_METALANG99_VERSION); do \
		tar -C $(COMPY_DEPS_DIR) -xf $(COMPY_DL_DIR)/$$v.tar.gz || exit 1; \
	done
endef
COMPY_POST_EXTRACT_HOOKS += COMPY_EXTRACT_DEPS

# The versions above are copies of pins that live in compy's CMakeLists (and
# datatype99's, for metalang99). A copy can drift, and the failure would be
# silent -- FETCHCONTENT_SOURCE_DIR wins, so compy would quietly build against a
# version it did not ask for. Check the pins still match and fail loudly if not.
define COMPY_CHECK_DEP_PINS
	grep -q 'slice99/archive/refs/tags/v$(COMPY_SLICE99_VERSION)\.tar\.gz' \
		$(@D)/CMakeLists.txt || { \
		echo "*** compy pins a slice99 other than $(COMPY_SLICE99_VERSION); update compy.mk"; \
		exit 1; }
	grep -q 'datatype99/archive/refs/tags/v$(COMPY_DATATYPE99_VERSION)\.tar\.gz' \
		$(@D)/CMakeLists.txt || { \
		echo "*** compy pins a datatype99 other than $(COMPY_DATATYPE99_VERSION); update compy.mk"; \
		exit 1; }
	grep -q 'interface99/archive/refs/tags/v$(COMPY_INTERFACE99_VERSION)\.tar\.gz' \
		$(@D)/CMakeLists.txt || { \
		echo "*** compy pins an interface99 other than $(COMPY_INTERFACE99_VERSION); update compy.mk"; \
		exit 1; }
	grep -qi 'metalang99/archive/refs/tags/v$(COMPY_METALANG99_VERSION)\.tar\.gz' \
		$(COMPY_DEPS_DIR)/datatype99-$(COMPY_DATATYPE99_VERSION)/CMakeLists.txt || { \
		echo "*** datatype99 pins a metalang99 other than $(COMPY_METALANG99_VERSION); update compy.mk"; \
		exit 1; }
endef
COMPY_PRE_CONFIGURE_HOOKS += COMPY_CHECK_DEP_PINS

COMPY_CONF_OPTS = \
	-DCOMPY_SHARED=OFF \
	-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
	-DFETCHCONTENT_SOURCE_DIR_SLICE99=$(COMPY_DEPS_DIR)/slice99-$(COMPY_SLICE99_VERSION) \
	-DFETCHCONTENT_SOURCE_DIR_DATATYPE99=$(COMPY_DEPS_DIR)/datatype99-$(COMPY_DATATYPE99_VERSION) \
	-DFETCHCONTENT_SOURCE_DIR_INTERFACE99=$(COMPY_DEPS_DIR)/interface99-$(COMPY_INTERFACE99_VERSION) \
	-DFETCHCONTENT_SOURCE_DIR_METALANG99=$(COMPY_DEPS_DIR)/metalang99-$(COMPY_METALANG99_VERSION)

# TLS/SRTP, against the 3.6 series rather than the 2.x that Majestic pins.
# compy is new code with no blob to satisfy, and rsd is the only consumer.
#
# CMakeLists reaches mbedtls through pkg_check_modules, so the private prefix
# has to arrive as a .pc search path. PKG_CONFIG_PATH rather than
# PKG_CONFIG_LIBDIR: Buildroot's pkg-config wrapper already sets LIBDIR to the
# sysroot's own pkgconfig dirs and replacing that would hide every other
# package. pkgconf searches PATH in addition to LIBDIR, and the wrapper's
# PKG_CONFIG_SYSROOT_DIR is what turns the .pc file's -I/usr/mbedtls3/include
# into a sysroot-relative path.
#
# 2.25 ships no pkg-config files at all -- upstream added them in 3.x -- so
# there is no ambiguity about which series answers here, and the -I this
# produces precedes the sysroot's own /usr/include, where 2.25's headers live.
ifeq ($(BR2_PACKAGE_MBEDTLS3_OPENIPC),y)
COMPY_DEPENDENCIES += mbedtls3-openipc
COMPY_CONF_OPTS += -DCOMPY_TLS_MBEDTLS=ON
COMPY_CONF_ENV += \
	PKG_CONFIG_PATH=$(STAGING_DIR)$(MBEDTLS3_OPENIPC_PREFIX)/lib/pkgconfig
endif

# compy has no install() rules -- upstream's cross builds copy the artefacts by
# hand -- so the staging step is spelled out here. The dependencies are
# header-only and rsd includes them directly through compy's headers, so they
# have to land in staging too or nothing that includes compy.h will compile.
define COMPY_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 644 $(@D)/buildroot-build/libcompy.a \
		$(STAGING_DIR)/usr/lib/libcompy.a
	$(INSTALL) -D -m 644 $(@D)/include/compy.h $(STAGING_DIR)/usr/include/compy.h
	cp -a $(@D)/include/compy $(STAGING_DIR)/usr/include/
	$(INSTALL) -m 644 -t $(STAGING_DIR)/usr/include \
		$(COMPY_DEPS_DIR)/slice99-$(COMPY_SLICE99_VERSION)/*.h \
		$(COMPY_DEPS_DIR)/datatype99-$(COMPY_DATATYPE99_VERSION)/*.h \
		$(COMPY_DEPS_DIR)/interface99-$(COMPY_INTERFACE99_VERSION)/*.h
	$(INSTALL) -D -m 644 \
		$(COMPY_DEPS_DIR)/metalang99-$(COMPY_METALANG99_VERSION)/include/metalang99.h \
		$(STAGING_DIR)/usr/include/metalang99.h
	cp -a $(COMPY_DEPS_DIR)/metalang99-$(COMPY_METALANG99_VERSION)/include/metalang99 \
		$(STAGING_DIR)/usr/include/
endef

$(eval $(cmake-package))
