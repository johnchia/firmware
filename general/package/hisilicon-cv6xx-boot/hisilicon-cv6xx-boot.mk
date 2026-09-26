################################################################################
#
# hisilicon-cv6xx-boot
#
# Board hooks for Buildroot's U-Boot package on the Hi3516CV6xx. Not a package:
# it builds nothing of its own and registers no target. U-Boot itself is
# BR2_TARGET_UBOOT, pinned and configured from the board defconfig; everything
# here turns what it builds into the image the boot ROM loads from mtd0.
#
# The steps are the vendor's, from build.sh's build_cv608 in the U-Boot tree,
# with one change: the GSL is built from the tree's gsl/ source. build.sh never
# calls its build_gsl and packs the prebuilt image_tool/input/gsl.bin instead,
# and that blob would not take a U-Boot over the boot ROM's UART download on a
# P23H, where the one built from source did.
#
# The guard is sigmastar-boot's: external.mk is parsed once before .config is
# loaded, so the hooks register only on the second parse, after boot/uboot has
# defined UBOOT_*.
#
################################################################################

ifeq ($(BR2_PACKAGE_HISILICON_CV6XX_BOOT)$(BR_BUILDING),yy)

# image_tool is Python and needs pycryptodome, which Buildroot carries as
# pycryptodomex (the patch in patches/ moves the imports to that name).
#
# Appending to UBOOT_DEPENDENCIES is only half of it this late. uboot.mk has
# already been evaluated, and pkg-generic wrote the configure step's
# prerequisites out then; only the per-package copy reads the list again, at
# build time. Without the rule below, that copy goes looking for host
# directories nothing has built, and rsync fails.
UBOOT_DEPENDENCIES += host-automake host-python3 host-python-pycryptodomex
$(UBOOT_TARGET_CONFIGURE): | host-automake host-python3 host-python-pycryptodomex

# The vendor tree takes the SoC as macros, from one defconfig per SoC. An empty
# PRODUCT_SOCMODEL is what build.sh passes for the cv608, which has a single
# binning; the cv610's five would each need their own DDR table below.
UBOOT_MAKE_OPTS += \
	KCFLAGS="-DPRODUCT_SOC=$(OPENIPC_SOC_MODEL) -DPRODUCT_SOCMODEL= -DVENDOR_HISILICON"

# The version `version` prints names the commit, as a build from a clone would
# (U-Boot 2022.07-gab5d86d5): setlocalversion asks git, and Buildroot unpacks
# a tarball, so the pin is passed instead. It is taken from the download name,
# <sha>.tar.gz, so the pin stays stated once, in the defconfig.
ifeq ($(UBOOT_OVERRIDE_SRCDIR),)
UBOOT_MAKE_OPTS += \
	LOCALVERSION=-g$(shell echo $(basename $(basename $(UBOOT_SOURCE))) | cut -c1-8)
endif

# The board's DDR register table, from reginfo/. The table is chosen by the
# board's DRAM, and every CV608 board seen so far (H4-52POX-S, P23H) runs the
# DMEB DDR2-1333 64 MB 16-bit one. The P23H's vendor image carries the same
# table, which is what makes one boot image serve both.
HISILICON_CV6XX_BOOT_REGINFO_hi3516cv608 = \
	Hi3516CV608-DMEB_4L_DDR2_1333M_64MB_16bit-A7_950M_QFN.bin
HISILICON_CV6XX_BOOT_REGINFO = $(HISILICON_CV6XX_BOOT_REGINFO_$(OPENIPC_SOC_MODEL))

# Records a camera appends to that table (BR2_PACKAGE_HISILICON_CV6XX_BOOT_REGS).
# The boot ROM applies them before the GSL, which is the only point early
# enough to park a pad the way a vendor bootloader does: the H4's leaves the
# enable of an IR-cut driver chip it never uses on the reference table's
# Ethernet-LED function, and the pin then follows the MAC's link state.
HISILICON_CV6XX_BOOT_REGS = $(call qstrip,$(BR2_PACKAGE_HISILICON_CV6XX_BOOT_REGS))
# This is a set of U-Boot hooks, not a generic package, so it has no _PKGDIR.
HISILICON_CV6XX_BOOT_FILES = $(BR2_EXTERNAL_GENERAL_PATH)/package/hisilicon-cv6xx-boot/files

# The defconfig has to spell the SoC out as a literal, because uboot.mk checks
# BR2_TARGET_UBOOT_BOARD_DEFCONFIG at parse time, before OPENIPC_SOC_MODEL is
# set. Assert that the two agree: a mismatch builds another SoC's bootloader.
HISILICON_CV6XX_BOOT_DEFCONFIG = $(call qstrip,$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG))
define HISILICON_CV6XX_BOOT_CHECK
	if [ "$(HISILICON_CV6XX_BOOT_DEFCONFIG)" != "$(OPENIPC_SOC_MODEL)_openipc" ]; then \
		echo "*** BR2_TARGET_UBOOT_BOARD_DEFCONFIG is $(HISILICON_CV6XX_BOOT_DEFCONFIG)"; \
		echo "*** but BR2_OPENIPC_SOC_MODEL is $(OPENIPC_SOC_MODEL)."; \
		exit 1; \
	fi
	if [ -z "$(HISILICON_CV6XX_BOOT_REGINFO)" ]; then \
		echo "*** No DDR table is named for $(OPENIPC_SOC_MODEL) in"; \
		echo "*** hisilicon-cv6xx-boot.mk. Pick the one matching the board's DRAM."; \
		exit 1; \
	fi
	test -f $(@D)/reginfo/$(HISILICON_CV6XX_BOOT_REGINFO)
	if [ -n "$(HISILICON_CV6XX_BOOT_REGS)" ] && [ ! -f "$(HISILICON_CV6XX_BOOT_REGS)" ]; then \
		echo "*** BR2_PACKAGE_HISILICON_CV6XX_BOOT_REGS names $(HISILICON_CV6XX_BOOT_REGS),"; \
		echo "*** which does not exist."; \
		exit 1; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += HISILICON_CV6XX_BOOT_CHECK

# hi-gzip is gzip 1.11 with an 8 KiB window, the most the U-Boot stub's
# decompressor holds. It is a host tool, built from the copy in extras/, and
# goes where the u-boot-z.bin rule looks for it.
#
# The tree commits automake's helper scripts (config.guess, install-sh and the
# rest) as symlinks into /usr/share/automake-1.16, which resolve only on a host
# carrying that version; build.sh papers over it with autoreconf. The generated
# configure and Makefile.in are committed and fine, so only the links are
# replaced, with the same files from Buildroot's host automake 1.16.
HISILICON_CV6XX_BOOT_HWDIR = $(@D)/arch/arm/cpu/armv7/hi3516cv610/hw_compressed

# The GSL Makefiles find their own tree through $(PWD), which make -C leaves
# at the caller's directory, so they are entered with cd and PWD set to match.
#
# THE BOOT IMAGE LAYOUT, AND WHAT IS CHECKED. image_tool writes the GSL length
# at 0x824, and the U-Boot info block follows the GSL at that length + 0x4400
# (0x9000 for the prebuilt GSL, 0x9400 for the source-built one). The info
# block opens with 0x4BF01E2D and records the compressed U-Boot length at
# +36. Checking the magic proves image_tool put a U-Boot where the GSL will
# look, and the length check that the image holds all of it.
#
# 256K is the boot partition of the OpenIPC layout: the env follows at 0x40000.
HISILICON_CV6XX_BOOT_MAX = 262144

define HISILICON_CV6XX_BOOT_ASSEMBLE
	for f in $$(find $(@D)/extras/gzip-1.11 -type l); do \
		cp --remove-destination \
			$(HOST_DIR)/share/automake-1.16/$$(basename $$(readlink $$f)) $$f || exit 1; \
	done
	cd $(@D)/extras/gzip-1.11 && \
		$(HOST_CONFIGURE_OPTS) ./configure \
			CFLAGS="$(HOST_CFLAGS) -fPIC -DWSIZE=0x2000" && \
		$(HOST_MAKE_ENV) $(MAKE)
	cp $(@D)/extras/gzip-1.11/gzip $(HISILICON_CV6XX_BOOT_HWDIR)/gzip
	$(TARGET_MAKE_ENV) $(UBOOT_MAKE) -C $(@D) $(UBOOT_MAKE_OPTS) u-boot-z.bin
	cd $(@D)/gsl && $(TARGET_MAKE_ENV) PWD=$(@D)/gsl $(MAKE1) \
		CHIP=$(OPENIPC_SOC_MODEL) CROSS_COMPILE="$(TARGET_CROSS)"
	cp $(@D)/u-boot-$(OPENIPC_SOC_MODEL).bin $(@D)/image_tool/input/u-boot-original.bin
	$(HOST_DIR)/bin/python3 $(HISILICON_CV6XX_BOOT_FILES)/reg-table-append.py \
		$(@D)/reginfo/$(HISILICON_CV6XX_BOOT_REGINFO) \
		$(@D)/image_tool/input/reg_info.bin $(HISILICON_CV6XX_BOOT_REGS)
	cp $(@D)/gsl/pub/gsl.bin $(@D)/image_tool/input/gsl.bin
	rm -f $(@D)/image_tool/image/oem/boot_image.bin
	cd $(@D)/image_tool/oem && $(HOST_DIR)/bin/python3 oem_quick_build.py
	cp $(@D)/image_tool/image/oem/boot_image.bin $(@D)/boot-image.bin
	img=$(@D)/boot-image.bin; \
	size=$$(wc -c < $$img); \
	gsl=$$(od -A n -t u4 -j 2084 -N 4 $$img | tr -d ' '); \
	info=$$((gsl + 0x4400)); \
	magic=$$(od -A n -t x4 -j $$info -N 4 $$img | tr -d ' '); \
	code=$$(od -A n -t u4 -j $$((info + 36)) -N 4 $$img | tr -d ' '); \
	if [ "$$magic" != "4bf01e2d" ]; then \
		echo "*** $$img has no U-Boot info block at $$info (read '$$magic')."; \
		exit 1; \
	fi; \
	if [ $$((info + 0x400 + code)) -gt $$size ]; then \
		echo "*** $$img ends before its U-Boot does ($$info + 1024 + $$code > $$size)."; \
		exit 1; \
	fi; \
	if [ $$size -gt $(HISILICON_CV6XX_BOOT_MAX) ]; then \
		echo "*** $$img is $$size bytes, over the $(HISILICON_CV6XX_BOOT_MAX)-byte boot partition."; \
		exit 1; \
	fi; \
	echo "boot image: $$size bytes, GSL $$gsl, U-Boot $$code at $$((info + 0x400))"
endef
UBOOT_POST_BUILD_HOOKS += HISILICON_CV6XX_BOOT_ASSEMBLE

# Named as the release server names a bootloader, u-boot-<soc>-nor.bin, which is
# what `make fullimage` looks for. A move rather than a copy, so there is one
# name for the image that goes to mtd0.
define HISILICON_CV6XX_BOOT_NAME_IMAGE
	mv $(BINARIES_DIR)/boot-image.bin $(BINARIES_DIR)/u-boot-$(OPENIPC_SOC_MODEL)-nor.bin
endef
UBOOT_POST_INSTALL_IMAGES_HOOKS += HISILICON_CV6XX_BOOT_NAME_IMAGE

endif
