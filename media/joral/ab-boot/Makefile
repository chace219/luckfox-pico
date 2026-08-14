# ab-boot — A/B slot machinery for the initramfs-driven update design
# (media/joral/swupdate-implementation-plan.md, "Chosen design").
#
# Ships ONE binary, misc_ab, into the rootfs (used there by the SWUpdate
# post-install hook, the first-good-boot health check and the console) and
# into the initramfs (used there to pick the slot to boot). The initramfs
# itself is assembled by scripts/mkinitramfs.sh, which is invoked from the
# platform build — not from this Makefile — because it needs the busybox
# staging tree.
#
# `make test` builds misc_ab for the HOST and runs the contract test against
# a scratch file; the tool is pure pread/pwrite, so host behaviour is target
# behaviour.

CROSS_COMPILE ?= arm-rockchip830-linux-uclibcgnueabihf-
CC      = $(CROSS_COMPILE)gcc
STRIP   = $(CROSS_COMPILE)strip
HOSTCC  ?= cc
CFLAGS  = -Wall -Wextra -O2 -std=c99

BUILDDIR = build

# Static for the initramfs: the initramfs must not depend on shared
# libraries that live in the rootfs it has not mounted yet.
LDFLAGS_STATIC = -static

DESTDIR ?= ./out/root
SBINDIR = $(DESTDIR)/usr/sbin
INITDIR = $(DESTDIR)/etc/init.d
SWUDIR  = $(DESTDIR)/etc/swupdate

# Trust store for update-signature verification (/etc/swupdate/trusted-certs.pem).
# PRODUCTION: the key-ceremony output, committed at scripts/compliance/keys/
# (firmware-signing-and-support-policy.md A.2 — absent until the ceremony).
# Until then a per-checkout DEV keypair is auto-generated under keys-dev/
# (gitignored) so signed-update development and the bench spike can proceed.
# The gate stands: NO CUSTOMER SHIPMENT on a DEV-keyed trust store.
SDK_ROOT   := $(abspath $(CURDIR)/../../..)
PROD_CERTS := $(SDK_ROOT)/scripts/compliance/keys/trusted-certs.pem
DEV_KEYDIR := keys-dev

.PHONY: all clean install test

all: $(BUILDDIR)/misc_ab

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/misc_ab: src/misc_ab.c | $(BUILDDIR)
	$(CC) $(CFLAGS) $(LDFLAGS_STATIC) -o $@ $<
	$(STRIP) $@

# Host build, for the contract test and for signing-side tooling.
$(BUILDDIR)/misc_ab.host: src/misc_ab.c | $(BUILDDIR)
	$(HOSTCC) $(CFLAGS) -o $@ $<

# Dev signing material (interim until the key ceremony; see above).
$(DEV_KEYDIR)/trusted-certs.pem:
	@mkdir -p $(DEV_KEYDIR)
	@umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
		-out $(DEV_KEYDIR)/dev-signing.key.pem 2>/dev/null
	@openssl req -new -x509 -days 730 -sha256 \
		-key $(DEV_KEYDIR)/dev-signing.key.pem \
		-subj "/O=Joral LLC/OU=DEV SIGNING - NOT FOR SHIPMENT/CN=joral-fw-dev" \
		-out $(DEV_KEYDIR)/dev-signing.crt.pem
	@cp $(DEV_KEYDIR)/dev-signing.crt.pem $@
	@echo "  GEN      DEV signing keypair ($(DEV_KEYDIR)/) — NOT FOR SHIPMENT"

install: all $(if $(wildcard $(PROD_CERTS)),,$(DEV_KEYDIR)/trusted-certs.pem)
	install -d $(SBINDIR) $(INITDIR) $(SWUDIR)
	install -m 755 $(BUILDDIR)/misc_ab $(SBINDIR)/misc_ab
	install -m 755 scripts/init.d/S99ab-health $(INITDIR)/S99ab-health
	install -m 644 swupdate/swupdate.cfg $(DESTDIR)/etc/swupdate.cfg
ifneq ($(wildcard $(PROD_CERTS)),)
	install -m 644 $(PROD_CERTS) $(SWUDIR)/trusted-certs.pem
	@echo "  INSTALL  PRODUCTION trust store -> /etc/swupdate/trusted-certs.pem"
else
	install -m 644 $(DEV_KEYDIR)/trusted-certs.pem $(SWUDIR)/trusted-certs.pem
	@echo "  INSTALL  DEV trust store -> /etc/swupdate/trusted-certs.pem (NOT FOR SHIPMENT)"
endif

test: $(BUILDDIR)/misc_ab.host
	MISC_AB=$(BUILDDIR)/misc_ab.host sh tests/test_misc_ab.sh

clean:
	rm -rf $(BUILDDIR) out
