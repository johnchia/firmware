################################################################################
#
# sigmastar-uboot
#
################################################################################

# WHY THIS PACKAGE EXISTS
#
# This tree built kernel and rootfs and nothing else, so a bootloader change had
# no way into an image. The two paths that do produce a full .bin --
# general/scripts/repack_firmware.sh and create() in .github/workflows/image.yml
# -- both fetch theirs with
#
#   wget https://github.com/openipc/firmware/releases/download/latest/u-boot-<soc>-nor.bin
#
# and .github/workflows/uboot.yml builds that artefact by cloning
# openipc/u-boot-sigmastar. A fork can therefore never appear in either.
#
# WHAT THE PIN CARRIES
#
# Nothing of our own: the pin is openipc/u-boot-sigmastar master. The package
# exists for the packaging reason above -- to get a locally built boot container
# into `make fullimage` -- not to change the bootloader. It fetched from a fork
# for a while, and that fork was commit-identical the whole time; pinning
# upstream directly says so where a reader can see it.
#
# It briefly carried two things, and both are gone:
#
#   - ethaddr derived from the SPI NOR part's factory unique ID, because the
#     Infinity6C die-ID registers read zero. The rootfs does that now, from
#     /proc/flash_uid, folding the same eight bytes the same way; see
#     ethaddr_provision in general/overlay/etc/init.d/rcS. Board-verified on
#     SSC377QE: both sources read 114a3f3b09914824 and both derive
#     02:2a:43:ae:48:25, so nothing changed address when the derivation moved.
#     The work is parked on johnchia/u-boot-sigmastar's
#     feat/ethaddr-from-flash-uid branch rather than deleted; nothing builds
#     from it.
#
#   - CONFIG_ENV_OVERWRITE, which flips ethaddr's env flags from "mo" (MAC,
#     write-once) to "ma". It went with the branch. If a userspace fw_setenv of
#     ethaddr is ever refused with "Can't overwrite", that is what to reinstate.
#
# NOT a reason to fork: the rootfs partition size. common/cmd_sf.c reads the
# squashfs it finds and sets rootmtd to 5120k or 8192k, and sstar-common.h puts
# ${rootmtd} in the bootargs -- both upstream, unmodified. An earlier revision
# of this comment claimed the 8192k layout needed this package. It does not; a
# stock OpenIPC bootloader selects it too.
#
# One patch is carried, and it is packaging rather than bootloader: upstream's
# Makefile reads the version string's commit hash from `git rev-parse`, which
# has nothing to read in an unpacked tarball, and the build dies at the version
# header. See the patch beside this file. It is here rather than in the pinned
# branch precisely so the pin stays commit-identical to upstream.

SIGMASTAR_UBOOT_VERSION = bf77aff5d44f34d14b89b3f4014aa8dda9834794
SIGMASTAR_UBOOT_SITE = $(call github,openipc,u-boot-sigmastar,$(SIGMASTAR_UBOOT_VERSION))
SIGMASTAR_UBOOT_LICENSE = GPL-2.0+
SIGMASTAR_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt

# The MVXV version string baked into the bootloader carries a short commit hash,
# and it is what `ver` prints on the board -- the only way to tell which build is
# in flash, on a camera with no serial console. The U-Boot Makefile fills it from
# `git rev-parse`, which has nothing to read here because Buildroot unpacks a
# tarball; passing the pin explicitly makes the running board name the exact
# commit this package built, which is better than what a clone-based build gets.
#
# An overridden checkout names its own HEAD instead, read from the checkout
# rather than from $(@D) -- Buildroot's rsync drops .git, so the copy could not
# answer. A tree with uncommitted work gets a trailing '+', which fits the
# eight-character field ms_gen_mvxv_h.py pads to and cannot be mistaken for part
# of a hash; --match=nothing keeps a stray tag from replacing it with a tag name.
ifneq ($(SIGMASTAR_UBOOT_OVERRIDE_SRCDIR),)
SIGMASTAR_UBOOT_CHANGELIST = $(shell git -C $(SIGMASTAR_UBOOT_OVERRIDE_SRCDIR) \
	describe --always --dirty=+ --abbrev=7 --match=nothing 2>/dev/null || echo local)
else
SIGMASTAR_UBOOT_CHANGELIST = $(shell echo $(SIGMASTAR_UBOOT_VERSION) | cut -c1-7)
endif

# A bootloader is not part of the root filesystem. INSTALL_IMAGES puts the
# container in $(BINARIES_DIR) beside uImage and rootfs.squashfs, where
# `make fullimage` looks for it, and out of the sysupgrade tarball, which
# REPACK_FIRMWARE assembles from a named kernel and rootfs rather than from
# whatever it finds in images/.
SIGMASTAR_UBOOT_INSTALL_TARGET = NO
SIGMASTAR_UBOOT_INSTALL_IMAGES = YES

# Iterating on the bootloader without pushing a commit and bumping the pin
# above: make BOARD=<board> UBOOT_SRCDIR=~/u-boot-sigmastar uboot-local
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
SIGMASTAR_UBOOT_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude '*.o' --exclude '*.a' --exclude '*.cmd' --exclude '*.su' \
	--exclude '.tmp_*' --exclude 'System.map' \
	--exclude '/.config' --exclude '/.config.old' \
	--exclude '/include/config' --exclude '/include/generated' \
	--exclude '/include/autoconf.mk' --exclude '/include/autoconf.mk.dep' \
	--exclude '/u-boot' --exclude '/u-boot.bin' --exclude '/u-boot.map' \
	--exclude '/u-boot.lds' --exclude '/u-boot.srec' --exclude '/u-boot.sym' \
	--exclude '/u-boot.img' --exclude '/u-boot*.img.bin' \
	--exclude '/BOOT.bin' --exclude '/BOOT-*.bin'

# One defconfig per family, and the SoC model reaches the code as a macro:
# infinity6c_defconfig with -DPRODUCT_SOC=ssc377qe. That is the vendor's own
# arrangement, from build.sh in the U-Boot tree.
#
# -std=gnu11 is not a preference. The tree predates C23 and include/fwfs.h
# guards `bool` against being a macro before typedef'ing it; under C23 bool is a
# keyword and the typedef is rejected outright. Infinity6C is where this bites
# because infinity6c_defconfig builds fs/firmwarefs.
SIGMASTAR_UBOOT_DEFCONFIG = $(OPENIPC_SOC_FAMILY)_defconfig
SIGMASTAR_UBOOT_MAKE_OPTS = ARCH=arm CROSS_COMPILE=$(TARGET_CROSS) \
	UBOOT_CHANGELIST=$(SIGMASTAR_UBOOT_CHANGELIST)
SIGMASTAR_UBOOT_KCFLAGS = -DPRODUCT_SOC=$(OPENIPC_SOC_MODEL) -std=gnu11

# Where make_boot_spinor.sh lands the compressed u-boot payload, after 128 KB of
# IPL, GCIS, IPL_CUST and the flash descriptor.
SIGMASTAR_UBOOT_PAYLOAD_OFF = 131072

# NAND boards boot a different container -- make_boot_spinand.sh, a different
# IPL layout -- and nothing here has been tried on one. Refusing is the whole
# point: mtd0 is the one partition with no software recovery, so a container
# built by a path nobody has run must not be produced quietly and left lying in
# images/ with a plausible name.
ifeq ($(BR2_TARGET_ROOTFS_UBI),y)
define SIGMASTAR_UBOOT_CHECK_FLASH
	echo "*** sigmastar-uboot builds the SPI NOR container only."; \
	echo "*** This board is NAND (BR2_TARGET_ROOTFS_UBI). make_boot_spinand.sh"; \
	echo "*** is the path for it and it is untested here -- do not guess at mtd0."; \
	exit 1
endef
else
define SIGMASTAR_UBOOT_CHECK_FLASH
	test -f $(@D)/configs/$(SIGMASTAR_UBOOT_DEFCONFIG) || { \
		echo "*** No $(SIGMASTAR_UBOOT_DEFCONFIG) in the U-Boot tree."; \
		echo "*** BR2_OPENIPC_SOC_FAMILY is $(OPENIPC_SOC_FAMILY); the tree carries"; \
		echo "*** infinity3, infinity6, infinity6b0, infinity6c, infinity6e."; \
		exit 1; }
endef
endif

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
define SIGMASTAR_UBOOT_CHECK_CONTAINER
	magic=$$(od -A n -t x1 -j $(SIGMASTAR_UBOOT_PAYLOAD_OFF) -N 4 $(@D)/BOOT.bin 2>/dev/null | tr -d ' \n'); \
	if [ "$$magic" != "27051956" ]; then \
		echo "*** $(@D)/BOOT.bin carries no u-boot payload at $(SIGMASTAR_UBOOT_PAYLOAD_OFF)"; \
		echo "*** (uImage magic 27051956 expected, read '$$magic')."; \
		echo "*** create_img.sh or make_boot_spinor.sh failed without saying so."; \
		echo "*** xz(1) and binutils strings(1) are what they need on the host."; \
		exit 1; \
	fi
endef

define SIGMASTAR_UBOOT_BUILD_CMDS
	$(SIGMASTAR_UBOOT_CHECK_FLASH)
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(SIGMASTAR_UBOOT_MAKE_OPTS) \
		$(SIGMASTAR_UBOOT_DEFCONFIG)
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(SIGMASTAR_UBOOT_MAKE_OPTS) \
		KCFLAGS="$(SIGMASTAR_UBOOT_KCFLAGS)"
	cd $(@D) && $(SHELL) make_boot_spinor.sh $(OPENIPC_SOC_FAMILY)
	$(SIGMASTAR_UBOOT_CHECK_CONTAINER)
endef

# Named as the release server names it, u-boot-<soc>-nor.bin, so that a script
# which flashes one does not care whether it was built here or downloaded.
#
# The container carries a placeholder flash descriptor (SNI) at 0x9000 -- ID
# 05 ee ee, string "default sni" -- as does every from-source build, including
# the binary OpenIPC publishes and the one these boards ship running. It is
# evidently not fatal. A board whose factory container holds a real descriptor
# is still better served by its own bytes: pass SNI_REF=<dump of its mtd0> to
# `make fullimage` and the 4 KB sector is taken from there.
define SIGMASTAR_UBOOT_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 644 -D $(@D)/BOOT.bin \
		$(BINARIES_DIR)/u-boot-$(OPENIPC_SOC_MODEL)-nor.bin
endef

$(eval $(generic-package))
