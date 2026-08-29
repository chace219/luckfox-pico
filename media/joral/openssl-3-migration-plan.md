# OpenSSL 1.1.1 → 3.5 LTS Migration — Plan & Record

*Started and completed 2026-08-12 — implemented, build-verified, and the
migrated TLS surfaces (default console HTTPS, OPC UA Sign&Encrypt) confirmed on
hardware the same day. Closes CRA plan item 4f (`cra-compliance-plan.md`), the
last substantive block on Annex I row #2: 13 of the 19 then-blocking CVE
findings were libopenssl 1.1.1v, EOL since 2023-09-11 (ADR-127).*

## Target version — and why not 3.0

**OpenSSL 3.5.7** (the 3.5 LTS line). 3.0 would have been the smallest step, but
3.0 reaches EOL on **2026-09-07 — four days before our CRA reporting obligations
begin**. Migrating onto a component that goes EOL the same month would recreate
the exact finding we are closing. 3.5 is the current LTS, supported until
**2030-04-08**. 3.5.7 is the latest point release (the buildroot 2025.08.x branch
pins 3.5.4; we take its recipe and bump the version + hash so the CVE gate starts
clean).

Within the 3.x series the API/ABI is stable (`libssl.so.3`), so everything that
builds against 3.0 builds against 3.5 — the compatibility question is 1.1.1 → 3.x,
which upstream Buildroot already solved for this exact package set (see below).

## Scoping results (2026-08-12, against the built image + both product trees)

Everything that links OpenSSL in the packed rootfs is **rebuildable from source**
— this is what makes the migration a package bump rather than a platform project:

- **Platform packages:** openssh (sshd + client tools), stunnel 5.65, libcurl +
  curl, wget, socat, ntpd, pppd, libevent_openssl, python3.11 (`_ssl`,
  `_hashlib`), open62541 1.3.4.
- **Our daemons:** `media-gateway`, `intelligence_edge_opcua` — rebuilt every
  `./build.sh media`; satisense `core/certgen.c` is already written against the
  3.x-safe EVP keygen API (header comment says so, and media-gateway's
  `src/tls/certgen.c` is the same lineage).
- **No Rockchip vendor blob links libssl/libcrypto.** Scanned every ELF in the
  rootfs staging tree.
- **The `wifi_app` prebuilts** (hostapd, dnsmasq, wpa_supplicant ×3, …) use
  internal/static crypto — no shared OpenSSL linkage, so they are unaffected
  (their declare-or-drop item 5e stays independent).
- **No `openssl` CLI in the image and no script invokes one** — console password
  hashing and cert generation are done by our own binaries.

Buildroot 2023.02.6 ships 1.1.1v **stock** (verified against the pristine
tarball) — upstream moved to 3.x in 2023.05, so this is not a Luckfox pin and
carries no vendor constraint.

## Decisions

1. **Recipe source: buildroot 2025.08.x `package/libopenssl/`** (mk, Config.in,
   hash, 4 patches), version bumped 3.5.4 → 3.5.7 with the upstream-published
   sha256. A release-branch recipe is tested against this package generation;
   the recipe uses only generic-package infra that 2023.02 has (verified:
   `BR2_TOOLCHAIN_HAS_UCONTEXT` exists in 2023.02's toolchain Config.in).
2. **The 1.1.1 patches must go.** The seven `000x-*.patch` files in the old
   package dir do not apply to 3.x — the install step replaces the whole
   directory, not just the recipe.
3. **No defconfig changes needed.** The 3.x recipe gates algorithms behind
   `BR2_PACKAGE_LIBOPENSSL_ENABLE_*` symbols that **default to y** — dependent
   packages keep DES (pppd MSCHAP), MD4, ChaCha20, BLAKE2 (python hashlib)
   without the `select` lines upstream added to *their* Config.in files (which
   our 2023.02 dependents don't have). Attack-surface minimization by disabling
   unused algorithm families is recorded as a follow-up, not done blind here.
4. **open62541 v1.3.4 → v1.3.15** in the same pass. 1.3.4 (mid-2022) predates
   OpenSSL 3 support in the 1.3 series; upstream buildroot pairs OpenSSL 3.x
   with 1.3.15, and the entire recipe diff is the version string — same API
   line, same MPL-2.0, plus that series' own security fixes. This adds the OPC
   UA server library to the set needing bench re-validation, which is pending
   anyway.
5. **Git-archive hash formats differ between buildroot versions:** upstream's
   hash names `open62541-v1.3.15-git4.tar.gz`; our 2023.02 git backend produces
   `-br1` archives with a different content hash. The pinned `-br1` hash was
   computed by a controlled `make open62541-source` download (submodule SHAs
   confirmed against the release), not taken on faith.

## Mechanism (how the change is tracked)

The extracted buildroot tree is throwaway (`sysdrv/.gitignore`). The tracked
masters live beside the defconfigs, following the existing `busybox.config`
precedent:

- `sysdrv/tools/board/buildroot/libopenssl/` — full 3.5.7 package dir
- `sysdrv/tools/board/buildroot/open62541/` — 1.3.15 package dir
- `sysdrv/Makefile` — both `buildroot_create` and the `buildroot` extract block
  now `rm -rf` the stock `package/libopenssl/*` and copy these in (the rm is
  load-bearing: it removes the 1.1.1 patches).

Both were also mirrored into the live extracted tree by hand — the copy step
only runs when the tree is re-extracted (same gotcha as `busybox.config`).

## Build & verification

- **Full rebuild from empty `output/`** inside the buildroot tree (`dl/` cache
  preserved — it is a sibling, and both new tarballs were hash-verified before
  the wipe). Buildroot never uninstalls: with a soname change
  (`libssl.so.1.1` → `libssl.so.3`) an incremental build would leave both
  libraries in `target/` and every un-rebuilt consumer silently linked against
  the CVE-carrying one. A side benefit: the stale `nginx` binary from the
  withdrawn ADR-151 experiment (deselected 2026-08-11, still present in the old
  staging tree) drops out.

**To build** (from the SDK root; the buildroot `output/` wipe was already done
2026-08-12, and the 3.5.7 + 1.3.15 tarballs are already in `dl/`, hash-verified):

```sh
./build.sh rootfs      # full clean buildroot rebuild — the long step
./build.sh media       # both products against the new staging libs
./build.sh firmware    # overlays + packed image
```

### Build fallout found on the first run (2026-08-12) — both fixed

1. **pppd 2.4.9 failed to compile: its EAP-TLS uses the OpenSSL ENGINE API**,
   which the 3.x recipe correctly omits (`no-engine`; the API is deprecated).
   Fixed by passing `USE_EAPTLS=` in the openssl branch of `pppd.mk` — no
   product uses PPP EAP-TLS, and MSCHAP keeps its DES via pppd's
   `NEEDDES`/`-lcrypto` path (verified: the rebuilt pppd links
   `libcrypto.so.3`, no libssl). Tracked as an overlay master at
   `sysdrv/tools/board/buildroot/pppd/pppd.mk` with its own Makefile copy line.
2. **The live tree was still building nginx.** The ADR-151 revert (2026-08-11)
   removed the nginx block from the *tracked* defconfig, but defconfigs are
   only copied into the buildroot tree at extract time — the live tree's copy
   predated the revert, so the clean rebuild re-selected nginx and installed
   20 files including an `S50nginx` init script. Same failure mode as the
   `busybox.config` gotcha, now proven to bite for defconfigs too. Fixed:
   masters re-synced into `configs/`, `.config` regenerated (nginx deselected),
   the 20 installed files purged from `target/` via the package's
   `.files-list.txt`, and its build dir removed. The earlier claim in this
   document that the stale nginx binary "drops out" with the clean rebuild was
   wrong in mechanism — it would have been *reinstalled*; the defconfig sync is
   what actually removes it.

If `rootfs` fails in a package beyond these, `ntp` is the remaining suspect
(the only consumer whose exact 2023.02 version upstream never release-tested
against OpenSSL 3.x); the fix pattern is the same — backport or overlay from
buildroot 2025.08.x. Then:

```sh
scripts/compliance/verify-openssl3-migration.sh output/out/rootfs_uclibc_rv1106
./build.sh sbom
./build.sh cve
```

Checklist for closing — **verified 2026-08-12 against the rebuilt image**
(build `v1.0.0-66-g2d4b29958-dirty`, `update.img` 2026-08-12 04:28):

- [x] Zero `NEEDED libssl.so.1.1`/`libcrypto.so.1.1` across every ELF in the
      packed rootfs; both product daemons link `.so.3`; old library files gone;
      open62541 at 1.3.15; nginx leftovers absent. All five checks in
      `scripts/compliance/verify-openssl3-migration.sh` pass.
- [x] `make test` green in both product trees.
- [x] `./build.sh sbom` — reports **libopenssl 3.5.7, supported branch**; the
      EOL flag cleared itself as designed. 51 platform + 8 app components.
- [x] `./build.sh cve` — **19 → 6 blocking**. All 13 libopenssl 1.1.1 findings
      resolved; open62541 1.3.15, openssh, stunnel and pppd all report zero.
      One *new* match against 3.5.7 — CVE-2019-0190 — is a false positive:
      the defect is in Apache httpd's mod_ssl (not shipped); NVD's CPE
      configuration lists openssl only as httpd's platform. Recorded as
      `not-affected` in `cve-triage.csv` (REVIEW_BY 2027-02-12). The 6 that
      remain (busybox, libzlib, wget ×2, libcurl, dhcpcd) are the pre-existing
      plan-item-5b set, untouched by this migration.
- [x] **Hardware bench — the migrated TLS surfaces confirmed on device
      2026-08-12**: the flashed image serves the console over HTTPS by default
      and the OPC UA server certificate / Sign&Encrypt session works under
      open62541 1.3.15 / OpenSSL 3.5.7. Still open (item 8 scope, not
      migration-specific): MQTT TLS leg c — which has never run on any stack —
      and the remaining queued bench checks (secrets-CGI path, factory reset,
      audit-log viewer, loopback-bind `netstat`, audit-attribution records).

## Residuals / follow-ups

- Legacy algorithm families (DES, MD4, RC2/RC4, …) are still compiled in via the
  default-y options. Trimming them needs a per-consumer reachability check
  (pppd is the only known DES/MD4 user — and whether pppd belongs in the image
  at all is its own question).
- The "secrets at rest are restricted, not encrypted" acceptance
  (2026-08-06) named the OpenSSL 3 migration as its revisit trigger — that
  trigger has now fired; a key-derivation-based sidecar encryption is now
  implementable on-platform if the product wants it.
- stunnel/openssh/curl/etc. stay at their 2023.02 versions — this migration
  changes the crypto provider underneath them, nothing else. Their own currency
  is covered by the CVE gate per release.

## 2026-08-29 — patch bump to 3.5.8, and QUIC turned off

The CVE gate had been red since 2026-08-25 with nobody watching it (last run
2026-08-22): three blocking findings, all `libopenssl 3.5.7`, CVSS 7.5 each —
CVE-2026-14456 (QUIC server unbounded incoming-channel queue), CVE-2026-14457
(RFC 7250 raw-public-key NULL dereference on a key-only config), CVE-2026-18798
(QUIC server double free on a malformed INITIAL packet). None reachable on this
image — no source in either product tree opens a QUIC listener or configures
raw public keys, and every TLS endpoint here (stunnel, open62541, the MQTT
client) is certificate-configured — but OpenSSL 3.5.8 (released 2026-08-25)
fixes all three plus seven more NVD had not yet attached to 3.5.7, so the bump
beats triaging ten rows one at a time as they land.

Mechanism, following the whole-package-replacement precedent exactly:
`LIBOPENSSL_VERSION` 3.5.7 → 3.5.8 in the tracked
`sysdrv/tools/board/buildroot/libopenssl/libopenssl.mk`, `.hash` sha256
`a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2` (matches
upstream's published `.sha256`; `LICENSE.txt`'s hash is unchanged — byte-
identical between the two releases). Same soname (`libssl.so.3` /
`libcrypto.so.3`), so — unlike the 1.1.1 → 3.x migration — this did **not**
need a wipe of `output/`: `make libopenssl-dirclean` plus the ordinary
`./build.sh rootfs && ./build.sh media && ./build.sh firmware` chain was
sufficient, and the four stock portability patches applied clean.

**Also disabled QUIC** (`# BR2_PACKAGE_LIBOPENSSL_ENABLE_QUIC is not set` in
`luckfox_pico_w_defconfig` — `Config.in` defaults it to `y`, so absence of
the finding was never going to argue not-built on its own). Confirmed on the
built library, not assumed from the Configure flag: `readelf --dyn-syms` on
the packed `libssl.so.3` exports no `SSL_new_listener*`/`OSSL_QUIC*` symbol,
and `configuration.h` in the build tree defines `OPENSSL_NO_QUIC`. (`strings`
still shows the literal `SSL_new_listener` twice — dead text in an unused
error-string table, not a callable symbol; checked so the record does not
repeat the "read from strings, not from the linker" mistake this document
already warns about elsewhere.) The effect: every future QUIC/RPK finding in
this library is *not built*, a compile-time fact, rather than a reachability
argument to re-litigate per finding.

**Verified 2026-08-29** — full chain, no `output/` wipe: `libssl.so.3`
reports `OpenSSL 3.5.8 25 Aug 2026`; `verify-openssl3-migration.sh` 5/5;
`./build.sh sbom` → `libopenssl 3.5.8`; `./build.sh cve` → **0 blocking**
(back from 3); `make test` clean in both product trees; all seven release
gates (`oem`, `partitions`, `hardening`, `doccmds`, `cited`, `cve`, `sbom`)
pass. **Not yet done:** the TLS bench legs (console HTTPS, OPC UA
Sign&Encrypt, MQTT TLS) that sit under this library — none is 3.5.8-specific,
but the patch-release precedent set by the original migration is to re-touch
them on a flashed unit before calling a libssl change closed, not only the
build-time checks.
