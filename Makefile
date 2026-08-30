BR_VER = 2024.02.10
BR_MAKE = $(MAKE) -C $(TARGET)/buildroot-$(BR_VER) BR2_EXTERNAL=$(PWD)/general O=$(TARGET)
BR_LINK = https://github.com/buildroot/buildroot/archive
BR_FILE = /tmp/buildroot-$(BR_VER).tar.gz
BR_CONF = $(TARGET)/openipc_defconfig
TARGET ?= $(PWD)/output

# TARGET is ours and must not reach a package's ./configure.
#
# A variable set on the make command line is exported to every sub-process, and
# `make BOARD=<board> TARGET=<dir>` -- the way to build a second board without
# overwriting the first one's output -- therefore puts TARGET in the environment
# of every configure script Buildroot runs. autoconf's AX_ENABLE_BUILDDIR macro
# reads exactly that name:
#
#   test ".$TARGET" = "." && TARGET="$target"
#   test ".$ax_enable_builddir" = ".auto" && ax_enable_builddir="$TARGET"
#
# so libffi re-execs its configure inside a directory named after our output
# path, computes a relative --srcdir by counting the components of it, and dies
# on "../../../../.././configure: No such file or directory". Invisible on the
# default path, because `TARGET ?=` is not a command-line variable and so is not
# exported at all.
#
# Two things carry it and both have to be stopped: `unexport` covers the
# environment, and the MAKEOVERRIDES filter covers MAKEFLAGS, through which a
# command-line variable reaches a sub-make and is re-exported by it. Only
# TARGET is filtered, so V=1 and every other override still propagate -- and
# every recipe here that recurses passes TARGET explicitly anyway.
unexport TARGET
MAKEOVERRIDES := $(filter-out TARGET=%,$(MAKEOVERRIDES))
export CMAKE_POLICY_VERSION_MINIMUM := 3.5

# Use an explicit local checkout for Divinus development without changing the
# release commit pinned by the Buildroot package.
ifneq ($(strip $(DIVINUS_SRCDIR)),)
BR_MAKE += DIVINUS_OVERRIDE_SRCDIR=$(abspath $(DIVINUS_SRCDIR))
endif

# Build the bootloader from a checkout instead of the commit pinned in the board
# defconfig, so a change can be tried without pushing it first. Buildroot's own
# override, so it serves whichever U-Boot the board builds -- SigmaStar's vendor
# tree or the Ingenic one -- rather than one vendor's package.
ifneq ($(strip $(UBOOT_SRCDIR)),)
BR_MAKE += UBOOT_OVERRIDE_SRCDIR=$(abspath $(UBOOT_SRCDIR))
endif

# GCC 15 defaults to -std=gnu23, where an empty parameter list means "takes no
# arguments" rather than "unspecified". Several host packages Buildroot pins
# here predate that and their configure probes stop compiling: gmp 6.3.0 fails
# its compiler test with "too many arguments to function 'g'", which surfaces as
# the far less helpful "could not find a working compiler" and halts any
# `make toolchain` on a current distro. Pin the dialect rather than carry a
# version bump for every affected host package. Applies only to host C builds,
# is overridable from the environment, and is a no-op on hosts whose GCC still
# defaults to gnu17.
#
# "Applies only to host C builds" is what the prepare: rule below has to make
# true -- Buildroot appends HOST_CFLAGS to HOST_CXXFLAGS wholesale.
HOST_CFLAGS ?= -O2 -std=gnu17
export HOST_CFLAGS

CONFIG = $(error variable BOARD not defined)
TIMER := $(shell date +%s)

ifeq ($(or $(MAKECMDGOALS), $(BOARD)),)
LIST := $(shell find ./br-ext-*/configs/*_defconfig | sort | \
	sed -E "s/br-ext-chip-(.+).configs.(.+)_defconfig/'\2' '\1 \2'/")
BOARD := $(or $(shell whiptail --title "Available boards" --menu "Select a config:" 20 70 12 \
	--notags $(LIST) 3>&1 1>&2 2>&3),$(CONFIG))
endif

ifneq ($(BOARD),)
CONFIG := $(shell find br-ext-*/configs/*_defconfig | grep -m1 $(BOARD))
include $(CONFIG)
endif

ifneq ($(filter repack,$(MAKECMDGOALS)),)
-include $(BR_CONF)
endif

all: repack-final timer

build: defconfig
	@$(BR_MAKE) all -j$(shell nproc)

br-%: defconfig
	@$(BR_MAKE) $(subst br-,,$@) -j$(shell nproc)

.PHONY: divinus-local divinus-pinned

# Split into two serial sub-makes instead of the single `br-divinus-rebuild`
# this used to call. Buildroot declares `divinus-rebuild: divinus-clean-for-rebuild
# .WAIT divinus`, relying on `.WAIT` to stop the build branch from running until
# the stamp files have been removed -- but `.WAIT` is a GNU Make 4.4 feature and
# is not honoured by 4.3, which is what most hosts still ship. Under `-j` the two
# branches then evaluate concurrently: the build branch sees `.stamp_built` before
# the clean branch deletes it, concludes the package is up to date, and only the
# rsync re-runs. The result was a silent no-op -- exit 0, a plausible-looking log
# ending at the rsync line, and a binary still built from the previous source,
# which is an excellent way to flash and debug stale firmware. Two separate
# invocations are ordered by make itself and need no `.WAIT`.
divinus-local:
	@test -n "$(strip $(DIVINUS_SRCDIR))" || { \
		echo "DIVINUS_SRCDIR is required (path to a Divinus checkout)"; exit 2; }
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		DIVINUS_SRCDIR="$(abspath $(DIVINUS_SRCDIR))" br-divinus-clean-for-rebuild
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		DIVINUS_SRCDIR="$(abspath $(DIVINUS_SRCDIR))" br-divinus

divinus-pinned:
	@test -z "$(strip $(DIVINUS_SRCDIR))" || { \
		echo "Do not set DIVINUS_SRCDIR when restoring the pinned Divinus source"; exit 2; }
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) br-divinus-dirclean
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) br-divinus

.PHONY: uboot-local

# An overridden source tree has no prerequisite Buildroot can see, so a plain
# build after editing U-Boot re-installs the container from the previous one. On
# mtd0 that is worse than elsewhere -- the flash succeeds, the board boots the
# old bootloader, and the change appears not to work. Hence the explicit
# clean-for-rebuild first.
#
# Two sequential invocations rather than Buildroot's <pkg>-rebuild, which does
# not work here and fails *silently*. Buildroot 2024.02 defines it as
#
#   $(1)-rebuild: $(1)-clean-for-rebuild .WAIT $(1)
#
# and .WAIT needs GNU make 4.4; on 4.3 it is not honoured, so the stamp removal
# and the rebuild are just parallel prerequisites and the build can be evaluated
# before the stamps are gone. The observed result is a run that re-syncs the
# source, builds nothing, and exits 0 -- leaving the previous binaries in place
# while looking like it worked. Splitting the two steps removes the ordering
# question entirely.
#
# (divinus-local above uses br-divinus-rebuild and has the same exposure.)
uboot-local:
	@test -n "$(strip $(UBOOT_SRCDIR))" || { \
		echo "UBOOT_SRCDIR is required (path to a U-Boot checkout)"; exit 2; }
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		UBOOT_SRCDIR="$(abspath $(UBOOT_SRCDIR))" \
		br-uboot-clean-for-rebuild
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		UBOOT_SRCDIR="$(abspath $(UBOOT_SRCDIR))" br-uboot

defconfig: prepare
	@echo --- $(or $(CONFIG),$(error variable BOARD not found))
	@cat $(CONFIG) $(PWD)/general/openipc.fragment > $(BR_CONF)
	@grep -s '^BR2_GLOBAL_PATCH_DIR=' $(CONFIG) >> $(BR_CONF) || true
# The fragment is concatenated after the board config, so it wins every
# conflict -- including BR2_ROOTFS_OVERLAY, which it hardcodes to the shared
# overlay alone. A board that needs a file of its own (fw_env.config is the
# case in hand: its offsets and sector size are per-SoC, and the shared
# overlay cannot carry a value that is right for every vendor) re-states the
# whole list, shared directory included, and it is appended back here. Same
# idiom as BR2_GLOBAL_PATCH_DIR above, and inert for boards that set neither.
	@grep -s '^BR2_ROOTFS_OVERLAY=' $(CONFIG) >> $(BR_CONF) || true
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig

prepare:
	@if test ! -e $(TARGET)/buildroot-$(BR_VER); then \
		wget -c -q $(BR_LINK)/$(BR_VER).tar.gz -O $(BR_FILE); \
		mkdir -p $(TARGET); tar -xf $(BR_FILE) -C $(TARGET); fi
	@if test -f $(TARGET)/buildroot-$(BR_VER)/linux/Config.in; then \
		sed -i '/source "$$(BR2_EXTERNAL_GENERAL_PATH)\/linux\/Config.ext.in"/d' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in; \
		grep -qF 'source "$$BR2_EXTERNAL_GENERAL_PATH/linux/Config.ext.in"' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in || \
		sed -i '/source "linux\/Config.ext.in"/a source "$$BR2_EXTERNAL_GENERAL_PATH/linux/Config.ext.in"' \
			$(TARGET)/buildroot-$(BR_VER)/linux/Config.in; \
	fi
	@# Keep the C dialect pinned at the top of this file out of host C++ builds.
	@# package/Makefile.in does `HOST_CXXFLAGS += $$(HOST_CFLAGS)`, so -std=gnu17
	@# reaches every host C++ compile, where it is not a C++ dialect at all: g++
	@# ignores it and prints "command-line option '-std=gnu17' is valid for
	@# C/ObjC but not for C++". Compilation still succeeds -- what does not is
	@# CMake, whose cm_check_cxx_feature discards any feature whose try_compile
	@# output contains the word "warning" (Source/Checks/cm_cxx_features.cmake).
	@# host-cmake therefore decides the compiler has no std::unique_ptr and
	@# aborts its own configure, taking every `make BOARD=...` with it.
	@# Filtering -std= rather than that one value so a C dialect set from the
	@# environment does not reintroduce this.
	@if test -f $(TARGET)/buildroot-$(BR_VER)/package/Makefile.in; then \
		grep -qF 'filter-out -std=%' \
			$(TARGET)/buildroot-$(BR_VER)/package/Makefile.in || \
		sed -i 's|^HOST_CXXFLAGS += \$$(HOST_CFLAGS)$$|HOST_CXXFLAGS += $$(filter-out -std=%,$$(HOST_CFLAGS))|' \
			$(TARGET)/buildroot-$(BR_VER)/package/Makefile.in; \
	fi

help:
	@printf "BR-OpenIPC usage:\n \
	- make list - show available device configurations\n \
	- make deps - install build dependencies\n \
	- make clean - remove defconfig and target folder\n \
	- make package - list available packages\n \
	- make distclean - remove buildroot and output folder\n \
	- make br-linux - build linux kernel only\n\n"
	@printf "Divinus development:\n \
	- make BOARD=<board> DIVINUS_SRCDIR=/path/to/divinus divinus-local\n \
	- make BOARD=<board> divinus-pinned\n\n"
	@printf "Bootloader (BR2_TARGET_UBOOT; the pin is in the board defconfig):\n \
	- make BOARD=<board> br-uboot - build it alone\n \
	- make BOARD=<board> UBOOT_SRCDIR=~/u-boot-sigmastar uboot-local\n\n"
	@printf "Full NOR image from locally built pieces. A modified bootloader\n \
	reaches an image no other way: repack_firmware.sh and the CI workflow both\n \
	download u-boot from the release server.\n \
	- make BOARD=<board> fullimage - uses images/u-boot-<soc>-nor.bin\n \
	- add UBOOT_BIN=<container> to flash one built elsewhere\n \
	- add SNI_REF=<dump of the board's mtd0> to keep its flash descriptor\n\n"

list:
	@ls -1 br-ext-chip-*/configs

package:
	@find $(PWD)/general/package/* -maxdepth 0 -type d -printf "br-%f\n" | grep -v patch

toolname:
	@echo toolchain.$(BR2_OPENIPC_SOC_VENDOR)-$(BR2_OPENIPC_SOC_FAMILY)

clean:
	@rm -rf $(TARGET)/build $(TARGET)/images $(TARGET)/per-package $(TARGET)/target

distclean:
	@rm -rf $(BR_FILE) $(TARGET)

audit-abi:
	@python3 $(PWD)/general/scripts/audit-vendor-abi.py

deps:
	sudo apt-get install -y automake autotools-dev bc build-essential cpio \
		curl file fzf git libncurses-dev libtool lzop make rsync unzip wget libssl-dev \
		python3 python3-pip
	# kconfiglib is the only non-stdlib dep added by general/scripts/kconfig_graph.py;
	# install with --break-system-packages on PEP 668 distros (Ubuntu 24.04+, Debian 12+).
	python3 -m pip install --user --break-system-packages kconfiglib

timer:
	@echo - Build time: $(shell date -d @$(shell expr $(shell date +%s) - $(TIMER)) -u +%M:%S)

toolchain: defconfig
ifeq ($(BR2_TOOLCHAIN_EXTERNAL),y)
	@cp -rf $(PWD)/general/package/gcc $(TARGET)/buildroot-$(BR_VER)/package
	@$(MAKE) -f $(PWD)/general/toolchain.mk BR_CONF=$(BR_CONF) CONFIG=$(PWD)/$(CONFIG)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
endif
	@$(BR_MAKE) sdk -j$(shell nproc)
	@$(call BUNDLE_SDK)

toolchain-asan: defconfig
ifeq ($(BR2_TOOLCHAIN_EXTERNAL),y)
	@cp -rf $(PWD)/general/package/gcc $(TARGET)/buildroot-$(BR_VER)/package
	@$(MAKE) -f $(PWD)/general/toolchain.mk BR_CONF=$(BR_CONF) CONFIG=$(PWD)/$(CONFIG)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
endif
	@echo 'BR2_EXTRA_GCC_CONFIG_OPTIONS="--enable-libsanitizer"' >> $(BR_CONF)
	@$(BR_MAKE) BR2_DEFCONFIG=$(BR_CONF) defconfig
	@$(BR_MAKE) sdk -j$(shell nproc)
	@$(call BUNDLE_SDK)

repack-final: build
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) repack

# A full NOR image, boot through rootfs, from what is in this tree.
#
# The .tgz the normal build emits carries kernel and rootfs only, so it can be
# sysupgraded but says nothing about the bootloader. The two paths that do
# produce a full .bin -- general/scripts/repack_firmware.sh and create() in
# .github/workflows/image.yml -- fetch u-boot from
# github.com/openipc/firmware/releases, built by .github/workflows/uboot.yml
# from openipc/u-boot-sigmastar. A locally modified bootloader therefore cannot
# appear in either, which is the right default for reproducing a release and no
# use at all for testing a change.
#
# The bootloader defaults to the one BR2_TARGET_UBOOT built here, which
# is in this tree and is the point. What it must never default to is a
# downloaded one: that would put upstream's bootloader in an image that claims
# to be assembled from local pieces, silently. UBOOT_BIN overrides for a
# container built elsewhere.
FULLIMAGE_UBOOT = $(strip $(if $(strip $(UBOOT_BIN)),$(abspath $(UBOOT_BIN)),\
	$(TARGET)/images/u-boot-$(subst ",,$(BR2_OPENIPC_SOC_MODEL))-nor.bin))

fullimage: defconfig
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"ingenic")
	@test -n "$(strip $(UBOOT_BIN))" -o -f "$(TARGET)/images/u-boot-with-tpl-lzma.bin" || { \
		echo "no bootloader at $(TARGET)/images/u-boot-with-tpl-lzma.bin"; \
		echo "enable BR2_TARGET_UBOOT in the board defconfig and build, or run"; \
		echo "  make BOARD=$(BOARD) br-uboot"; \
		echo "or point UBOOT_BIN at one built elsewhere (the TPL container,"; \
		echo "not u-boot.bin)"; \
		exit 2; }
	@test -n "$(strip $(UBOOT_ENV_BIN))" -o -f "$(TARGET)/images/uboot-env.bin" || { \
		echo "no environment at $(TARGET)/images/uboot-env.bin"; \
		echo "enable BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE and point"; \
		echo "BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SOURCE at the board's"; \
		echo "env text file. Without it the board boots on U-Boot's"; \
		echo "compiled-in default, which has no SD-card recovery in it."; \
		exit 2; }
	@$(SHELL) $(PWD)/general/scripts/make_full_image_ingenic.sh \
		"$(TARGET)/images" \
		"$(subst ",,$(BR2_OPENIPC_SOC_MODEL))" \
		"$(TARGET)/images/openipc-$(subst ",,$(BR2_OPENIPC_SOC_MODEL))-nor-full.bin"
else
	@test -f "$(FULLIMAGE_UBOOT)" || { \
		echo "no boot container at $(FULLIMAGE_UBOOT)"; \
		echo "enable BR2_TARGET_UBOOT and BR2_PACKAGE_SIGMASTAR_BOOT and build,"; \
		echo "or run  make BOARD=$(BOARD) br-uboot"; \
		echo "or point UBOOT_BIN at one built elsewhere (the assembled"; \
		echo "container, not u-boot.bin)"; \
		exit 2; }
	@FLASH_KB=$(shell expr $(subst ",,$(BR2_OPENIPC_FLASH_SIZE)) \* 1024) \
	$(SHELL) $(PWD)/general/scripts/make_full_image.sh \
		"$(FULLIMAGE_UBOOT)" \
		"$(TARGET)/images" \
		"$(subst ",,$(BR2_OPENIPC_SOC_MODEL))" \
		"$(TARGET)/images/openipc-$(subst ",,$(BR2_OPENIPC_SOC_MODEL))-nor-full.bin" \
		$(if $(strip $(SNI_REF)),"$(abspath $(SNI_REF))")
endif

# The rootfs size limit is a property of the *partition table*, not of the flash
# chip. Deriving it from BR2_OPENIPC_FLASH_SIZE assumes the two agree, and they
# need not: ssc30kq had 16MB of NOR while giving the rootfs only 0x500000
# (5120KB), the remaining 8.5MB going to the overlay --
#
#   0x000000250000-0x000000750000 : "rootfs"
#   0x000000750000-0x000001000000 : "rootfs_data"
#
# so a 16MB board was checked against 8192KB, passed at 5160KB, and flashcp then
# refused the image as "bigger than /dev/mtd3". A limit larger than the partition
# is not a limit; it moves the failure from the build, where it is a number, to
# the flash, where it is a camera in an unknown state.
#
# (That board takes the 8192k layout now, since it builds the bootloader that
# switches to it. The example stands as the reason this setting exists: the two
# numbers were independent then and still are.)
#
# Boards whose layout does not follow from the chip size state the real figure in
# BR2_OPENIPC_ROOTFS_PART_KB; everything else keeps the previous defaults.
ROOTFS_CAP_KB = $(or $(strip $(subst ",,$(BR2_OPENIPC_ROOTFS_PART_KB))),\
	$(if $(filter "8",$(BR2_OPENIPC_FLASH_SIZE)),5120,8192))

repack:
ifeq ($(BR2_PACKAGE_OPENIPC_NFS_ROOT),y)
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"rockchip")
	@$(call PREPARE_REPACK,zboot.img,16384,,,nfs-root)
else
	@$(call PREPARE_REPACK,uImage,16384,,,nfs-root)
endif
else
ifeq ($(BR2_OPENIPC_SOC_FAMILY),"hi3516cv6xx")
	@$(call PREPARE_REPACK,firmware.bin,$(shell expr $(subst ",,$(BR2_OPENIPC_FLASH_SIZE)) \* 1024),,,nor)
else ifeq ($(BR2_OPENIPC_SOC_FAMILY),"hi3519dv500")
	@$(call PREPARE_REPACK,firmware.bin,$(shell expr $(subst ",,$(BR2_OPENIPC_FLASH_SIZE)) \* 1024),,,nor)
else ifneq ($(wildcard $(TARGET)/images/firmware.bin),)
	@$(call PREPARE_REPACK,firmware.bin,8192,,,nor)
else
ifeq ($(BR2_TARGET_ROOTFS_SQUASHFS),y)
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"rockchip")
	@$(call PREPARE_REPACK,zboot.img,4096,rootfs.squashfs,8192,nor)
else
	@$(call PREPARE_REPACK,uImage,2048,rootfs.squashfs,$(ROOTFS_CAP_KB),nor)
endif
endif
ifeq ($(BR2_TARGET_ROOTFS_UBI),y)
ifneq ($(filter $(BR2_OPENIPC_SOC_VENDOR),"rockchip" "sigmastar"),)
	@$(call PREPARE_REPACK,,,rootfs.ubi,16384,nand)
else
	@$(call PREPARE_REPACK,uImage,4096,rootfs.ubi,16384,nand)
endif
endif
ifeq ($(BR2_TARGET_ROOTFS_INITRAMFS),y)
	@$(call PREPARE_REPACK,uImage,16384,,,initramfs)
endif
endif
endif

size-report:
	@TARGET_DIR=$(TARGET)/target \
	BR2_OUTPUT_DIR=$(TARGET) \
	IMAGES_DIR=$(TARGET)/images \
	OPENIPC_SOC_MODEL=$(BR2_OPENIPC_SOC_MODEL) \
	OPENIPC_VARIANT=$(BR2_OPENIPC_VARIANT) \
	BR2_OPENIPC_FLASH_SIZE=$(BR2_OPENIPC_FLASH_SIZE) \
	BR2_OPENIPC_ROOTFS_PART_KB=$(BR2_OPENIPC_ROOTFS_PART_KB) \
	BR2_OPENIPC_SOC_VENDOR=$(BR2_OPENIPC_SOC_VENDOR) \
	BR2_TARGET_ROOTFS_SQUASHFS=$(BR2_TARGET_ROOTFS_SQUASHFS) \
	BR2_TARGET_ROOTFS_UBI=$(BR2_TARGET_ROOTFS_UBI) \
	python3 $(PWD)/general/scripts/size_report.py

kconfig-graph:
	@TARGET_DIR=$(TARGET)/target \
	BR2_OUTPUT_DIR=$(TARGET) \
	IMAGES_DIR=$(TARGET)/images \
	OPENIPC_SOC_MODEL=$(BR2_OPENIPC_SOC_MODEL) \
	OPENIPC_VARIANT=$(BR2_OPENIPC_VARIANT) \
	BR_VER=$(BR_VER) \
	PWD=$(PWD) \
	python3 $(PWD)/general/scripts/kconfig_graph.py

define BUNDLE_SDK
	OSDRV_DIR=$(PWD)/general/package/$(BR2_OPENIPC_SOC_VENDOR)-osdrv-$(BR2_OPENIPC_SOC_FAMILY)/files; \
	MPP_HEADERS=$(PWD)/general/package/hisilicon-osdrv-hi3516cv100/files/include; \
	SDK_TGZ=$$(find $(TARGET)/images -name '*_sdk-buildroot.tar.gz' | head -1); \
	UCLIBC_COMPAT_SRC=$(PWD)/general/package/uclibc-compat/src/uclibc-compat.c; \
	UCLIBC_COMPAT_STATIC=$(PWD)/general/package/uclibc-compat/src/uclibc-compat-static.c; \
	GLIBC_COMPAT_SRC=$(PWD)/general/package/glibc-compat/src/glibc-compat.c; \
	GLIBC_COMPAT_STATIC=$(PWD)/general/package/glibc-compat/src/glibc-compat-static.c; \
	SDK_CC=$$(ls $(TARGET)/host/bin/*-gcc 2>/dev/null | head -1); \
	if [ -d "$$OSDRV_DIR" ] && [ -n "$$SDK_TGZ" ]; then \
		SDK_TOP=$$(tar tzf $$SDK_TGZ | head -1 | cut -d/ -f1); \
		rm -rf /tmp/sdk-overlay && mkdir -p /tmp/sdk-overlay/$$SDK_TOP/sdk; \
		cp -a $$OSDRV_DIR/* /tmp/sdk-overlay/$$SDK_TOP/sdk/; \
		if [ "$(BR2_OPENIPC_SOC_VENDOR)" = "hisilicon" ] && [ ! -d "$$OSDRV_DIR/include" ] && [ -d "$$MPP_HEADERS" ]; then \
			mkdir -p /tmp/sdk-overlay/$$SDK_TOP/sdk/include; \
			cp -a $$MPP_HEADERS/. /tmp/sdk-overlay/$$SDK_TOP/sdk/include/; \
		fi; \
		if [ -n "$$SDK_CC" ]; then \
			SDK_AR=$$(echo $$SDK_CC | sed 's/-gcc$$/-ar/'); \
			if [ -f "$$UCLIBC_COMPAT_SRC" ]; then \
				$$SDK_CC -shared -Wall -O2 -fPIC \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libuclibc-compat.so \
					$$UCLIBC_COMPAT_SRC; \
			fi; \
			if [ -f "$$UCLIBC_COMPAT_STATIC" ]; then \
				$$SDK_CC -Wall -O2 -fPIC -c \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o \
					$$UCLIBC_COMPAT_STATIC; \
				$$SDK_AR rcs /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libuclibc-compat-static.a \
					/tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o; \
				rm -f /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/uclibc-compat-static.o; \
			fi; \
			if [ -f "$$GLIBC_COMPAT_SRC" ]; then \
				$$SDK_CC -shared -Wall -O2 -fPIC \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libglibc-compat.so \
					$$GLIBC_COMPAT_SRC; \
			fi; \
			if [ -f "$$GLIBC_COMPAT_STATIC" ]; then \
				$$SDK_CC -Wall -O2 -fPIC -c \
					-o /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o \
					$$GLIBC_COMPAT_STATIC; \
				$$SDK_AR rcs /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/libglibc-compat-static.a \
					/tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o; \
				rm -f /tmp/sdk-overlay/$$SDK_TOP/sdk/lib/glibc-compat-static.o; \
			fi; \
		fi; \
		gunzip $$SDK_TGZ && \
		tar rf $${SDK_TGZ%.tar.gz}.tar -C /tmp/sdk-overlay $$SDK_TOP && \
		gzip $${SDK_TGZ%.tar.gz}.tar; \
		rm -rf /tmp/sdk-overlay; \
	fi
endef

define PREPARE_REPACK
	$(if $(1),$(call CHECK_SIZE,$(1),$(2)))
	$(if $(3),$(call CHECK_SIZE,$(3),$(4)))
	$(call REPACK_FIRMWARE,$(1),$(3),$(5))
endef

# The headroom line exists because "fits" and "only just fits" read the same in
# a green build. hi3519v101_lite sat at exactly 5120KB of a 5120KB cap for weeks
# -- reported, passing, and one 34-line edit from the overflow it hit on
# 2026-08-18. 32KB is the threshold because what tips these boards is a change
# to the shared overlay, which is single-digit KB at a time; a board under that
# is a couple of ordinary commits from red, and a board over it is not.
define CHECK_SIZE
	$(eval FILE_SIZE = $(shell expr $(shell stat -c %s $(TARGET)/images/$(1) || echo 0) / 1024))
	if test $(FILE_SIZE) -eq 0; then exit 1; fi
	echo - $(1): [$(FILE_SIZE)KB/$(2)KB]
	if test $(FILE_SIZE) -gt $(2); then \
		echo -- size exceeded by: $(shell expr $(FILE_SIZE) - $(2))KB; exit 1; fi
	if test $(shell expr $(2) - $(FILE_SIZE)) -lt 32; then \
		echo -- headroom warning: $(1) has $(shell expr $(2) - $(FILE_SIZE))KB left of $(2)KB; fi
endef

# The build identity is not computed here: it is read back from the rootfs that
# is about to be packaged, where general/scripts/rootfs_script.sh wrote it. That
# makes the tarball's name and /etc/openipc-build-id on a running camera the same
# string by construction, so "which image is this" and "what is flashed" cannot
# disagree.
#
# They used to be computed independently, and this line was
#
#   $(eval OPENIPC_BUILD_ID ?= $(shell git rev-parse --short HEAD ...)-$(shell date ...))
#
# which names an artefact after its last *commit*. An image built before
# committing was therefore stamped with its predecessor's hash, so two images
# with genuinely different contents differed in name only by the timestamp --
# and flashing the wrong one of the pair cost an evening spent debugging a
# package that had been in the image all along. Uncommitted work now shows up
# as a -dirty suffix and can never collide with the commit it came from.
#
# The fallback only fires when there is no staged rootfs to read (a bare `make
# repack`), and says so rather than inventing a plausible-looking hash.
#
# LATEST is a stable name for the newest build of this soc/type/variant.
# Timestamped tarballs accumulate here for a good reason -- going back to
# yesterday's image matters during a bring-up -- but a flashing script that has
# to pick one out of a directory listing will eventually pick wrong. The symlink
# is the one to flash; the timestamped names are the archive.
# The sensor is part of the image, so it is part of the image's name.
#
# A board that sets BR2_OPENIPC_SNS_MODEL ships that sensor's tuning blob and no
# other -- on ssc333 that is 1387KB of a 5120KB partition, which is why it is
# set there at all. Flashed onto the same SoC carrying a different part, such an
# image streams and gets the colour wrong, which is the kind of failure nobody
# traces back to the filename. So the filename says it: ssc333_sc3336, t31_gc2053.
#
# Boards that ship every blob are named as before. The quotes come from the
# defconfig being included as a makefile, and the shell strips them out of the
# tar and ln arguments below -- but $(if ...) would see "" as a value, so the
# sensor has to be unquoted here rather than left to the shell.
#
# Only the archive is renamed. The members inside it keep the plain SoC suffix
# -- uImage.ssc333, rootfs.squashfs.ssc333 -- because that is the name
# sysupgrade looks for on the camera, derived from BUILD_PLATFORM's first
# token. Renaming those would make an image that no board can unpack.
IMAGE_SNS = $(strip $(subst ",,$(BR2_OPENIPC_SNS_MODEL)))
IMAGE_SOC = $(BR2_OPENIPC_SOC_MODEL)$(if $(IMAGE_SNS),_$(IMAGE_SNS))

define REPACK_FIRMWARE
	$(eval OPENIPC_BUILD_ID ?= $(or $(shell cat $(TARGET)/target/etc/openipc-build-id 2>/dev/null),unknown-$(shell date -u +%Y%m%dT%H%M%SZ)))
	cd $(TARGET)/images && if test -e rootfs.tar; then mv -f rootfs.tar rootfs.$(BR2_OPENIPC_SOC_MODEL).tar; fi
	$(if $(1),cd $(TARGET)/images && if test -e $(1); then mv -f $(1) $(1).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(2),cd $(TARGET)/images && if test -e $(2); then mv -f $(2) $(2).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(1),cd $(TARGET)/images && md5sum $(1).$(BR2_OPENIPC_SOC_MODEL) > $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(2),cd $(TARGET)/images && md5sum $(2).$(BR2_OPENIPC_SOC_MODEL) > $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(1),$(eval KERNEL = $(1).$(BR2_OPENIPC_SOC_MODEL) $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval KERNEL =))
	$(if $(2),$(eval ROOTFS = $(2).$(BR2_OPENIPC_SOC_MODEL) $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval ROOTFS =))
	$(eval ARCHIVE = openipc.$(IMAGE_SOC)-$(3)-$(BR2_OPENIPC_VARIANT)-$(OPENIPC_BUILD_ID).tgz)
	$(eval LATEST = openipc.$(IMAGE_SOC)-$(3)-$(BR2_OPENIPC_VARIANT)-latest.tgz)
	cd $(TARGET)/images && tar -czf $(ARCHIVE) $(KERNEL) $(ROOTFS)
	cd $(TARGET)/images && ln -sfn $(ARCHIVE) $(LATEST)
	echo "- image: $(ARCHIVE)"
	echo "-        $(LATEST) -> $(OPENIPC_BUILD_ID)"
	rm -f $(TARGET)/images/*.md5sum
endef
