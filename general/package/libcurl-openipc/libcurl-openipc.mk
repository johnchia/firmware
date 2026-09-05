################################################################################
#
# libcurl-openipc
#
################################################################################

LIBCURL_OPENIPC_VERSION = 8.15.0
LIBCURL_OPENIPC_SOURCE = curl-$(LIBCURL_OPENIPC_VERSION).tar.xz
LIBCURL_OPENIPC_SITE = https://curl.se/download
LIBCURL_OPENIPC_DL_SUBDIR = libcurl
LIBCURL_OPENIPC_DEPENDENCIES = host-pkgconf \
	$(if $(BR2_PACKAGE_ZLIB),zlib) \
	$(if $(BR2_PACKAGE_RTMPDUMP),rtmpdump)
LIBCURL_OPENIPC_LICENSE = curl
LIBCURL_OPENIPC_LICENSE_FILES = COPYING
LIBCURL_OPENIPC_INSTALL_STAGING = YES

# We disable NTLM support because it uses fork(), which doesn't work
# on non-MMU platforms. Moreover, this authentication method is
# probably almost never used. See
# http://curl.haxx.se/docs/manpage.html#--ntlm.
# Likewise, there is no compiler on the target, so libcurl-option (to
# generate C code) isn't very useful
# --disable-ntlm-wb and --with-random are gone: curl removed the NTLM winbind
# helper in 8.8.0 and stopped taking a random source on the command line, it
# now picking one itself. --enable-hidden-symbols became --enable-symbol-hiding.
# An unrecognised option is only a configure warning, so these would have gone
# on "working" while doing nothing at all.
#
# --without-libpsl is not optional bookkeeping: curl 8.x treats a missing libpsl
# as a configure error rather than a missing feature, so the build stops unless
# the answer is given. There is no libpsl package in this tree, and a public
# suffix list is a cookie-scoping concern that a camera fetching from fixed
# hosts does not have.
LIBCURL_OPENIPC_CONF_OPTS = --disable-manual \
	--enable-symbol-hiding --disable-curldebug \
	--disable-libcurl-option \
	--without-libpsl \
	--without-zstd \
	--without-libuv

ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
LIBCURL_OPENIPC_CONF_OPTS += --enable-threaded-resolver
else
LIBCURL_OPENIPC_CONF_OPTS += --disable-threaded-resolver
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_VERBOSE),y)
LIBCURL_OPENIPC_CONF_OPTS += --enable-verbose
else
LIBCURL_OPENIPC_CONF_OPTS += --disable-verbose
endif

LIBCURL_OPENIPC_CONFIG_SCRIPTS = curl-config

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_OPENSSL),y)
LIBCURL_OPENIPC_DEPENDENCIES += openssl
# configure adds the cross openssl dir to LD_LIBRARY_PATH which screws up
# native stuff during the rest of configure when target == host.
# Fix it by setting LD_LIBRARY_PATH to something sensible so those libs
# are found first.
LIBCURL_OPENIPC_CONF_ENV += LD_LIBRARY_PATH=$(if $(LD_LIBRARY_PATH),$(LD_LIBRARY_PATH):)/lib:/usr/lib
LIBCURL_OPENIPC_CONF_OPTS += --with-openssl=$(STAGING_DIR)/usr \
	--with-ca-path=/etc/ssl/certs
else
# --without-openssl, not --without-ssl. They were the same thing in 7.76; in
# 8.x --without-ssl means "no TLS backend at all" and configure hard-errors if
# it is passed alongside --with-mbedtls, which is exactly what every mbedTLS
# board does.
LIBCURL_OPENIPC_CONF_OPTS += --without-openssl
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_GNUTLS),y)
LIBCURL_OPENIPC_CONF_OPTS += --with-gnutls=$(STAGING_DIR)/usr \
	--with-ca-fallback
LIBCURL_OPENIPC_DEPENDENCIES += gnutls
else
LIBCURL_OPENIPC_CONF_OPTS += --without-gnutls
endif

# The two mbedTLS series are one choice in Config.in, so at most one of these
# arms runs. 2.25 stays the default because it is what a hundred boards already
# carry and moving them all is a flash-size decision, not a build one.
#
# 8.15.0 is the last curl that can take either. 8.16.0 opens vtls/mbedtls.c with
# #error "mbedTLS 3.2.0 or later required", so the next bump past this one stops
# being a version bump and becomes a fleet-wide migration off 2.25.
ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_MBEDTLS),y)
LIBCURL_OPENIPC_CONF_OPTS += --with-mbedtls=$(STAGING_DIR)/usr \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
LIBCURL_OPENIPC_DEPENDENCIES += mbedtls-openipc
else ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_MBEDTLS3),y)
LIBCURL_OPENIPC_CONF_OPTS += \
	--with-mbedtls=$(STAGING_DIR)$(MBEDTLS3_OPENIPC_PREFIX) \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
LIBCURL_OPENIPC_DEPENDENCIES += mbedtls3-openipc
# --with-mbedtls=<prefix> only appends -L<prefix>/lib. The sysroot's own
# -L$(STAGING_DIR)/usr/lib already precedes it, and that is where 2.25 lives, so
# -lmbedtls resolves to 2.25 while -isystem has already pointed the compiler at
# 3.6's headers. The build succeeds and the result is a header/ABI mismatch that
# only shows up on the camera. Naming the 3.x directory here puts it first.
# Checked by readelf, not by reading the link line: libcurl.so must NEED
# libmbedtls.so.21, not .so.13.
LIBCURL_OPENIPC_CONF_ENV += \
	LDFLAGS="-L$(STAGING_DIR)$(MBEDTLS3_OPENIPC_PREFIX)/lib"
else
LIBCURL_OPENIPC_CONF_OPTS += --without-mbedtls
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_WOLFSSL),y)
LIBCURL_OPENIPC_CONF_OPTS += --with-wolfssl=$(STAGING_DIR)/usr
LIBCURL_OPENIPC_DEPENDENCIES += wolfssl
else
LIBCURL_OPENIPC_CONF_OPTS += --without-wolfssl
endif

ifeq ($(BR2_PACKAGE_C_ARES),y)
LIBCURL_OPENIPC_DEPENDENCIES += c-ares
LIBCURL_OPENIPC_CONF_OPTS += --enable-ares
else
LIBCURL_OPENIPC_CONF_OPTS += --disable-ares
endif

ifeq ($(BR2_PACKAGE_LIBIDN2),y)
LIBCURL_OPENIPC_DEPENDENCIES += libidn2
LIBCURL_OPENIPC_CONF_OPTS += --with-libidn2
else
LIBCURL_OPENIPC_CONF_OPTS += --without-libidn2
endif

# Configure curl to support libssh2
ifeq ($(BR2_PACKAGE_LIBSSH2),y)
LIBCURL_OPENIPC_DEPENDENCIES += libssh2
LIBCURL_OPENIPC_CONF_OPTS += --with-libssh2
else
LIBCURL_OPENIPC_CONF_OPTS += --without-libssh2
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
LIBCURL_OPENIPC_DEPENDENCIES += brotli
LIBCURL_OPENIPC_CONF_OPTS += --with-brotli
else
LIBCURL_OPENIPC_CONF_OPTS += --without-brotli
endif

ifeq ($(BR2_PACKAGE_NGHTTP2),y)
LIBCURL_OPENIPC_DEPENDENCIES += nghttp2
LIBCURL_OPENIPC_CONF_OPTS += --with-nghttp2
else
LIBCURL_OPENIPC_CONF_OPTS += --without-nghttp2
endif

ifeq ($(BR2_PACKAGE_LIBGSASL),y)
LIBCURL_OPENIPC_DEPENDENCIES += libgsasl
LIBCURL_OPENIPC_CONF_OPTS += --with-gsasl
else
LIBCURL_OPENIPC_CONF_OPTS += --without-gsasl
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_COOKIES_SUPPORT),y)
LIBCURL_OPENIPC_CONF_OPTS += --enable-cookies
else
LIBCURL_OPENIPC_CONF_OPTS += --disable-cookies
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_PROXY_SUPPORT),y)
LIBCURL_OPENIPC_CONF_OPTS += --enable-proxy
else
LIBCURL_OPENIPC_CONF_OPTS += --disable-proxy
endif

ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_EXTRA_PROTOCOLS_FEATURES),y)
LIBCURL_OPENIPC_CONF_OPTS += \
	--enable-dict \
	--enable-gopher \
	--enable-imap \
	--enable-ldap \
	--enable-ldaps \
	--enable-pop3 \
	--enable-rtsp \
	--enable-smb \
	--enable-smtp \
	--enable-telnet \
	--enable-tftp
else
LIBCURL_OPENIPC_CONF_OPTS += \
	--disable-dict \
	--disable-gopher \
	--disable-imap \
	--disable-ldap \
	--disable-ldaps \
	--disable-pop3 \
	--disable-rtsp \
	--disable-smb \
	--disable-telnet \
	--disable-tftp
endif

#	--disable-smtp \


# The hook that appended "Requires: openssl" to libcurl.pc.in is gone rather
# than repaired. It was registered as LIBCURL_FIX_DOT_PC while the define was
# named LIBCURL_OPENIPC_FIX_DOT_PC, so it never ran -- and 8.15 is why it must
# not start. 7.76's libcurl.pc.in carried no Requires: field at all, only a
# comment saying one would be welcome; 8.15 templates Requires: and
# Requires.private: and fills them from the configured backends. Correcting the
# name would append a second Requires: key to a file that already has one.
#
# This one is repaired, because it still has a job: without it, a board that
# asks for the library and not the binary gets /usr/bin/curl anyway. No board in
# the tree is in that position today -- every defconfig that enables
# libcurl-openipc also sets _CURL -- so this is a trap for the next one rather
# than a bug in a shipped image.
ifeq ($(BR2_PACKAGE_LIBCURL_OPENIPC_CURL),)
define LIBCURL_OPENIPC_TARGET_CLEANUP
	rm -rf $(TARGET_DIR)/usr/bin/curl
endef
LIBCURL_OPENIPC_POST_INSTALL_TARGET_HOOKS += LIBCURL_OPENIPC_TARGET_CLEANUP
endif

HOST_LIBCURL_OPENIPC_DEPENDENCIES = host-openssl
HOST_LIBCURL_OPENIPC_CONF_OPTS = \
	--disable-manual \
	--disable-curldebug \
	--with-openssl \
	--without-gnutls \
	--without-mbedtls

$(eval $(autotools-package))
$(eval $(host-autotools-package))
