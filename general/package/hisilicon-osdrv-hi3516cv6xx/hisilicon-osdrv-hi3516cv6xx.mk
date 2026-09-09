################################################################################
#
# hisilicon-osdrv-hi3516cv6xx
#
# Load script + vendor userspace MPP libraries for the Hi3516CV6xx (V5)
# family. Kernel modules and sensor drivers are no longer shipped here:
#  * kernel modules now built against the running openipc/linux tree by
#    hisilicon-opensdk (see ../hisilicon-opensdk/hisilicon-opensdk.mk).
#    Shipping prebuilt vendor .ko caused init-time hangs because struct
#    module / vermagic / config layouts didn't match openipc's kernel.
#  * sensor drivers now built from vendor SDK source by hisilicon-opensdk
#    via libraries/sensor/hi3516cv6xx/ and HISILICON_OPENSDK_SENSORS_hi3516cv6xx.
#
# Vendor MPP userspace .so blobs ship from files/lib/ — no openhisilicon
# V5 source mirror exists. The install list below is the transitive
# NEEDED closure of the majestic binary against the vendor lib set
# (computed via readelf -d), with libopus.so excluded because
# BR2_PACKAGE_OPUS_OPENIPC + BR2_PACKAGE_OPUS_OPENIPC_HISI_SHIM build
# an open equivalent that covers both the standard opus_* API and the
# 6 HiSi-only ot_opus_* extensions used by libss_mpi_audio_adp.so (the
# shim source lives in general/package/opus-openipc/src/ot_opus_shim.c
# and is baked into libopus.so by the package's gated POST_EXTRACT
# hook). The 13 libs not in the closure (libss_mpi_aibnr/bla/cipher/
# devstat/km/otp/smartae/syskol/uvc, libss_bcd,
# libmbedtls_harden_adapt, libsvp_aicpu, libvqe_common) save ~660 KB
# and are intentionally omitted.
#
################################################################################

HISILICON_OSDRV_HI3516CV6XX_VERSION =
HISILICON_OSDRV_HI3516CV6XX_SITE =
HISILICON_OSDRV_HI3516CV6XX_LICENSE = MIT
HISILICON_OSDRV_HI3516CV6XX_LICENSE_FILES = LICENSE

# Vendor MPP userspace .so files. The core set is what any streamer on this
# family reaches: the MPI entry points, the ISP and its algorithm libraries,
# and the VQE front end.
HISILICON_OSDRV_HI3516CV6XX_MPP_LIBS = \
	libacs.so libbnr.so libcalcflicker.so \
	libdehaze.so libdnvqe.so libdrc.so \
	libextend_stats.so libir_auto.so libldci.so \
	libot_mpi_isp.so libot_osal.so libsecurec.so \
	libss_mpi.so libss_mpi_ae.so libss_mpi_audio.so libss_mpi_audio_adp.so \
	libss_mpi_awb.so libss_mpi_isp.so \
	libss_mpi_sysbind.so libss_mpi_sysmem.so \
	libupvqe.so libvoice_engine.so \
	libvqe_aec.so libvqe_agc.so libvqe_anr.so libvqe_eq.so \
	libvqe_hpf.so libvqe_hs.so

# The rest of majestic's NEEDED closure, which nothing else on this family
# reaches. 1681 KB, and on a 5056 KB rootfs that is the difference between
# raptor fitting and not.
#
# Determined from the image rather than assumed: the transitive closure of
# every lib*.so name the eight raptor daemons carry -- DT_NEEDED and dlopen
# strings both, since the HAL reaches the MPI through dlopen -- contains none
# of these. raptor encodes AAC with faac and decodes it with helix in
# userspace, so the vendor codec chain is majestic's alone; the NPU, the AI
# ISP and IVE have no raptor caller at all.
#
# The VQE split is the one judgement call here. libupvqe and libvoice_engine ARE
# in raptor's closure and stay, with the six small per-stage libraries behind
# them -- aec, agc, anr, eq, hpf, hs -- because those are what an AEC or ANR
# dlopen would reach and they are 247 KB between them. The three big ones,
# talkv2, record and res at 624 KB, are the full-duplex talk and record
# pipelines, which raptor has no path to; they move with majestic. If a raptor
# board ever loses audio processing at runtime rather than at link time, this is
# the first place to look.
ifeq ($(BR2_PACKAGE_MAJESTIC),y)
HISILICON_OSDRV_HI3516CV6XX_MPP_LIBS += \
	libaac_comm.so libaac_dec.so libaac_enc.so \
	libaac_sbr_dec.so libaac_sbr_enc.so \
	libaiisp.so \
	libmp3_dec.so libmp3_enc.so libmp3_lame.so \
	libss_ivs_md.so libss_mpi_ive.so libsvp_acl.so \
	libvqe_record.so libvqe_res.so libvqe_talkv2.so
endif

# Sensor .so blobs shipped from vendor flash where the openhisilicon
# V5 SDK has no source mirror. Extracted from the original CV608 DEMO
# board flash (Hi3516CV610_MPP_V1.0.1.0 B040, Sep 2024). Source-built
# sensors (gc4023, os04d10, sc4336p, sc450ai, sc500ai, sc431hai) come
# from hisilicon-opensdk and are not duplicated here.
HISILICON_OSDRV_HI3516CV6XX_SENSOR_BLOBS = \
	libsns_imx307.so \
	libsns_os02m10.so

# ...but not on a raptor target, which is built for one board rather than
# published for a family. The cv608 bench board is an os04d10, hisilicon-opensdk
# already ships that one alone for the same reason, and these two are 155 KB of
# an 8 MB NOR that also has to hold a wifi driver, cfg80211 and a supplicant in
# AP mode. A published cv6xx image keeps them.
ifeq ($(OPENIPC_VARIANT),raptor)
HISILICON_OSDRV_HI3516CV6XX_SENSOR_BLOBS =
endif

define HISILICON_OSDRV_HI3516CV6XX_INSTALL_TARGET_CMDS

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(HISILICON_OSDRV_HI3516CV6XX_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(foreach lib,$(HISILICON_OSDRV_HI3516CV6XX_MPP_LIBS), \
		$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(HISILICON_OSDRV_HI3516CV6XX_PKGDIR)/files/lib/$(lib) ; \
	)

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/sensors
	$(foreach lib,$(HISILICON_OSDRV_HI3516CV6XX_SENSOR_BLOBS), \
		$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/sensors $(HISILICON_OSDRV_HI3516CV6XX_PKGDIR)/files/sensor/$(lib) ; \
	)

	# ipctool's i2c probe reports the OmniVision OS02M10 chip ID
	# (0x5302) as "SP2308" (rebadged SuperPix marker — same silicon).
	# Symlink so devices whose u-boot env still carries that legacy
	# name resolve to the correct driver without a manual fix.
	# ...and only where that driver is actually installed. The raptor
	# target ships no blob sensors, and a dangling symlink there would be
	# dead weight -- sns_usable's -e follows it and correctly answers no,
	# so it would buy nothing and confuse anyone reading the directory.
	[ -f $(TARGET_DIR)/usr/lib/sensors/libsns_os02m10.so ] && \
		ln -sf libsns_os02m10.so $(TARGET_DIR)/usr/lib/sensors/libsns_sp2308.so || true

endef

$(eval $(generic-package))
