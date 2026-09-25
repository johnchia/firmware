# How `make BOARD=<camera>` finds its configuration.
#
# A camera is a directory, br-ext-chip-<vendor>/cameras/<camera>/, holding a
# Kconfig fragment (camera.conf) that names the SoC target it layers on
# (BR2_OPENIPC_CAMERA_BASE) and the camera's own facts: the sensor, the radio,
# the baked environment, the bootloader's pins. It is not a defconfig and
# never a copy of one. The Makefile includes this file before it resolves
# BOARD, and it resolves a camera first; anything else falls through to the
# Makefile's own `grep -m1` over the defconfigs, exactly as before.
#
# The composition is text: the `defconfig` recipe writes the base defconfig,
# then camera.conf, then general/openipc.fragment into one file, and
# Buildroot's defconfig merge lets later lines win. So a camera can add
# packages and override an SoC value, and the shared fragment still wins over
# both -- the ordering the tree already relies on.
#
# What a camera may set is a short allowlist, checked by
# .github/scripts/test_cameras.sh. The rule of thumb: if the fragment wants a
# symbol the allowlist refuses, that is an SoC or variant fact, and the camera
# wants a different base rather than a longer fragment.
#
# Kept out of the Makefile so the upstream-visible diff there stays at one
# include and one line in the defconfig recipe.

CAMERA_DIR := $(patsubst %/camera.conf,%,$(wildcard br-ext-chip-*/cameras/$(BOARD)/camera.conf))

ifneq ($(CAMERA_DIR),)
ifneq ($(words $(CAMERA_DIR)),1)
$(error BOARD=$(BOARD) matches more than one camera directory: $(CAMERA_DIR))
endif
CAMERA_CONF := $(CAMERA_DIR)/camera.conf
CAMERA_BASE := $(shell sed -n 's/^BR2_OPENIPC_CAMERA_BASE="\(.*\)"$$/\1/p' $(CAMERA_CONF))
# Exact, not grep -m1: a camera names its base in full, and a prefix match
# here would let a typo pick some other SoC's defconfig.
CAMERA_BASE_CONFIG := $(wildcard br-ext-*/configs/$(CAMERA_BASE)_defconfig)
ifeq ($(CAMERA_BASE_CONFIG),)
$(error $(CAMERA_CONF) names base '$(CAMERA_BASE)', and there is no br-ext-*/configs/$(CAMERA_BASE)_defconfig)
endif
endif

# The overlay list, composed from what exists rather than re-stated by a
# defconfig: the shared overlay always, the family's board/<family>/overlay
# when the directory is there, the camera's overlay when it is there. Written
# as $(BR2_EXTERNAL)-relative paths because that is the form the fragment and
# Buildroot use, and evaluated late (a recursive variable) because the vendor
# and family are only known once the Makefile has included the defconfig.
#
# A defconfig used to re-state the whole list to add its family overlay, and
# the Makefile appended that line back after the fragment. The composed line
# replaces both; a defconfig that still carries one is checked against it in
# the recipe, so the two cannot disagree silently.
CAMERA_VENDOR = $(subst ",,$(BR2_OPENIPC_SOC_VENDOR))
CAMERA_FAMILY = $(subst ",,$(BR2_OPENIPC_SOC_FAMILY))
ROOTFS_OVERLAY_DIRS = $$(BR2_EXTERNAL)/overlay\
	$(if $(wildcard br-ext-chip-$(CAMERA_VENDOR)/board/$(CAMERA_FAMILY)/overlay),\
		$$(BR2_EXTERNAL)/../br-ext-chip-$(CAMERA_VENDOR)/board/$(CAMERA_FAMILY)/overlay)\
	$(if $(wildcard $(CAMERA_DIR)/overlay),$$(BR2_EXTERNAL)/../$(CAMERA_DIR)/overlay)
ROOTFS_OVERLAY_LINE = BR2_ROOTFS_OVERLAY="$(strip $(ROOTFS_OVERLAY_DIRS))"
