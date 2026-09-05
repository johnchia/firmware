################################################################################
#
# mbedtls3-openipc
#
################################################################################

# WHY THIS IS A SECOND MBEDTLS AND NOT A BUMP OF THE FIRST
#
# mbedtls-openipc is pinned at 2.25.0 because Majestic is a prebuilt
# proprietary binary linked against the 2.x SONAMEs -- libmbedtls.so.13,
# libmbedcrypto.so.6, libmbedx509.so.1 -- and four of the 87 mbedtls symbols
# it imports do not exist in 3.x at all (the three mbedtls_md5_*_ret, which
# 3.0 renamed, and mbedtls_ssl_conf_export_keys_ext_cb, which it removed).
# Bumping that package in place gives an image whose video daemon dies in the
# dynamic loader. So the 2.x pin stays as long as the blob does, and new code
# gets this package instead.
#
# The two can ship together because 3.6 carries different SONAMEs --
# libmbedtls.so.21, libmbedcrypto.so.16, libmbedx509.so.7 -- so nothing in
# /usr/lib collides and each consumer's DT_NEEDED names what it was built
# against.
#
# THE ONE RULE THAT MATTERS
#
# Both libraries export the same symbol names. The dynamic linker resolves by
# name across the global scope, so a process that ends up with both in its
# closure gets whichever loaded first, against the other's struct layout --
# silent corruption, not a link error. No single binary may reach both series.
# In practice that means libevent-openipc stays on 2.x: it builds
# libevent_mbedtls, which Majestic itself DT_NEEDs.

MBEDTLS3_OPENIPC_VERSION = 3.6.5
MBEDTLS3_OPENIPC_SITE = https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$(MBEDTLS3_OPENIPC_VERSION)
MBEDTLS3_OPENIPC_SOURCE = mbedtls-$(MBEDTLS3_OPENIPC_VERSION).tar.bz2
MBEDTLS3_OPENIPC_LICENSE = Apache-2.0 or GPL-2.0+
MBEDTLS3_OPENIPC_LICENSE_FILES = LICENSE
MBEDTLS3_OPENIPC_CPE_ID_VENDOR = arm
MBEDTLS3_OPENIPC_CPE_ID_PRODUCT = mbed_tls
MBEDTLS3_OPENIPC_INSTALL_STAGING = YES

# The release tarball rather than a git archive: it carries the generated
# files a checkout builds with a Python toolchain we do not have on the
# builder, and it is the artifact upstream signs.
MBEDTLS3_OPENIPC_CONF_OPTS = \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -std=c99" \
	-DENABLE_PROGRAMS=$(if $(BR2_PACKAGE_MBEDTLS3_OPENIPC_PROGRAMS),ON,OFF) \
	-DENABLE_TESTING=OFF \
	-DMBEDTLS_FATAL_WARNINGS=OFF \
	-DCMAKE_INSTALL_PREFIX=$(MBEDTLS3_OPENIPC_PREFIX)

# 3.0 renamed include/mbedtls/config.h to include/mbedtls/mbedtls_config.h.
# Every SED below names the new path; against the old one they would find no
# file, change nothing, and leave DTLS-SRTP off in a build that looks clean.
# There is no zlib hook here at all: MBEDTLS_ZLIB_SUPPORT was removed in 3.0
# and 3.6's own check_config.h #errors on it, which is why this package has no
# compression option to mirror mbedtls-openipc's.
define MBEDTLS3_OPENIPC_ENABLE_SRTP
	$(SED) "s://#define MBEDTLS_SSL_DTLS_SRTP:#define MBEDTLS_SSL_DTLS_SRTP:" \
		$(@D)/include/mbedtls/mbedtls_config.h
	$(SED) "s:#define MBEDTLS_ECP_DP_SECP224K1_ENABLED://#define MBEDTLS_ECP_DP_SECP224K1_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h
	$(SED) "s:#define MBEDTLS_ECP_DP_SECP256K1_ENABLED://#define MBEDTLS_ECP_DP_SECP256K1_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h
endef
MBEDTLS3_OPENIPC_POST_PATCH_HOOKS += MBEDTLS3_OPENIPC_ENABLE_SRTP

# 3.6 defines MBEDTLS_AESCE_C by default and reaches the Armv8 AES instructions
# through vaeseq_u8/vaesmcq_u8. Those need -march=...+crypto, and aesce.c only
# sets that pragma on aarch64, so a 32-bit Armv8 target -- the Cortex-A35 in
# these SigmaStar parts is one -- stops at "inlining failed in call to
# always_inline vaeseq_u8: target specific option mismatch" instead of falling
# back to the C implementation. Buildroot's own package carries no patch for
# this because it never meets the combination.
#
# Keyed on the architecture rather than on a board list: every SoC in this tree
# is 32-bit today, but what makes the accelerated path legal is aarch64, not
# which camera is being built.
ifeq ($(BR2_aarch64)$(BR2_aarch64_be),)
define MBEDTLS3_OPENIPC_DISABLE_AESCE
	$(SED) "s:^#define MBEDTLS_AESCE_C://#define MBEDTLS_AESCE_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h
endef
MBEDTLS3_OPENIPC_POST_PATCH_HOOKS += MBEDTLS3_OPENIPC_DISABLE_AESCE
endif

ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
define MBEDTLS3_OPENIPC_ENABLE_THREADING
	$(SED) "s://#define MBEDTLS_THREADING_C:#define MBEDTLS_THREADING_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h
	$(SED) "s://#define MBEDTLS_THREADING_PTHREAD:#define MBEDTLS_THREADING_PTHREAD:" \
		$(@D)/include/mbedtls/mbedtls_config.h
endef
MBEDTLS3_OPENIPC_PRE_CONFIGURE_HOOKS += MBEDTLS3_OPENIPC_ENABLE_THREADING
ifeq ($(BR2_STATIC_LIBS),y)
MBEDTLS3_OPENIPC_CONF_OPTS += -DLINK_WITH_PTHREAD=ON
endif
endif

ifeq ($(BR2_STATIC_LIBS),y)
MBEDTLS3_OPENIPC_CONF_OPTS += \
	-DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON
else ifeq ($(BR2_SHARED_STATIC_LIBS),y)
MBEDTLS3_OPENIPC_CONF_OPTS += \
	-DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=ON
else ifeq ($(BR2_SHARED_LIBS),y)
MBEDTLS3_OPENIPC_CONF_OPTS += \
	-DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=OFF
endif

define MBEDTLS3_OPENIPC_DISABLE_ASM
	$(SED) '/^#define MBEDTLS_AESNI_C/d' \
		$(@D)/include/mbedtls/mbedtls_config.h
	$(SED) '/^#define MBEDTLS_HAVE_ASM/d' \
		$(@D)/include/mbedtls/mbedtls_config.h
	$(SED) '/^#define MBEDTLS_PADLOCK_C/d' \
		$(@D)/include/mbedtls/mbedtls_config.h
endef

# ARM in thumb mode breaks debugging with asm optimizations
# Microblaze asm optimizations are broken in general
# MIPS R6 asm is not yet supported
ifeq ($(BR2_ENABLE_DEBUG)$(BR2_ARM_INSTRUCTIONS_THUMB)$(BR2_ARM_INSTRUCTIONS_THUMB2),yy)
MBEDTLS3_OPENIPC_POST_CONFIGURE_HOOKS += MBEDTLS3_OPENIPC_DISABLE_ASM
else ifeq ($(BR2_microblaze)$(BR2_MIPS_CPU_MIPS32R6)$(BR2_MIPS_CPU_MIPS64R6),y)
MBEDTLS3_OPENIPC_POST_CONFIGURE_HOOKS += MBEDTLS3_OPENIPC_DISABLE_ASM
endif

# STAGING IS WHERE THE TWO SERIES ACTUALLY COLLIDE
#
# The target does not collide -- the SONAMEs differ -- but staging does, on
# three things both packages own: usr/include/mbedtls/, usr/include/psa/ (2.25
# ships one too) and the unversioned usr/lib/libmbed*.so development symlinks.
# Buildroot has no ordering between two independent external packages, so
# whichever installed second would decide what every consumer compiles against.
#
# The fix is to never write to the shared path, not to move things afterwards.
# Relocating after the install cannot work: by then the directory holds a merge
# of both packages' headers, and carrying it off would take mbedtls-openipc's
# with it and leave the 2.x consumers with nothing. So the install prefix is
# private from configure time, and nothing of this package's ever lands in
# usr/include/mbedtls or usr/lib.
#
# This package moves rather than mbedtls-openipc because moving the old one
# would change the build of the hundred boards that already select it. The cost
# here is one -I and one -L on the consumers that opt in, and they keep writing
# #include <mbedtls/ssl.h> unchanged.
MBEDTLS3_OPENIPC_PREFIX = /usr/mbedtls3

# What a consumer adds to reach this package rather than the 2.x one. Named
# here so a consumer's .mk does not spell the paths out and drift from them.
MBEDTLS3_OPENIPC_CFLAGS = -I$(STAGING_DIR)$(MBEDTLS3_OPENIPC_PREFIX)/include
MBEDTLS3_OPENIPC_LDFLAGS = -L$(STAGING_DIR)$(MBEDTLS3_OPENIPC_PREFIX)/lib

# The private prefix is a build-time arrangement; at runtime the loader has to
# find these on the default search path, because a consumer's DT_NEEDED carries
# a bare SONAME. Only the versioned files go -- the unversioned .so symlinks are
# for linking and stay in staging, where they cannot collide with 2.25's.
ifeq ($(BR2_STATIC_LIBS),)
define MBEDTLS3_OPENIPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	cp -a $(@D)/library/libmbedcrypto.so.* $(TARGET_DIR)/usr/lib/
	cp -a $(@D)/library/libmbedtls.so.* $(TARGET_DIR)/usr/lib/
	cp -a $(@D)/library/libmbedx509.so.* $(TARGET_DIR)/usr/lib/
	# libmbedcrypto DT_NEEDs both of these -- 3.6 builds Everest's X25519 and
	# the p256-m ECC backend as their own shared objects rather than folding
	# them in, so an image with only the three libmbed* files has a crypto
	# library that cannot load. They carry no version in the SONAME and 2.25
	# ships nothing by these names, so /usr/lib is theirs uncontested.
	cp -a $(@D)/3rdparty/everest/libeverest.so $(TARGET_DIR)/usr/lib/
	cp -a $(@D)/3rdparty/p256-m/libp256m.so $(TARGET_DIR)/usr/lib/
endef
else
define MBEDTLS3_OPENIPC_INSTALL_TARGET_CMDS
endef
endif

$(eval $(cmake-package))
