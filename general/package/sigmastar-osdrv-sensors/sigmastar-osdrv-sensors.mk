################################################################################
#
# sigmastar-osdrv-sensors
#
################################################################################

# johnchia/openipc-sensors, branch fix/setorien-records-cur-orien, pinned to a
# sha because upstream HEAD does not carry the fix. Ten SigmaStar drivers stage
# the mirror/flip register in pCus_SetOrien but never write params->cur_orien
# back, so cur_orien stays at its zero-initialised CUS_ORIT_M0F0 and each
# resolution init re-applies that identity value over whatever was asked for.
# Orientation has to be set before the sensor is enabled on these SoCs, which
# is exactly the order that loses it, so the register never sees mirror or
# flip. sensor_sc2335_mipi.c and sensor_sc2239_mipi.c already did it right;
# this makes the rest match.
#
# Sent upstream as OpenIPC/sensors#2 and open at the time of writing. When it
# merges, this goes back to `openipc,sensors` at HEAD and the pin disappears.
#
# The version was `HEAD` before this, so the package built whatever upstream
# had that day. Naming a sha is worth keeping even after the fork goes away.
SIGMASTAR_OSDRV_SENSORS_SITE = $(call github,johnchia,openipc-sensors,$(SIGMASTAR_OSDRV_SENSORS_VERSION))
SIGMASTAR_OSDRV_SENSORS_VERSION = 6fd5abe4ded9a9ef1e99569743b5c250335cf95a

SIGMASTAR_OSDRV_SENSORS_MODULE_SUBDIRS = $(OPENIPC_SOC_VENDOR)/$(OPENIPC_SOC_FAMILY)
SIGMASTAR_OSDRV_SENSORS_MODULE_MAKE_OPTS = \
	SENSOR_VERSION=$(OPENIPC_SOC_FAMILY) \
	INSTALL_MOD_DIR=$(OPENIPC_SOC_VENDOR) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
