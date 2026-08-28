################################################################################
#
# sigmastar-boot
#
# Board hooks for Buildroot's U-Boot package on SigmaStar. Not a package: it
# builds nothing of its own and registers no target. U-Boot itself is
# BR2_TARGET_UBOOT, pinned and configured from the board defconfig; everything
# here is the SigmaStar-specific part of turning what it builds into something
# that can be written to mtd0.
#
# The guard mirrors the one ingenic-uboot needs: external.mk is parsed once
# before .config is loaded, when every BR2_ symbol is still empty, so the hooks
# must only be registered on the second parse. Buildroot includes this external
# after boot/common.mk (buildroot/Makefile line 545), so UBOOT_* is already
# defined here and += composes with it.
#
################################################################################

ifeq ($(BR2_PACKAGE_SIGMASTAR_BOOT)$(BR_BUILDING),yy)

# NAND boards boot a different container -- make_boot_spinand.sh, a different
# IPL layout -- and nothing here has been tried on one. Refused at parse time
# rather than in a hook, because mtd0 is the one partition with no software
# recovery: a container built by a path nobody has run must not be produced
# quietly and left in images/ with a plausible name.
ifeq ($(BR2_TARGET_ROOTFS_UBI),y)
$(error sigmastar-boot assembles the SPI NOR container only, and this board is \
NAND (BR2_TARGET_ROOTFS_UBI). make_boot_spinand.sh is the path for it and it is \
untested here -- do not guess at mtd0)
endif

# Buildroot's UBOOT_COPY_OLD_LICENSE_FILE hook is a no-op on this tree: it
# copies COPYING over Licenses/gpl-2.0.txt and there is no COPYING here, only
# the Licenses directory. ingenic-uboot has to blank the hook because the
# Ingenic fork ships COPYING as a symlink to that same file and install then
# refuses. Nothing to do on this side, and worth saying so.

# THE VERSION STRING THE BOARD REPORTS
#
# The MVXV version string baked into the bootloader carries a short commit hash,
# and it is what `ver` prints on the board -- the only way to tell which build is
# in flash, on a camera with no serial console. The U-Boot Makefile fills it from
# `git rev-parse`, which has nothing to read because Buildroot unpacks a tarball;
# passing the pin explicitly makes the running board name the exact commit it was
# built from, which is better than what a clone-based build gets.
#
# Taken from the download filename rather than restated, so the pin stays stated
# once, in the defconfig. UBOOT_SOURCE is <sha>.tar.gz for the archive URL there;
# two $(basename) calls strip .gz then .tar.
#
# An overridden checkout names its own HEAD instead, read from the checkout
# rather than from $(@D) -- Buildroot's rsync drops .git, so the copy could not
# answer. A tree with uncommitted work gets a trailing '+', which fits the
# eight-character field ms_gen_mvxv_h.py pads to and cannot be mistaken for part
# of a hash; --match=nothing keeps a stray tag from replacing it with a tag name.
ifneq ($(UBOOT_OVERRIDE_SRCDIR),)
SIGMASTAR_BOOT_CHANGELIST = $(shell git -C $(UBOOT_OVERRIDE_SRCDIR) \
	describe --always --dirty=+ --abbrev=7 --match=nothing 2>/dev/null || echo local)
else
SIGMASTAR_BOOT_CHANGELIST = $(shell echo $(basename $(basename $(UBOOT_SOURCE))) | cut -c1-7)
endif

# One defconfig per family, and the SoC model reaches the code as a macro:
# infinity6c_defconfig with -DPRODUCT_SOC=ssc377qe. That is the vendor's own
# arrangement, from build.sh in the U-Boot tree.
#
# -std=gnu11 is not a preference. The tree predates C23 and include/fwfs.h
# guards `bool` against being a macro before typedef'ing it; under C23 bool is a
# keyword and the typedef is rejected outright. Infinity6C is where this bites
# because infinity6c_defconfig builds fs/firmwarefs.
UBOOT_MAKE_OPTS += \
	KCFLAGS="-DPRODUCT_SOC=$(OPENIPC_SOC_MODEL) -std=gnu11" \
	UBOOT_CHANGELIST=$(SIGMASTAR_BOOT_CHANGELIST)

# Iterating on the bootloader without pushing a commit and bumping the pin in
# the defconfig: make BOARD=<board> UBOOT_SRCDIR=~/u-boot-sigmastar uboot-local
#
# Everything kbuild generates is excluded rather than copied. A U-Boot checkout
# that has been built by hand is full of objects, .cmd files and a .config for
# whichever defconfig was last used, and Buildroot's override rsync updates in
# place without deleting -- so a tree configured for infinity6e would leave its
# .config sitting there for the infinity6c build to pick up. Excluding the
# products means there are none to be stale.
#
# The patterns for the top-level artefacts are anchored with a leading slash on
# purpose: an unanchored 'u-boot' matches any path component and would drop
# include/u-boot/, which is a directory of real headers.
UBOOT_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude '*.o' --exclude '*.a' --exclude '*.cmd' --exclude '*.su' \
	--exclude '.tmp_*' --exclude 'System.map' \
	--exclude '/.config' --exclude '/.config.old' \
	--exclude '/include/config' --exclude '/include/generated' \
	--exclude '/include/autoconf.mk' --exclude '/include/autoconf.mk.dep' \
	--exclude '/u-boot' --exclude '/u-boot.bin' --exclude '/u-boot.map' \
	--exclude '/u-boot.lds' --exclude '/u-boot.srec' --exclude '/u-boot.sym' \
	--exclude '/u-boot.img' --exclude '/u-boot*.img.bin' \
	--exclude '/BOOT.bin' --exclude '/BOOT-*.bin'

# The board defconfig has to spell the family out as a literal --
# BR2_TARGET_UBOOT_BOARD_DEFCONFIG is checked by uboot.mk at parse time, before
# this external is included, so $(OPENIPC_SOC_FAMILY) is still empty there. That
# leaves two statements of the same fact in one file, which is exactly how they
# come to disagree. Assert instead: a mismatch here means the board would build
# another family's bootloader and say nothing.
#
# The existence check is the second half. A family whose defconfig is not in the
# tree otherwise fails inside kbuild, with a message that does not name the cause.
SIGMASTAR_BOOT_DEFCONFIG = $(call qstrip,$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG))
define SIGMASTAR_BOOT_CHECK_DEFCONFIG
	if [ "$(SIGMASTAR_BOOT_DEFCONFIG)" != "$(OPENIPC_SOC_FAMILY)" ]; then \
		echo "*** BR2_TARGET_UBOOT_BOARD_DEFCONFIG is $(SIGMASTAR_BOOT_DEFCONFIG)"; \
		echo "*** but BR2_OPENIPC_SOC_FAMILY is $(OPENIPC_SOC_FAMILY). One of the"; \
		echo "*** two is wrong, and the bootloader is the half with no recovery."; \
		exit 1; \
	fi
	test -f $(@D)/configs/$(SIGMASTAR_BOOT_DEFCONFIG)_defconfig || { \
		echo "*** No $(SIGMASTAR_BOOT_DEFCONFIG)_defconfig in the U-Boot tree."; \
		echo "*** It carries infinity3, infinity6, infinity6b0, infinity6c,"; \
		echo "*** infinity6e."; \
		exit 1; }
endef
UBOOT_PRE_BUILD_HOOKS += SIGMASTAR_BOOT_CHECK_DEFCONFIG

# Where make_boot_spinor.sh lands the compressed u-boot payload, after 128 KB of
# IPL, GCIS, IPL_CUST and the flash descriptor.
SIGMASTAR_BOOT_PAYLOAD_OFF = 131072

# NOTHING IN THIS CHAIN FAILS LOUDLY, SO CHECK THE RESULT
#
# create_img.sh compresses u-boot.bin with xz(1) and wraps it with mkimage;
# make_boot_spinor.sh dd's the result into the container. Neither script sets
# -e. If xz is missing, or mkimage fails, or create_img.sh never runs, the dd of
# a missing file prints one line to stderr and the build still "succeeds" --
# leaving a 128 KB IPL followed by erased flash. That image writes cleanly and
# the board never comes back.
#
# The uImage magic at 128 KB is an exact test for "the payload is there", and
# costs nothing.
#
# What is NOT checked is the load and entry addresses in that header.
# create_img.sh reads them out of the ELF with gdb(1), so on a host without gdb
# they come out 00000000 -- and they are 00000000 in the u-boot-ssc377qe-nor.bin
# OpenIPC publishes and in the factory container read back off a board, both of
# which boot. The IPL plainly does not consult them. Left alone rather than
# "fixed", because on the one partition with no recovery, matching the artefact
# every SigmaStar image has shipped beats filling in a field nothing reads.
# (It does mean a build host with gdb produces a container that differs from
# this one in those eight bytes.)
define SIGMASTAR_BOOT_ASSEMBLE
	cd $(@D) && $(SHELL) make_boot_spinor.sh $(OPENIPC_SOC_FAMILY)
	magic=$$(od -A n -t x1 -j $(SIGMASTAR_BOOT_PAYLOAD_OFF) -N 4 $(@D)/BOOT.bin 2>/dev/null | tr -d ' \n'); \
	if [ "$$magic" != "27051956" ]; then \
		echo "*** $(@D)/BOOT.bin carries no u-boot payload at $(SIGMASTAR_BOOT_PAYLOAD_OFF)"; \
		echo "*** (uImage magic 27051956 expected, read '$$magic')."; \
		echo "*** create_img.sh or make_boot_spinor.sh failed without saying so."; \
		echo "*** xz(1) and binutils strings(1) are what they need on the host."; \
		exit 1; \
	fi
endef
UBOOT_POST_BUILD_HOOKS += SIGMASTAR_BOOT_ASSEMBLE

# Named as the release server names it, u-boot-<soc>-nor.bin, so that a script
# which flashes one does not care whether it was built here or downloaded.
# BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME put BOOT.bin in $(BINARIES_DIR) -- which
# is also how a missing container becomes a build failure rather than a silent
# omission -- and this gives it the name `make fullimage` looks for. A move
# rather than a copy: two names for one container invite flashing the wrong one.
#
# The container carries a placeholder flash descriptor (SNI) at 0x9000 -- ID
# 05 ee ee, string "default sni" -- as does every from-source build, including
# the binary OpenIPC publishes and the one these boards ship running. It is
# evidently not fatal. A board whose factory container holds a real descriptor
# is still better served by its own bytes: pass SNI_REF=<dump of its mtd0> to
# `make fullimage` and the 4 KB sector is taken from there.
define SIGMASTAR_BOOT_NAME_CONTAINER
	mv $(BINARIES_DIR)/BOOT.bin $(BINARIES_DIR)/u-boot-$(OPENIPC_SOC_MODEL)-nor.bin
endef
UBOOT_POST_INSTALL_IMAGES_HOOKS += SIGMASTAR_BOOT_NAME_CONTAINER

endif
