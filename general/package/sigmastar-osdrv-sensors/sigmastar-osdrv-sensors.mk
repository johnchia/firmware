################################################################################
#
# sigmastar-osdrv-sensors
#
################################################################################

# johnchia/openipc-sensors, branch integration/sigmastar-fixes, pinned to a sha.
# The branch is upstream master with the two fixes upstream does not carry yet
# replayed on top, and it exists so that tracking upstream and keeping those
# fixes are not the same decision: master here is a plain mirror of upstream and
# stays that way, and this is the only place the fork adds anything.
#
# ORIENTATION. Nine SigmaStar drivers stage the mirror/flip register in
# pCus_SetOrien but never write params->cur_orien back, so cur_orien stays at
# its zero-initialised CUS_ORIT_M0F0 and each resolution init re-applies that
# identity value over whatever was asked for. Orientation has to be set before
# the sensor is enabled on these SoCs, which is exactly the order that loses
# it, so the register never sees mirror or flip. sensor_sc2335_mipi.c and
# sensor_sc2239_mipi.c already did it right; this makes the rest match.
# sc850sl is deliberately left alone: it has no cur_orien to record.
#
# Sent upstream as OpenIPC/sensors#2, narrowed there to sc3336 alone at their
# request and still open. The broader version is what the images were built and
# verified with, so it is what this branch keeps.
#
# MODEL ID. sensor_sc450ai_mipi.c set its model ID with SENSOR_DMSG, the debug
# macro, which expands to nothing at the shipped SENSOR_DBG == 0 -- so
# MI_SNR_GetPlaneInfo reported an empty sensor name and a userspace ISP that
# names its IQ tuning after the sensor silently loaded none. Verified on an
# SSC377D + SC450AI.
#
# Both go back to `openipc,sensors` at a sha the moment they merge, and this
# branch disappears with them. The version was `HEAD` before any of this, so the
# package built whatever upstream had that day; naming a sha is worth keeping
# even after the fork goes away.
SIGMASTAR_OSDRV_SENSORS_SITE = $(call github,johnchia,openipc-sensors,$(SIGMASTAR_OSDRV_SENSORS_VERSION))
SIGMASTAR_OSDRV_SENSORS_VERSION = f4f1c0b96581d93bcf2f2b2d2fc237fcb763f106

SIGMASTAR_OSDRV_SENSORS_MODULE_SUBDIRS = $(OPENIPC_SOC_VENDOR)/$(OPENIPC_SOC_FAMILY)
SIGMASTAR_OSDRV_SENSORS_MODULE_MAKE_OPTS = \
	SENSOR_VERSION=$(OPENIPC_SOC_FAMILY) \
	INSTALL_MOD_DIR=$(OPENIPC_SOC_VENDOR) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
