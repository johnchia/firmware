################################################################################
#
# faac
#
################################################################################

# Pinned to a commit rather than a release tag, and to *this* commit, because
# it is the one Raptor itself pins: raptor/build-standalone.sh sets the same
# FAAC_VERSION and rad/rad_codec_aac.c is written against the API in it. That
# API is not the historical faac one -- upstream moved from
# faacEncOpen/faacEncEncode to faac_encoder_open/faac_params_init and from
# autotools to Meson, and added HE-AAC v1 (SBR), which the old library never
# had. The commit sits past the 2.1 tag on purpose: rad needs the SONAME 2
# rate control (FAAC_RC_CBR plus max_bit_rate), which is what keeps every
# frame inside AAC-LC's 6144 bits per channel; 2.1 has only a best-effort
# retry limiter, and everything before it lets a frame run over, which
# Apple's decoder refuses. A package tracking "latest faac" would break rad on
# an API change with no version number to warn about it. Keep this in step
# with build-standalone.sh, not with upstream's tags.
FAAC_VERSION = 9e957e24f39f95366f057c5630f8cc3f269fa200
FAAC_SITE = $(call github,knik0,faac,$(FAAC_VERSION))
FAAC_LICENSE = LGPL-2.1
FAAC_LICENSE_FILES = COPYING

# rad links libfaac, so the headers and library have to be in staging. The
# library itself is installed to the target because this is a shared-library
# build; nothing else needs it.
FAAC_INSTALL_STAGING = YES

# The frontend is the `faac` command-line encoder. Raptor only ever calls the
# library, and this is an 8 MiB NOR image.
FAAC_CONF_OPTS = -Dfrontend=false

# Left at the upstream default (1, full quality) deliberately. faac's
# sbr-decimation trades HE-AAC quality for encode speed, and on a single-core
# SSC30KQ that trade may well be worth making -- but it should be made against
# a measurement of rad's actual CPU share, not pre-emptively here. -Dsbr-
# decimation=2 is ~20% faster HE-AAC for a MOS delta of -0.004 if it is needed.

$(eval $(meson-package))
