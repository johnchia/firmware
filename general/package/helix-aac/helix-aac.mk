################################################################################
#
# helix-aac
#
################################################################################

# RealNetworks' fixed-point AAC decoder has no release of its own and no
# repository of its own: it is vendored inside ESP8266Audio, an Arduino audio
# library, as src/libhelix-aac. So this package downloads that library and
# builds one subdirectory of it, which is what every other Raptor build does
# too -- build-standalone.sh and build-asan.sh both compile the same directory
# out of a clone.
#
# Pinned to the sha raptor's build-standalone.sh pins, so an image and a
# developer's standalone build decode with the same code.
HELIX_AAC_VERSION = 05f2fb0045cc294b4e0d1a1a9747b89c22c1fea4
HELIX_AAC_SITE = $(call github,earlephilhower,ESP8266Audio,$(HELIX_AAC_VERSION))

# Two licences, and neither covers the other: the decoder sources carry
# RealNetworks' RPSL/RCSL notice (the header at the top of every .c), while the
# repository carrying them is GPL-3.0. Only the decoder is built here, and none
# of it reaches the rootfs -- rsd links the archive statically -- but both
# belong in the manifest.
HELIX_AAC_LICENSE = RPSL-1.0 or RCSL (decoder), GPL-3.0 (containing repository)
HELIX_AAC_LICENSE_FILES = LICENSE src/libhelix-aac/aacdec.c

# Static archive and one header for rsd to link against; nothing on the target.
HELIX_AAC_INSTALL_STAGING = YES
HELIX_AAC_INSTALL_TARGET = NO

HELIX_AAC_SRC = $(@D)/src/libhelix-aac

# aaccommon.h includes <Arduino.h> and <pgmspace.h> -- the flash-addressing
# helpers of a microcontroller that cannot hold this decoder's tables in RAM.
# On Linux a table is just a table, so the two headers are stubbed away rather
# than the sources being patched: a patch would need rebasing on every bump,
# and these few macros will not change. The same stubs, spelled the same way,
# are in raptor's build-standalone.sh and build-asan.sh.
define HELIX_AAC_STUBS
	mkdir -p $(@D)/stubs
	printf '%s\n' '#ifndef PGMSPACE_H' '#define PGMSPACE_H' \
		'#include <stdint.h>' '#include <string.h>' \
		'#define PROGMEM' '#define PGM_P const char *' \
		'#define pgm_read_byte(x) (*(const uint8_t *)(x))' \
		'#define pgm_read_word(x) (*(const uint16_t *)(x))' \
		'#define pgm_read_dword(x) (*(const uint32_t *)(x))' \
		'#define memcpy_P memcpy' '#endif' >$(@D)/stubs/pgmspace.h
	printf '%s\n' '#ifndef ARDUINO_H' '#define ARDUINO_H' \
		'#include <stdint.h>' '#include "pgmspace.h"' '#endif' \
		>$(@D)/stubs/Arduino.h
endef

# There is no makefile to call: the directory is a pile of .c files that the
# Arduino IDE would have compiled itself.
#
# USE_DEFAULT_STDLIB takes the platform's memcpy and friends instead of the
# decoder's own. -w because this is 2005 code shipped as-is, and its warnings
# are not ours to fix or to fail an image build on.
#
# ARDUINO is not a lie about the host, it is how this copy spells "no assembly,
# use the portable C". Helix ships hand-written ARM assembly, and ESP8266Audio
# disabled it by renaming the macros that select it -- assembly.h tests
# `XXX__arm` and `XXXX__arm__`, which nothing defines -- leaving ARM to fall off
# the end of the chain into '#error Unsupported platform'. ARDUINO selects the
# generic branch that mips and powerpc also take. Raptor's own standalone build
# does not need this only because it targets mips, which that branch names
# outright.
#
# It is a build-time flag and nothing more: aacdec.h, the only header a consumer
# sees, has a real `__GNUC__ && __arm__` branch, so rsd compiles against this
# without knowing any of the above.
define HELIX_AAC_BUILD_CMDS
	$(HELIX_AAC_STUBS)
	cd $(HELIX_AAC_SRC) && for f in *.c; do \
		$(TARGET_CC) $(TARGET_CFLAGS) -w -DUSE_DEFAULT_STDLIB -DARDUINO \
			-I$(@D)/stubs -I. -c $$f -o $${f%.c}.o || exit 1; \
	done
	$(TARGET_AR) rcs $(@D)/libhelix-aac.a $(HELIX_AAC_SRC)/*.o
endef

# aacdec.h alone: it is the whole public API and, unlike the other headers,
# includes nothing at all -- so a consumer never reaches the stubbed Arduino
# headers, which are a detail of building this library rather than of using it.
define HELIX_AAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 644 $(@D)/libhelix-aac.a $(STAGING_DIR)/usr/lib/libhelix-aac.a
	$(INSTALL) -D -m 644 $(HELIX_AAC_SRC)/aacdec.h $(STAGING_DIR)/usr/include/aacdec.h
endef

$(eval $(generic-package))
