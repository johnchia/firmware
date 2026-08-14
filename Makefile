BR_VER = 2024.02.10
BR_MAKE = $(MAKE) -C $(TARGET)/buildroot-$(BR_VER) BR2_EXTERNAL=$(PWD)/general O=$(TARGET)
BR_LINK = https://github.com/buildroot/buildroot/archive
BR_FILE = /tmp/buildroot-$(BR_VER).tar.gz
BR_CONF = $(TARGET)/openipc_defconfig
TARGET ?= $(PWD)/output
export CMAKE_POLICY_VERSION_MINIMUM := 3.5

# Use an explicit local checkout for Divinus development without changing the
# release commit pinned by the Buildroot package.
ifneq ($(strip $(DIVINUS_SRCDIR)),)
BR_MAKE += DIVINUS_OVERRIDE_SRCDIR=$(abspath $(DIVINUS_SRCDIR))
endif

# Raptor has no pinned release to fall back on: it is four sibling repositories
# and its SigmaStar backend is not upstream yet, so a local checkout is the only
# source. RAPTOR_SRCDIR is the *parent* directory holding raptor, raptor-hal,
# raptor-common, raptor-ipc and compy.
# The package is raptor-streaming because Buildroot already has a `raptor`
# (raptor2, the RDF library); the knob here keeps the short name.
ifneq ($(strip $(RAPTOR_SRCDIR)),)
BR_MAKE += RAPTOR_STREAMING_OVERRIDE_SRCDIR=$(abspath $(RAPTOR_SRCDIR))
endif

# An overridden source tree is invisible to Buildroot's staleness tracking. The
# package's .stamp_built has no prerequisite anywhere inside RAPTOR_SRCDIR, so a
# plain image build after editing the daemons re-uses whatever binaries the
# previous build left behind -- and the image still gets a current-looking
# /etc/openipc-build-id, because that id describes *this* repository and the
# raptor checkout is not part of it. Observed on 2026-07-26: an image built to
# carry an audio fix, whose rad was the build from before the fix, reported as
# a successful build of the current tree.
#
# Dropping the package's build stamps before the image build costs one relink
# and makes the image mean what its build id says. It is a separate make
# invocation rather than Buildroot's <pkg>-rebuild for the reason documented at
# raptor-local below: on GNU make 4.3 that rule's .WAIT is ignored and it can
# evaluate the build before the stamps are gone.
#
# (A DIVINUS_SRCDIR build has the identical exposure and is left alone here.)
ifneq ($(strip $(RAPTOR_SRCDIR)),)
RAPTOR_RESYNC = $(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
	RAPTOR_SRCDIR="$(abspath $(RAPTOR_SRCDIR))" br-raptor-streaming-clean-for-rebuild
else
RAPTOR_RESYNC = true
endif

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
	@$(RAPTOR_RESYNC)
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

.PHONY: raptor-local

# Re-sync the local checkout and rebuild just Raptor, leaving the rest of the
# image alone. Use this to iterate on the daemons without a full image build.
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
raptor-local:
	@test -n "$(strip $(RAPTOR_SRCDIR))" || { \
		echo "RAPTOR_SRCDIR is required (parent directory of the raptor repos)"; exit 2; }
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		RAPTOR_SRCDIR="$(abspath $(RAPTOR_SRCDIR))" \
		br-raptor-streaming-clean-for-rebuild
	@$(MAKE) --no-print-directory BOARD=$(BOARD) TARGET=$(TARGET) \
		RAPTOR_SRCDIR="$(abspath $(RAPTOR_SRCDIR))" br-raptor-streaming

defconfig: prepare
	@echo --- $(or $(CONFIG),$(error variable BOARD not found))
	@cat $(CONFIG) $(PWD)/general/openipc.fragment > $(BR_CONF)
	@grep -s '^BR2_GLOBAL_PATCH_DIR=' $(CONFIG) >> $(BR_CONF) || true
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
	@printf "Raptor development (RAPTOR_SRCDIR is the parent of the raptor repos):\n \
	- make BOARD=ssc30kq_raptor RAPTOR_SRCDIR=~/raptor\n \
	- make BOARD=ssc30kq_raptor RAPTOR_SRCDIR=~/raptor raptor-local\n\n"
	@printf "Full NOR image from locally built pieces. A modified bootloader\n \
	reaches an image no other way: repack_firmware.sh and the CI workflow both\n \
	download u-boot from the release server.\n \
	- make BOARD=<board> UBOOT_BIN=~/u-boot-sigmastar/BOOT-<soc>.bin fullimage\n \
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
# Requires UBOOT_BIN because there is no sane default: this repo does not build
# u-boot, and silently reaching for a downloaded one would defeat the point.
fullimage: defconfig
	@test -n "$(strip $(UBOOT_BIN))" || { \
		echo "UBOOT_BIN is required (the assembled boot container, not u-boot.bin)"; \
		echo "e.g. make BOARD=$(BOARD) UBOOT_BIN=~/u-boot-sigmastar/BOOT-ssc377qe.bin fullimage"; \
		exit 2; }
	@$(SHELL) $(PWD)/general/scripts/make_full_image.sh \
		"$(abspath $(UBOOT_BIN))" \
		"$(TARGET)/images" \
		"$(subst ",,$(BR2_OPENIPC_SOC_MODEL))" \
		"$(TARGET)/images/openipc-$(subst ",,$(BR2_OPENIPC_SOC_MODEL))-nor-full.bin" \
		$(if $(strip $(SNI_REF)),"$(abspath $(SNI_REF))")

# The rootfs size limit is a property of the *partition table*, not of the flash
# chip. Deriving it from BR2_OPENIPC_FLASH_SIZE assumes the two agree, and they
# need not: ssc30kq has 16MB of NOR but gives the rootfs only 0x500000 (5120KB),
# the remaining 8.5MB going to the overlay --
#
#   0x000000250000-0x000000750000 : "rootfs"
#   0x000000750000-0x000001000000 : "rootfs_data"
#
# so a 16MB board was checked against 8192KB, passed at 5160KB, and flashcp then
# refused the image as "bigger than /dev/mtd3". A limit larger than the partition
# is not a limit; it moves the failure from the build, where it is a number, to
# the flash, where it is a camera in an unknown state. Boards whose layout does
# not follow from the chip size state the real figure in
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

define CHECK_SIZE
	$(eval FILE_SIZE = $(shell expr $(shell stat -c %s $(TARGET)/images/$(1) || echo 0) / 1024))
	if test $(FILE_SIZE) -eq 0; then exit 1; fi
	echo - $(1): [$(FILE_SIZE)KB/$(2)KB]
	if test $(FILE_SIZE) -gt $(2); then \
		echo -- size exceeded by: $(shell expr $(FILE_SIZE) - $(2))KB; exit 1; fi
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
define REPACK_FIRMWARE
	$(eval OPENIPC_BUILD_ID ?= $(or $(shell cat $(TARGET)/target/etc/openipc-build-id 2>/dev/null),unknown-$(shell date -u +%Y%m%dT%H%M%SZ)))
	cd $(TARGET)/images && if test -e rootfs.tar; then mv -f rootfs.tar rootfs.$(BR2_OPENIPC_SOC_MODEL).tar; fi
	$(if $(1),cd $(TARGET)/images && if test -e $(1); then mv -f $(1) $(1).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(2),cd $(TARGET)/images && if test -e $(2); then mv -f $(2) $(2).$(BR2_OPENIPC_SOC_MODEL); fi)
	$(if $(1),cd $(TARGET)/images && md5sum $(1).$(BR2_OPENIPC_SOC_MODEL) > $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(2),cd $(TARGET)/images && md5sum $(2).$(BR2_OPENIPC_SOC_MODEL) > $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(1),$(eval KERNEL = $(1).$(BR2_OPENIPC_SOC_MODEL) $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval KERNEL =))
	$(if $(2),$(eval ROOTFS = $(2).$(BR2_OPENIPC_SOC_MODEL) $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval ROOTFS =))
	$(eval ARCHIVE = openipc.$(BR2_OPENIPC_SOC_MODEL)-$(3)-$(BR2_OPENIPC_VARIANT)-$(OPENIPC_BUILD_ID).tgz)
	$(eval LATEST = openipc.$(BR2_OPENIPC_SOC_MODEL)-$(3)-$(BR2_OPENIPC_VARIANT)-latest.tgz)
	cd $(TARGET)/images && tar -czf $(ARCHIVE) $(KERNEL) $(ROOTFS)
	cd $(TARGET)/images && ln -sfn $(ARCHIVE) $(LATEST)
	echo "- image: $(ARCHIVE)"
	echo "-        $(LATEST) -> $(OPENIPC_BUILD_ID)"
	rm -f $(TARGET)/images/*.md5sum
endef
