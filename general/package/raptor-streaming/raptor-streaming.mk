################################################################################
#
# raptor-streaming
#
################################################################################

# Named raptor-streaming rather than raptor, and it cannot be shortened:
# Buildroot already ships package/raptor (raptor2, the RDF parsing library), and
# two packages of the same name is a hard error -- "Package 'raptor' defined a
# second time". The project calls itself the Raptor Streaming System, hence this
# name. The user-facing knob stays RAPTOR_SRCDIR; only the Buildroot variable
# prefix carries the longer name.
#
# Raptor is developed as four sibling repositories -- raptor (the daemons),
# raptor-hal (SoC backends), raptor-common (shared library) and raptor-ipc
# (control sockets). Its top-level Makefile reaches the others through relative
# paths (HAL_DIR := ../raptor-hal and friends), so they have to be siblings at
# build time.
#
# A Buildroot package has one source tree, so the tree this package builds is
# the *parent* directory holding all four, and every command below runs in
# $(@D)/raptor. The fifth sibling a developer checkout usually has, compy, is
# *not* used from there -- it comes from the compy package instead (see the
# COMPY_* overrides below).
#
# There is deliberately no download site. The SigmaStar backend lives on
# unpushed branches of the gtxaspec repositories, so no fetchable revision of it
# exists; a local checkout is currently the only valid source. Pass it as
#
#   make BOARD=ssc30kq_raptor RAPTOR_SRCDIR=/path/to/parent
#
# which the top-level Makefile turns into RAPTOR_STREAMING_OVERRIDE_SRCDIR. When
# the branches are upstreamed this gains a normal pinned _SITE/_VERSION and the
# override becomes the developer path, as it already is for Divinus.
#
# _SOURCE has to be blanked explicitly: Buildroot otherwise derives
# raptor-streaming-local.tar.gz from _VERSION and then refuses the package for
# having a source with no site to fetch it from. Empty _SOURCE is how a package
# says it has nothing to download.
RAPTOR_STREAMING_VERSION = local
RAPTOR_STREAMING_SOURCE =
RAPTOR_STREAMING_LICENSE = MIT
RAPTOR_STREAMING_LICENSE_FILES = raptor/LICENSE

# The parent directory holds more than the five repositories: ref/ is a ~100 MB
# documentation mirror and sigmastar-sdk/ a vendor drop, neither of which the
# build reads. Object files, archives and linked daemons are excluded because a
# developer checkout is normally full of products from direct make invocations,
# and Buildroot's source tree must not inherit them.
RAPTOR_STREAMING_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude ref --exclude sigmastar-sdk --exclude compy \
	--exclude '*.o' --exclude '*.a' --exclude '*.so' \
	--exclude '.built' \
	--exclude 'rss_build_info.c' \
	--exclude 'build' \
	$(foreach d,$(RAPTOR_STREAMING_DAEMONS) $(RAPTOR_STREAMING_TOOLS),--exclude $(d)/$(d))

# The HAL dlopens the MI libraries rather than linking them, so this is an
# install-order dependency rather than a link-time one: the vendor bundle and
# the kernel modules have to be in the image for the daemons to do anything.
#
# faac and opus, by contrast, are genuine link-time dependencies -- but of rad
# alone. Upstream's AAC=1 also declares an AAC *decoder* (-lhelix-aac), which is
# only linked by daemons this image does not build (rsp, rmd), so no helix
# package is needed; -DRAPTOR_AAC on its own compiles fine everywhere else.
RAPTOR_STREAMING_DEPENDENCIES = compy libschrift majestic-fonts \
	sigmastar-osdrv-$(OPENIPC_SOC_FAMILY) faac opus

# What this image runs. Deliberately a subset of upstream's DAEMONS: the rest
# (recording, web, motion, wifibroadcast...) are either unported to this backend
# or not part of the bring-up, and building them here would only turn unrelated
# breakage into a firmware build failure.
#
#   rvd  video, owns the HAL and the SHM rings
#   rsd  RTSP
#   rad  audio
#   rod  OSD text rendering -- draws into SHM, which rvd uploads to MI_RGN
#   ric  IR-cut day/night; exits immediately unless [ircut] enabled
RAPTOR_STREAMING_DAEMONS = rvd rsd rad rod ric
RAPTOR_STREAMING_TOOLS = raptorctl

# The HAL backend to compile, one per SoC family. Derived from the family so a
# new SigmaStar board needs only its defconfig, not an edit here: infinity6e ->
# INFINITY6E, infinity6c -> INFINITY6C.
RAPTOR_STREAMING_PLATFORM = $(shell echo $(OPENIPC_SOC_FAMILY) | tr '[:lower:]' '[:upper:]')

# Board config, with the generic one as the fallback. The ssc30kq file carries
# the settings this hardware was actually brought up with, including the
# comments recording why each one is what it is.
RAPTOR_STREAMING_CONFIG_FILE = $(if $(wildcard $(@D)/raptor/config/raptor-$(OPENIPC_SOC_MODEL).conf),\
	$(@D)/raptor/config/raptor-$(OPENIPC_SOC_MODEL).conf,\
	$(@D)/raptor/config/raptor.conf)

# Buildroot's rsync drops .git, so raptor's own `git rev-parse` for the build
# banner would report "unknown" from inside the source tree. Read it from the
# checkout instead -- during a soak, the banner is how you tell which build is
# on the board.
RAPTOR_STREAMING_BUILD_HASH = $(shell git -C $(RAPTOR_STREAMING_OVERRIDE_SRCDIR)/raptor rev-parse --short HEAD 2>/dev/null || echo unknown)

# With no _SITE and no override, Buildroot has nothing to download or extract
# and leaves an empty source directory, so the build would fail on a missing
# path instead of saying what is wrong. The presence of $(@D)/raptor is an exact
# proxy for "the override rsync ran".
define RAPTOR_STREAMING_CHECK_SRCDIR
	test -d $(@D)/raptor || { \
		echo "*** No Raptor source in $(@D)."; \
		echo "*** Pass a local checkout: make BOARD=$(OPENIPC_SOC_MODEL)_raptor RAPTOR_SRCDIR=/path/to/parent"; \
		echo "*** RAPTOR_SRCDIR is the directory holding raptor/, raptor-hal/, raptor-common/ and raptor-ipc/."; \
		exit 1; }
endef

# The three COMPY_* overrides point rsd at the compy package in staging instead
# of the sibling checkout. Without them raptor's Makefile looks for a libcompy.a
# inside ../compy/build-arm -- a CMake build tree that only exists if a developer
# built it by hand, which is exactly the kind of artefact a firmware image must
# not depend on. compy is excluded from the source sync for the same reason.
#
# Deleting the build products before every build, so that "rebuilt" means
# rebuilt.
#
# This used to compensate for two defects in raptor's own Makefile: HAL archive
# rules with no prerequisites (so make never reconsidered an archive that
# already existed) and two targets sharing one sub-make recipe (so under -j both
# ran at once and each wrote the other's archive). Both are now fixed upstream,
# in raptor/Makefile, by building each sibling library through a stamp -- which
# is why this file no longer needs MAKE1 to serialise the build.
#
# It is still not safe to drop this, because prerequisites are necessary but not
# sufficient here. Buildroot's override rsync copies with -a, preserving each
# file's mtime from the developer's checkout, and updates in place without
# deleting anything. Check out an older revision of raptor-hal and its sources
# arrive *older* than the archive the previous build left behind, so make is
# correct to conclude there is nothing to do -- and the image silently ships HAL
# code that is not the code in the checkout. mtimes cannot answer "is this the
# tree I asked for"; deleting the products can.
#
# The daemon and tool binaries go too, so a library-only change relinks them.
# The stamps must go with the archives: a stamp that outlives the archive it
# stands for tells make the file has already been produced, and the link then
# fails on a missing .a.
define RAPTOR_STREAMING_CLEAN_PRODUCTS
	rm -f $(@D)/raptor-hal/libraptor_hal_video.a $(@D)/raptor-hal/libraptor_hal_audio.a
	rm -f $(@D)/raptor-hal/.built $(@D)/raptor-ipc/.built $(@D)/raptor-common/.built
	rm -f $(foreach d,$(RAPTOR_STREAMING_DAEMONS) $(RAPTOR_STREAMING_TOOLS),$(@D)/raptor/$(d)/$(d))
endef

define RAPTOR_STREAMING_BUILD_CMDS
	$(call RAPTOR_STREAMING_CHECK_SRCDIR)
	$(call RAPTOR_STREAMING_CLEAN_PRODUCTS)
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/raptor \
		PLATFORM=$(RAPTOR_STREAMING_PLATFORM) \
		AAC=1 OPUS=1 \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		SYSROOT="$(STAGING_DIR)" \
		RSS_BUILD_HASH="$(RAPTOR_STREAMING_BUILD_HASH)" \
		COMPY_CFLAGS="-I$(STAGING_DIR)/usr/include" \
		LIB_COMPY_FILE="$(STAGING_DIR)/usr/lib/libcompy.a" \
		LIB_COMPY="$(STAGING_DIR)/usr/lib/libcompy.a" \
		libs $(RAPTOR_STREAMING_DAEMONS) $(RAPTOR_STREAMING_TOOLS)
endef

# Not `make install`: upstream's install target installs every daemon it finds
# and, more importantly, does not install librss_common.so or librss_ipc.so,
# which every daemon lists in DT_NEEDED. An image missing those has binaries
# that cannot start.
#
# The init script is renamed on the way in, and it must not drift back to
# upstream's number: S31 suits a platform whose camera drivers are already in
# the kernel, but on OpenIPC S70vendor is what insmods the MI modules (it runs
# load_sigmastar). At S31 rvd would start before /dev/mi_* exists. S95 is where
# Majestic and Divinus start, for exactly this reason.
define RAPTOR_STREAMING_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin $(TARGET_DIR)/usr/lib \
		$(TARGET_DIR)/etc/init.d
	$(foreach d,$(RAPTOR_STREAMING_DAEMONS) $(RAPTOR_STREAMING_TOOLS),\
		$(INSTALL) -m 755 $(@D)/raptor/$(d)/$(d) $(TARGET_DIR)/usr/bin/$(d)$(sep))
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/lib \
		$(@D)/raptor-common/librss_common.so \
		$(@D)/raptor-ipc/librss_ipc.so
	$(INSTALL) -m 644 $(RAPTOR_STREAMING_CONFIG_FILE) $(TARGET_DIR)/etc/raptor.conf
	$(INSTALL) -m 755 $(@D)/raptor/config/S31raptor \
		$(TARGET_DIR)/etc/init.d/S95raptor
endef

$(eval $(generic-package))
