################################################################################
#
# sigmastar-osdrv-sensors
#
################################################################################

# johnchia/openipc-sensors, branch integration/sigmastar-fixes, pinned to a sha.
# The branch is upstream master with the one fix upstream does not carry yet
# merged on top, and it exists so that tracking upstream and keeping that fix
# are not the same decision: master here is a plain mirror of upstream and
# stays that way, and this is the only place the fork adds anything. Sync it by
# merging upstream in, never by rebasing -- the pin has to name a commit that
# stays reachable.
#
# ORIENTATION. Nine SigmaStar drivers stage the mirror/flip register in
# pCus_SetOrien but never write params->cur_orien back, so cur_orien stays at
# its zero-initialised CUS_ORIT_M0F0 and each resolution init re-applies that
# identity value over whatever was asked for. Orientation has to be set before
# the sensor is enabled on these SoCs, which is exactly the order that loses
# it, so the register never sees mirror or flip. sensor_sc2335_mipi.c and
# sensor_sc2239_mipi.c already did it right; this makes the rest match.
# sc850sl is deliberately left alone: it has no cur_orien to record, because
# its resolution init has the re-apply call commented out and it never had the
# bug.
#
# Upstream took this as OpenIPC/sensors#2 for sc3336 alone, narrowed at their
# request. The eight drivers that narrowing left out are what this branch
# carries: infinity6 sc3335; infinity6b0 sc200ai, sc223a, sc2336, sc3335,
# sc3338; infinity6c sc4336p; infinity6e gc2093. That is the set the images
# were built and verified with, and the branch goes away when it lands
# upstream.
#
# The infinity6c imx335 driver (#3) and the sc450ai model ID fix (#4) were
# carried here too and are upstream now, so the fork no longer adds them.
#
# The branch also carries two infinity6c drivers that exist nowhere else: the
# sc5235 driver, taken unmodified from the SSC377 SDK, and an sc5239 driver
# built from it that programs the part as SigmaStar's own sc5239 driver does
# (the two answer the same sensor ID, so a board names the 5239 in its env).
# Both stream on an SSC377D board. They should go upstream as their own pull
# requests.
#
# IMX335 ON INFINITY6C. Three changes to TipoMan's driver, each its own commit
# on the fork's imx335-i6c-1440p60 branch so they can go upstream alone:
# - pCus_SetFPS no longer keeps an exposure stretch as the base frame length.
#   The handle starts with expo_lines at 5000, so a streamer that sets the rate
#   while building the pipeline latched every mode shorter than that at VMAX
#   5008: the 90 fps mode ran at 54, the 30 fps table at 24.7.
# - Every linear table writes the whole readout window, so no mode depends on
#   the sensor having been reset since the last one.
# - Mode 6, 2560x1440@60, a centred 16:9 window for 1080p60. It is appended,
#   so no index moves, and a streamer that takes the first mode covering its
#   size and rate still lands on 2560x1920@60 (mode 3) for 1080p60; it has to
#   ask for 6.
# Naming a sha rather than HEAD is worth keeping even after the fork does go
# away: the package used to build whatever upstream had on the day.
SIGMASTAR_OSDRV_SENSORS_SITE = $(call github,johnchia,openipc-sensors,$(SIGMASTAR_OSDRV_SENSORS_VERSION))
SIGMASTAR_OSDRV_SENSORS_VERSION = 7d1f4028ad02c0edcea7e4030094d14d4a7fc15d

SIGMASTAR_OSDRV_SENSORS_MODULE_SUBDIRS = $(OPENIPC_SOC_VENDOR)/$(OPENIPC_SOC_FAMILY)
SIGMASTAR_OSDRV_SENSORS_MODULE_MAKE_OPTS = \
	SENSOR_VERSION=$(OPENIPC_SOC_FAMILY) \
	INSTALL_MOD_DIR=$(OPENIPC_SOC_VENDOR) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
