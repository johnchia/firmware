################################################################################
#
# raptor-streaming
#
################################################################################

# Named raptor-streaming rather than raptor, and it cannot be shortened:
# Buildroot already ships package/raptor (raptor2, the RDF parsing library), and
# two packages of the same name is a hard error -- "Package 'raptor' defined a
# second time". The project calls itself the Raptor Streaming System, hence this
# name.
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
# FOUR PINS, ONE PACKAGE
#
# This used to have no download site at all: the SigmaStar work lived on
# unpushed branches, so a local checkout was the only valid source and an image
# could not be rebuilt by anyone who did not have one. The branches are pushed
# now, so each repository is pinned here and the build fetches them. Pins are
# the only source; to build a change, push it and move the pin.
#
# The pins are on **johnchia**, not gtxaspec: the sigmastar branch exists only on
# the forks (`git ls-remote --heads origin sigmastar` is empty on all four).
# When the work lands upstream these become gtxaspec pins and nothing else here
# changes.
#
# All four move together in practice -- a HAL change usually needs the daemon
# change that calls it -- so bump them as a set and rebuild before trusting the
# result. There is no test that a mixed set links.
RAPTOR_STREAMING_VERSION = bb5901b286378211d97cc15be2bb5b14a1766ee9
RAPTOR_STREAMING_HAL_VERSION = bd0a54d8a25abdf655cd952a63b09a1293b47190
RAPTOR_STREAMING_COMMON_VERSION = c32a43ecd780973ea9c8e5d803729cf14ba1a23b
RAPTOR_STREAMING_IPC_VERSION = 32438648cc03e3c731bb84c7b46f6c51a9e9604e

# A FIFTH PIN, BECAUSE A TARBALL IS NOT A CLONE
#
# raptor-hal keeps the MI ABI declarations in a submodule, johnchia/sigmastar-headers,
# and reaches them as -Isigmastar-headers/<family> (mk/sigmastar.mk). GitHub's
# source archives omit submodule contents entirely -- the directory is simply not
# in the tarball -- so the first pinned build got as far as
# "fatal error: i6c_aud.h: No such file or directory". A checkout never shows
# this because `git submodule update` has already populated it.
#
# The sha is the gitlink recorded at RAPTOR_STREAMING_HAL_VERSION, not whatever
# main points at today:
#
#   git -C raptor-hal ls-tree <hal-pin> sigmastar-headers
#
# so bumping the HAL pin means re-reading this one. That is the same coupling a
# submodule has, made explicit because Buildroot cannot follow the gitlink for a
# source it did not clone.
#
# raptor-hal's other submodule, gtxaspec/ingenic-headers, is deliberately not
# fetched: mk/sigmastar.mk overrides SDK_INCLUDE, and the -I for the Ingenic tree
# is inside `ifneq ($(VENDOR),sigmastar)`, so nothing on these boards reads it.
# An Ingenic raptor target here would need it added the same way.
RAPTOR_STREAMING_HEADERS_VERSION = e7dbbf274405f5bb6dee422f2c1a36699675fa79

RAPTOR_STREAMING_SITE = $(call github,johnchia,raptor,$(RAPTOR_STREAMING_VERSION))
# All four repos are GPL-3.0, and each ships its own copy. Declaring MIT here
# put the wrong licence on the largest component of the image in legal-info,
# while pointing LICENSE_FILES at a GPLv3 file.
RAPTOR_STREAMING_LICENSE = GPL-3.0
RAPTOR_STREAMING_LICENSE_FILES = raptor/LICENSE raptor-hal/LICENSE \
	raptor-common/LICENSE raptor-ipc/LICENSE

# Buildroot fetches one source per package, so the other three come as extra
# downloads. Each URL is spelled the way Buildroot's own github helper spells
# it -- .../archive/<sha>/<name>-<sha>.tar.gz -- because the trailing filename is
# what the downloader saves the file as, and GitHub ignores it. Left as the bare
# .../archive/<sha>.tar.gz these would all land in dl/raptor-streaming/ named
# after nothing but a hash.
RAPTOR_STREAMING_EXTRA_DOWNLOADS = \
	$(call github,johnchia,raptor-hal,$(RAPTOR_STREAMING_HAL_VERSION))/raptor-hal-$(RAPTOR_STREAMING_HAL_VERSION).tar.gz \
	$(call github,johnchia,raptor-common,$(RAPTOR_STREAMING_COMMON_VERSION))/raptor-common-$(RAPTOR_STREAMING_COMMON_VERSION).tar.gz \
	$(call github,johnchia,raptor-ipc,$(RAPTOR_STREAMING_IPC_VERSION))/raptor-ipc-$(RAPTOR_STREAMING_IPC_VERSION).tar.gz \
	$(call github,johnchia,sigmastar-headers,$(RAPTOR_STREAMING_HEADERS_VERSION))/sigmastar-headers-$(RAPTOR_STREAMING_HEADERS_VERSION).tar.gz

# The source tree is the parent directory, so the main tarball must NOT be
# flattened into it the way Buildroot flattens every other package: raptor has to
# end up at $(@D)/raptor with its siblings beside it, not spilled over $(@D)
# itself. STRIP_COMPONENTS = 0 keeps the archive's own top directory, and the
# hook below renames it and unpacks the rest next to it.
RAPTOR_STREAMING_STRIP_COMPONENTS = 0

# $(1) = repository name, $(2) = its pin, $(3) = where it has to end up.
#
# The rm is what makes `mv` mean "become this directory" rather than "move
# inside it", which is the difference between raptor-hal/sigmastar-headers and
# raptor-hal/sigmastar-headers/sigmastar-headers-<sha> if the archive ever does
# ship an empty submodule directory.
define RAPTOR_STREAMING_UNPACK
	$(TAR) -C $(@D) -xf $(RAPTOR_STREAMING_DL_DIR)/$(1)-$(2).tar.gz
	rm -rf $(3)
	mv $(@D)/$(1)-$(2) $(3)
endef

# raptor-hal first: the headers go inside it.
define RAPTOR_STREAMING_LAYOUT_SIBLINGS
	mv $(@D)/raptor-$(RAPTOR_STREAMING_VERSION) $(@D)/raptor
	$(call RAPTOR_STREAMING_UNPACK,raptor-hal,$(RAPTOR_STREAMING_HAL_VERSION),$(@D)/raptor-hal)
	$(call RAPTOR_STREAMING_UNPACK,raptor-common,$(RAPTOR_STREAMING_COMMON_VERSION),$(@D)/raptor-common)
	$(call RAPTOR_STREAMING_UNPACK,raptor-ipc,$(RAPTOR_STREAMING_IPC_VERSION),$(@D)/raptor-ipc)
	$(call RAPTOR_STREAMING_UNPACK,sigmastar-headers,$(RAPTOR_STREAMING_HEADERS_VERSION),$(@D)/raptor-hal/sigmastar-headers)
endef

RAPTOR_STREAMING_POST_EXTRACT_HOOKS += RAPTOR_STREAMING_LAYOUT_SIBLINGS

# The HAL dlopens the MI libraries rather than linking them, so this is an
# install-order dependency rather than a link-time one: the vendor bundle and
# the kernel modules have to be in the image for the daemons to do anything.
#
# faac and opus, by contrast, are genuine link-time dependencies -- of rad, and
# now of rsd too. Upstream's AAC=1 declares both an encoder (-lfaac) and a
# decoder (-lhelix-aac); the decoder used to be reached only by daemons this
# image does not build, so this said no helix package was needed. rsd's
# backchannel changed that: rsd_backchannel.c includes <aacdec.h> under
# RAPTOR_AAC to decode AAC coming *from* a client, and rsd's link line has
# carried -lhelix-aac all along. AAC=1 is one switch for the two libraries, so
# an image that wants AAC out of rad has to supply the decoder as well.
RAPTOR_STREAMING_DEPENDENCIES = compy libschrift majestic-fonts \
	sigmastar-osdrv-$(OPENIPC_SOC_FAMILY) faac helix-aac opus mosquitto

# libmdnsd, for finding a service on the LAN rather than being told where it is
# -- rmq's broker address is the case in hand.
#
# Conditional, where mosquitto above is not, and the difference is whether the
# daemon can be built without it. rmq always links libmosquitto, so that one is
# unconditional; mDNS discovery is a feature of a board that asked for mDNS, and
# an unconditional entry here would build and install mdnsd on every raptor
# target whether or not its defconfig selected it. A board without
# BR2_PACKAGE_MDNSD_OPENIPC simply does not get the discovery path.
ifeq ($(BR2_PACKAGE_MDNSD_OPENIPC),y)
RAPTOR_STREAMING_DEPENDENCIES += mdnsd-openipc
endif

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
#   rmq  MQTT bridge; needs libmosquitto, which is why mosquitto is a dependency
#        above. Idle unless [mqtt] enabled. It plans nothing itself: every
#        command it receives is handed to rcd.
#   rhd  HTTP: snapshots and MJPEG served off the same rings, plus the status
#        page. Gated by [http] enabled, which the overlay config turns on.
#   rcd  Config daemon. Owns raptor.conf -- validates every edit, applies what
#        a running daemon can take live, writes what it cannot, and sequences
#        the restarts for the rest. rmq and raptorctl are its clients, and
#        neither writes the file, so a build without it can start the daemons
#        but cannot change their configuration.
RAPTOR_STREAMING_DAEMONS = rvd rsd rad rod ric rmq rhd rcd
RAPTOR_STREAMING_TOOLS = raptorctl

# The HAL backend to compile, one per SoC family. Derived from the family so a
# new SigmaStar board needs only its defconfig, not an edit here: infinity6e ->
# INFINITY6E, infinity6c -> INFINITY6C.
RAPTOR_STREAMING_PLATFORM = $(shell echo $(OPENIPC_SOC_FAMILY) | tr '[:lower:]' '[:upper:]')

# One config for every board. This used to pick a raptor-$(SOC_MODEL).conf when
# raptor shipped one, which made the config a per-part fork that drifted from the
# default it was copied from; raptor deleted those and this follows.
#
# Per-image changes belong in general/overlay/etc/raptor.conf, which Buildroot
# applies after packages and which therefore wins over this. That overlay is what
# turns [mqtt] and [http] on. Note it is global rather than board-scoped: a
# setting that is genuinely true of one board only has nowhere to go here yet,
# and should be argued for as a raptor.conf default or carried on the board.
RAPTOR_STREAMING_CONFIG_FILE = $(@D)/raptor/config/raptor.conf

# The hash in the daemons' startup banner, which during a soak is how you tell
# which build is on the board. raptor's own Makefile derives it with
# `git rev-parse`, and an unpacked source archive has no .git to read, so it is
# passed in from the pin instead.
RAPTOR_STREAMING_BUILD_HASH = $(shell echo $(RAPTOR_STREAMING_VERSION) | cut -c1-7)

# $(@D)/raptor is where the extract hook must have put the source. Checking it
# costs nothing and turns "no such file or directory" deep in a sub-make into a
# sentence.
define RAPTOR_STREAMING_CHECK_SOURCE
	test -d $(@D)/raptor || { \
		echo "*** No Raptor source in $(@D) -- the extract hook did not run,"; \
		echo "*** or the archive layout changed. Try a dirclean."; \
		exit 1; }
	test -n "$$(ls -A $(@D)/raptor-hal/sigmastar-headers 2>/dev/null)" || { \
		echo "*** raptor-hal/sigmastar-headers is missing or empty."; \
		echo "*** The MI declarations are a submodule of raptor-hal, and neither a"; \
		echo "*** GitHub tarball nor a checkout that has not run 'git submodule"; \
		echo "*** update' carries them. Without it the build fails one file at a"; \
		echo "*** time on missing i6c_*.h."; \
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
# It is kept because it costs one relink and makes "rebuilt" mean rebuilt, and
# because it is the cheap half of a trap the pins set. $(@D) is named after
# RAPTOR_STREAMING_VERSION alone, so moving the HAL, common or IPC pin does not
# change it: the extract hook has already run, its stamp says so, and the build
# directory keeps the sibling sources the *previous* pins unpacked. Deleting the
# products cannot fix that -- only `make br-raptor-streaming-dirclean` can, and
# it is the required first step whenever any pin below the first one moves.
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
	$(call RAPTOR_STREAMING_CHECK_SOURCE)
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
	# rhd serves whatever is at /usr/share/raptor/index.html and 404s without
	# it, so the console is installed *as* that file while living beside
	# upstream's demo page rather than replacing it. Keeping console.html a
	# file upstream does not have is what stops 1600 lines of web UI turning
	# every upstream edit to index.html into a merge conflict.
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/raptor
	$(INSTALL) -m 644 $(@D)/raptor/rhd/console.html \
		$(TARGET_DIR)/usr/share/raptor/index.html
	# rod's default OSD font path is /usr/share/fonts/default.ttf; point it at the
	# UbuntuMono the majestic-fonts dependency already ships rather than shipping a
	# second copy. Relative target so it resolves under any root.
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/fonts
	ln -sf truetype/UbuntuMono-Regular.ttf $(TARGET_DIR)/usr/share/fonts/default.ttf
endef

$(eval $(generic-package))
