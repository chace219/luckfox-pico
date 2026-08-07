# CRA Compliance Plan — Media Gateway & SatiSense Edge

*Prepared 2026-07-26 from `CRA_Gateway_Requirements_1.docx` (internal Joral engineering
reference for Regulation (EU) 2024/2847, Annex I & II) plus a code-level audit of both
product trees. Status column reflects the codebase as of commit `8cff5d0e9`.*

## Key dates

- **11 September 2026** — vulnerability/incident reporting obligations begin (applies to already-shipped units).
- **11 December 2027** — full CRA compliance (CE marking, technical file, labeling) for products newly placed on the EU market.

## Kernel of the requirements doc

1. **Annex I Part I — eight built-in security properties**: secure-by-default config, no known CVEs at shipment, protected credentials/config data, minimized attack surface, access control on write paths, security-event logging, a reliable (ideally signed) update mechanism, factory reset to a known-secure state.
2. **Annex I Part II — vulnerability-handling process**: SBOM per release, ability to assess/fix reported vulnerabilities quickly, plain-language security fix notes, coordinated disclosure channel, periodic security testing (e.g. fuzzing protocol parsers).
3. **Annex II — accurate facts for the compliance file** (Carl/product management owns the file; engineering owns accuracy): exact version/build-ID scheme, true default open ports/services list, real update procedure, honest deployment assumptions ("isolated machine control network").

## Gap inventory (audited 2026-07-26)

| # | Annex I requirement | Media Gateway | SatiSense Edge |
|---|---|---|---|
| 1 | Secure by default | ⚠️ default `admin`/`joral` (`src/web/cgi-lib/webauth.sh`), HTTP-only console (`tls_on()` returns 1) | ⚠️ same default creds; OPC UA `security: none` default (`gateway.json`), web TLS off by default, stunnel init fails open (`scripts/init.d/S60intelligence-edge`) |
| 2 | No known CVEs at shipment | ⚠️ no CVE-check process; shared rootfs ships OpenSSL 1.1.1 (EOL, ADR-127) | same |
| 3 | Data confidentiality/integrity | ✅ console pw salted-SHA-256; config plaintext but secret-free | ❌ MQTT pw + OPC UA pw + LLM API key plaintext in `gateway.json` (`core/config.c:1302,1333,1422`), served to browser by `web/cgi/api-config.sh:24` over plain HTTP |
| 4 | Minimize attack surface | ❌ shared Luckfox rootfs boots telnetd, sshd, adbd, Samba; root pw `luckfox` (`luckfox_pico_defconfig:16`) | same (shared rootfs) |
| 5 | Access control | ✅ all CGIs gated by `require_auth`; CAN ports :8000/:8001 unauthenticated by protocol design | ✅ web gated; OPC UA anonymous by default (ADR-107 trusted-LAN); Sign/Encrypt implemented but opt-in (`core/opcua_security.c`) |
| 6 | Security-event logging | ❌ zero logging of logins/failures/config changes (no `logger` calls in any CGI) | same |
| 7 | Update mechanism | ❌ no in-product updater; host reflash only (SocToolKit/`upgrade_tool`), unsigned images | same, and undocumented in manuals |
| 8 | Factory reset | ⚠️ manual file-deletion procedure documented only | ❌ none (Utilities page = export/import + restart) |

Cross-cutting: media-gateway `docs/manual/user-manual.md:425` and `docs/project-context.md:77`
still claim "no authentication (v1)" — contradicts shipped code; fix for Annex II accuracy.
httpd + CGIs run as root (accepted in `project-context.md:78`). No firewall ruleset shipped.
No LICENSE file in media-gateway. SatiSense config import has no schema validation
(`web/cgi/api-config.sh:15-19`).

## Closed since the audit

*Appended as items land. The table above stays a snapshot of the 2026-07-26 audit.*

- **2026-07-31 — SatiSense Edge, Annex I #4 (minimise attack surface):** the OPC UA
  server advertised the OPC Foundation-deprecated `Basic128Rsa15` (SHA-1 + PKCS#1 v1.5)
  and `Basic256` (SHA-1) security policies, because open62541's
  `setDefaultWithSecurityPolicies` registers every policy it implements.
  `core/opcua_security.c` now removes both from `config->securityPolicies` *and* from
  the endpoint list — deleting the policies matters, since open62541 resolves an
  OpenSecureChannel request by policy URI from that array rather than from the
  advertised endpoints, so hiding the endpoints alone would have left them
  negotiable. Only `Basic256Sha256` and `Aes128Sha256RsaOaep` are served (plus
  `None`, discovery-only). Evidence: `core/opcua_security.c` `drop_deprecated_policies()`.
  **Needs a reflash to take effect on already-flashed units.**
- **2026-07-31 — SatiSense Edge, Annex I #3 (confidentiality) enabler:** on-device
  certificate generation produced certificates that no conforming OPC UA client would
  accept — `core/certgen.c` omitted the `nonRepudiation` and `dataEncipherment`
  KeyUsage bits required by OPC UA Part 6 §6.2.2, and marked the extension critical,
  so UaExpert refused CreateSession with `BadCertificateUseNotAllowed`. In practice
  this meant the *only* transport-security control on the primary northbound could not
  be switched on by an operator using the documented procedure. Fixed and locked in by
  `tests/test_certgen.c`. Relevant to Annex I #1 too: the secure mode has to be usable
  before "secure by default" is a meaningful target.

Both fixes were **validated on hardware 2026-07-31** — an OPC UA Sign & Encrypt session
from UaExpert now establishes against the RV1106, where before the fix the client
refused the server certificate outright. Both defects were found by *executing* TC-S3
on hardware rather than by review: neither is visible in a code read, and the product
had carried them through every prior release. That is evidence for treating the
"periodic security testing" line of Annex I Part II as a scheduled activity with a
hardware bench in the loop, not a release-time checkbox.

- **2026-07-31 — SatiSense Edge, Annex I #1 (secure by default) + availability:** enabling
  web-console TLS required an operator to place a certificate by hand, and a missing one
  silently downgraded the console to plain HTTP. `S60intelligence-edge` now generates
  **this unit's own** certificate when `web.tls` is set, so TLS can be turned on from
  configuration alone. A proposal to embed certificate PEMs in the firmware image was
  **rejected**: an image-embedded private key is byte-identical on every unit shipped
  (CWE-321), so recovering it from one device would compromise the console TLS of the
  entire fleet — strictly worse than the `admin`/`joral` default already in the table
  above. Per-device generation gives the same zero-touch result with a unique key per
  unit. `.gitignore` blocks `*.pem`/`*.key`/`*.der`/`*.p12`/`*.pfx` to catch a stray
  local keygen.
- **2026-07-31 — SatiSense Edge, availability defect found by procedure review:** the
  same init script moved httpd to loopback *before* starting stunnel and never verified
  stunnel came up, so a malformed certificate left the console unreachable from the
  network **while printing `(https:8080)` as if it had succeeded**. An operator following
  the documented HTTPS procedure could lose console access and be told it worked. The
  script now polls the public port and rolls back to plaintext if stunnel is not
  listening. Verified against a stubbed-device harness across all five branches; the
  same harness reproduces the lockout on the pre-fix script.

**Status 2026-07-31 (end of day):** all of the above is now **in a flashed firmware image
and confirmed on hardware**. The console runs over HTTPS with a per-device certificate,
plain HTTP is refused on the same port, and the OPC UA server runs Sign & Encrypt with
username auth and an enforcing client trust list. Gap-table row #1 (secure by default)
and row #3 (data confidentiality) improve materially for SatiSense Edge — though row #1
is not closed: `opcua.security` and `web.tls` are still **opt-in**, and the default
`admin`/`joral` console credential is untouched. Remaining from this thread: MQTT TLS
(TC-S3 leg c) has still never run, and the media-gateway console remains HTTP-only.

- **2026-08-04 — SatiSense Edge, Annex I #3/#5 hardening (OPC UA PKI):** the OPC UA
  client trust list only accepted pinned (self-signed) client certificates;
  `core/opcua_security.c` now also validates CA-signed client certificates against a
  CA in the trust folder (`8572479`). `core/certgen.c` binds the server certificate
  to the device hostname instead of its IP address, so a DHCP lease change no longer
  invalidates the certificate (`084c291`).
- **2026-08-04 — SatiSense Edge, factory-reset enabler:** the image now ships a
  factory-default `gateway.json` (`25b3d6c`) — the staging basis the 2026-08-06
  factory-reset implementation below restores from.
- **2026-08-05 — SatiSense Edge, TC-S3 leg c unblocked:** MQTT TLS PEMs can be
  uploaded from the web console to fixed device paths (`9179e17`), and a CA
  directory is now loaded as CApath rather than CAfile (`6da394d`). The MQTT TLS
  bench leg — never yet executed on hardware — no longer requires shell access to
  stage certificates.

- **2026-08-06 — SatiSense Edge, Annex I #3 (data confidentiality): stored secrets
  no longer in gateway.json, and never served to the browser.** The three secrets
  (`mqtt.password`, `opcua.password`, `llm.api_key`) now live in a root-only 0600
  sidecar (`/etc/intelligence-edge/gateway.json.secrets`), written atomically and
  created 0600 from the first byte. `gateway.json` — the file the console
  round-trips, the Utilities page exports and imports — is secret-free by
  construction. The console API was redesigned around that: `api-config.sh` GET
  serves a **redacted** view (a stored secret appears only as the
  `__SECRET_UNCHANGED__` sentinel — not even its length is disclosed), and POST
  resolves sentinels back against the device's stored values via the daemon's
  `--config-ingest`, which also gives config saves a real JSON parse check
  (closing the "no schema validation on import" cross-cutting note at the parse
  level). Web TLS stays **opt-in** per the current posture, which is exactly why
  the design never relies on the transport: no stored secret crosses the wire in
  either direction, HTTP or HTTPS. Units flashed before the change migrate
  automatically — the daemon detects legacy in-file plaintext at boot and rewrites
  the pair once — and the legacy file is redacted correctly even before migration.
  Secret fields in the console (MQTT password, OPC UA password, LLM API key) use a
  shared `SecretField` that renders "stored — type to replace", keeps on empty,
  and clears only via an explicit button. Contract pinned by 24 new checks in
  `tests/test_config_json.c` (`make test-config`), including sidecar mode 0600,
  no-secret-key-in-config, sentinel keep/replace/clear resolution, and
  legacy-plaintext redaction. **Needs a reflash (or daemon update) to take
  effect; validation of the CGI path on hardware is pending the next bench
  session.** Remaining for row #3: secrets are restricted, not encrypted at rest
  (no key store on this platform — accepted for now, revisit with the OpenSSL 3
  migration).
- **2026-08-06 — SatiSense Edge, Annex I #8 (factory reset): implemented.**
  `satisense-factory-reset` (installed to `/usr/sbin`) wipes every category of
  operator data — configuration, the secrets sidecar, the console login, all TLS
  keys/certificates, the OPC UA trust/issuer/CRL dirs, learned AI state,
  operator-added KB manuals, sessions and logs — then restores pristine factory
  defaults (`gateway.json` + the manual KB seed) from a new read-only staging area
  `/usr/share/intelligence-edge/factory` and reboots. Reachable two ways: the
  console's Utilities page (typed `RESET` confirmation + explicit dialog, POST-only
  CGI that re-checks a server-side confirm phrase) and by hand over serial/SSH for
  a locked-out operator. The wipe logic that ships is the wipe logic that is
  tested: the script takes a path-prefix override and
  `tests/test_factory_reset.sh` (now part of `make test`) pins the factory-state
  contract, including the degraded no-factory-dir case. Media Gateway (row #8
  ⚠️) still has only the documented manual procedure.

- **2026-08-06 — both products, Annex I Part II §1 (SBOM): generated from the build.**
  `./build.sh sbom` (→ `scripts/compliance/gen-sbom.sh`) merges two sources, because
  neither covers the image alone: Buildroot's own `make legal-info` for the platform
  layer (**134 components** with version, license, license files and upstream source
  site, straight from the `.config` that built the image) and a hand-declared
  application layer per product (`docs/compliance/app-manifest.csv`, **8 components**)
  for everything Buildroot cannot see — our own daemons and console, the statically
  linked EIPScanner submodule, and the Rockchip NPU vendor blob. Output is stamped
  with the SDK `git describe` build ID, so an inventory can be matched to a deployed
  unit, and it deliberately excludes legal-info's ~400 MB `sources/` tree (that is a
  source-redistribution artifact, not an SBOM). The document also rolls up licenses
  and flags end-of-life components automatically — it already reports **OpenSSL
  1.1.1v, EOL since 2023-09-11**, by matching the real built version rather than
  asserting it, so the line disappears on its own once we migrate. Verified
  end-to-end on this tree. Cheapest item in the plan, now closed; the remaining work
  on Annex I #2 is feeding this inventory into a CVE check as a release gate.
- **2026-08-06 — both products, plan items 1 and 3: compliance matrix + Annex II
  fact sheet, per product.** `docs/compliance/cra-annex1-matrix.md` and
  `docs/compliance/cra-annex2-facts.md` in each tree: one row per Annex I
  requirement → status → evidence path, plus the Annex II facts (identification,
  build ID scheme, true default open ports, security defaults, update procedure,
  support/reporting status, deployment assumptions, components). Written to be
  *honest rather than flattering* — a row reads "met" only where a path in the tree
  demonstrates it, and the gaps carry the same evidence discipline as the wins.
  Three factual corrections came out of writing them:
  - **media-gateway :8000 is not bound** — only `comm_port + 1` (8001) is. The audit
    table above and `docs/manual/quick-start.md:83` both overstated the exposure.
  - **the documented media-gateway factory reset leaves the password in place** —
    it deletes `gateway.conf`/`t1s.conf` but not `webauth.conf`, which is a separate
    procedure in a different paragraph. A reset that retains the previous operator's
    credentials does not satisfy Annex I #8, so row #8 for media-gateway is worse
    than "⚠️ manual procedure documented" implied.
  - **media-gateway has no version identifier at all** (no `VERSION`, no macro, no
    `--version`, stripped binaries), so after 11 Sep 2026 we could not state which
    builds an advisory covers. Annex II requires an identifying element; the SDK
    build ID only counts if it is readable on the device. Recommended fix: stamp it
    into both binaries and surface it in the console.
  Also recorded: media-gateway has **no LICENSE file and no SPDX headers**, so the
  SBOM lists our own components as UNDECLARED — needs an outbound-license decision.
  Its test coverage is two pure-function host tests with no `make test` target and
  **no coverage of the auth layer, CGIs, config writer or listeners**, which is the
  weakest Annex I Part II §3 position of the two products.

- **2026-08-07 — Media Gateway, Annex I #8 (factory reset): implemented, and a
  security-relevant documentation defect closed with it.** This was the worst row in
  either product's matrix: there was no reset function at all, and the *documented*
  manual procedure (`rm gateway.conf t1s.conf`) left `webauth.conf` in place — so the
  previous operator's console password **survived a "factory reset"**, which is not a
  return to a known-secure state. `media-gateway-factory-reset` now wipes config, the
  credential, sessions **and our managed block in `/etc/dhcpcd.conf`** (a stale DHCP
  policy must not outlive the config it was derived from, while lines the operator owns
  are preserved), restores pristine copies staged read-only at
  `/usr/share/media-gateway/factory`, and reboots. Reachable from the console
  (**Configuration → Factory reset**, typed `RESET` + confirm, POST-only CGI that
  re-checks the confirm phrase server-side) and over serial/SSH for a locked-out
  operator — that second path is why the credential wipe belongs in the reset rather
  than in a separate procedure. Ported from the SatiSense implementation as predicted,
  including the path-prefix design that lets the *shipped* script be the *tested*
  script: `tests/test_factory_reset.sh`, 19 checks, now running under a **new `make
  test` target** (this tree previously had none — its two unit tests had to be compiled
  by hand from command lines in their own headers, so they were easy to skip). The
  credential-wipe check was verified to fail against a script reverted to the old
  behaviour, so it guards the defect rather than merely passing.
- **2026-08-07 — Media Gateway, Annex II documentation accuracy: the false
  "no authentication" claim is gone.** `docs/manual/user-manual.md`'s specification
  table claimed "No authentication (v1)" — untrue since the auth layer landed, and it
  was baked into the on-device Help HTML *and* the customer PDF. The row now states the
  sign-in requirement, salted-hash credential and 8-hour session while keeping the
  honest limits (plain HTTP, unauthenticated CAN port, trusted-network deployment).
  Also corrected: `docs/project-context.md`'s security section (now documents the
  credential store, hash scheme, session model, HTTP limitation and the reset), and the
  quick-start default-ports table that read as though :8000 were open. Markdown,
  on-device HTML and all four PDFs regenerated together via
  `node scripts/render-manual.mjs --pdf`; verified zero occurrences of
  "No authentication" remain in any generated artifact.
  **Row #8 in the gap table is now met for both products, and row #5's documentation
  half is closed.** Still open for this product: HTTP-only console (no TLS option
  exists at all), no version identifier, no LICENSE file, no security-event logging,
  and no test coverage of the auth layer, config writer or listeners.

- **2026-08-07 — both products, Annex I #6 (security-event logging): implemented.**
  The last "zero logging" row. `audit_log <event> <result> <user> [k=v…]` lives in each
  product's shared console auth library, so every CGI gets it by sourcing what it
  already sourced, and the two implementations are **deliberately identical** (same
  function names, same record format) so one log parser and one operator procedure
  covers both. Recorded: login success/failure with the *attempted* username, logout,
  password change success/failure, config save, service restart, certificate
  generate/upload (SatiSense), factory reset including a refused one, and access to a
  guarded endpoint with an invalid session. Each record carries event, result, user,
  client address and event-specific fields.
  Three findings shaped the design, none of them visible from the plan line
  ("add `logger` calls"):
  - **`logger` alone would not have satisfied the requirement.** `/var/log` is a
    symlink to `/tmp`, which is **tmpfs** — the system log is RAM-only, so every
    record dies on reboot and anyone can erase the trail by power-cycling the unit.
    Records therefore go to syslog *and* to a durable 0600 file on the `/userdata`
    ext4 partition, which also survives a factory reset of `/etc` (the reset
    deliberately does not touch `/userdata`, and logs itself before running).
    1 MB per generation with 3 rotated generations kept (~45k records, ≤4 MB) —
    unbounded logging on embedded flash is its own availability bug, but see the
    cap-sizing note below for why the first attempt at this was too small.
  - **Log injection was a real hole.** Audit values are attacker-controlled (the
    username on a failed login). A first cut flattened newlines but still let a
    crafted username emit the literal text `result=success` inside the user field,
    which a parser or a human scanning the log would read as a real outcome. The
    principal field now also folds whitespace and `=`; the test that caught this is
    in the suite.
  - **Logging must never break the caller.** A password change or a factory reset
    must not fail because `/userdata` is full or absent, so persistence is
    best-effort and `audit_log` always returns success.
  No secret is ever passed to the logger: a config save records a 12-char fingerprint
  of the *persisted, secret-free* file instead of any content. Pinned by
  `tests/test_audit_log.sh` in both trees (22 and 23 checks, in `make test`) —
  including the no-secret contract asserted both against the helper and by grepping
  the call sites for credential variables. Documented for operators in both user
  manuals (markdown + on-device Help + PDFs regenerated).
  **Row #6 moves from ❌ (both) to met for SatiSense and partial for media-gateway** —
  the one remaining unlogged security event there is the CAN-gateway peer address,
  which `accept()` currently discards; it matters because reaching :8001 is equivalent
  to bus access. Also still open for both: nothing forwards the log off-device by
  default and there is no in-console viewer.
  While documenting this, found and fixed a **stale SatiSense manual procedure** that
  still said "there is no reset button; delete gateway.json" — untrue since 2026-08-06,
  and dangerous advice because hand-deleting config leaves credentials and certificates
  in place.

- **2026-08-07 — both products, Annex II §2 (product identification): build ID in the
  binaries.** media-gateway carried **no version identifier of any kind** (no `VERSION`,
  no macro, no `--version`, stripped binaries) and SatiSense had none readable off a
  running unit. That is a **reporting blocker**, not cosmetics: after 11 Sep 2026 an
  advisory has to name the affected builds, and we could not have. Both trees now
  compile `git describe --always --dirty --tags` into their binaries
  (`MG_VERSION` / `IE_VERSION`), exposed three ways: `--version` (and `-V`), a startup
  log line so a support bundle names the build, and the console — media-gateway's status
  header via `status.sh`, SatiSense's topbar via `diagnostics.json`. In both cases the
  console reads the value **from the running binary** rather than a hard-coded string,
  so it can never report a version the binary is not. Derived from git rather than
  hand-maintained because a hand-edited version is wrong the moment someone forgets to
  bump it; `-dirty` is kept deliberately, and `make MG_VERSION=1.2.3` overrides for a
  tagged release. Documented in both user manuals with an explicit "quote this when
  checking whether an advisory applies".
- **2026-08-07 — Media Gateway, Annex I #6 completed: CAN-path peer identity.**
  `accept()` on the CAN-over-Ethernet port discarded the peer sockaddr, so the one
  security-relevant event still unlogged after the console audit trail landed was *who
  injected frames onto the bus*. It now logs `can_client_connect` /
  `can_client_refused` / `can_client_disconnect` with `peer=ip:port`, storing the
  address per client slot so the disconnect record can still name who left after the fd
  is closed. Refusals are logged at warning priority — "client slots full" is also what
  a trivial connection-exhaustion attempt against the CAN path looks like. This matters
  more here than anywhere else on either product: reaching :8001 is equivalent to CAN
  bus access and the port is unauthenticated by protocol design, so under the
  trusted-network assumption this log is the **only** accountability that write path
  has. **Row #6 is now met for both products.**

- **2026-08-07 — both products, Annex I #6 hardened and made usable: console viewer,
  bigger history, no silent loss.** Three things came out of working out what the
  storage layout actually *is* rather than reading the code:
  - **`logger` alone was never going to be enough, confirmed.** `/var/log` is a symlink
    to `/tmp` (tmpfs), so the system log is RAM-only. The durable copy lives on
    `/userdata` = **eMMC `/dev/mmcblk0p6`, 256 MB ext4**, mounted by
    `/etc/init.d/S20linkmount` (generated at pack time from `RK_PARTITION_FS_TYPE_CFG`)
    at S20 — before the product services at S39/S50/S60, so it is always available by
    the time anything logs.
  - **The 256 KB cap was a forensics weakness, not a storage choice.** Rotation
    *evicts* history, so a single 256 KB generation (~2900 records) let an attacker
    push their own earlier activity out of the log by generating failed logins — a
    size limit doubling as an evidence-destruction primitive. Now 1 MB × 4 generations
    (~45k records, **1.6% of a 256 MB partition** — the old cap used 0.1%), aged out so
    only the oldest is discarded. With the existing 1-second penalty per failed login,
    flooding is no longer practical.
  - **A failed write was silent.** Persistence must stay best-effort (a password change
    must not fail because the log cannot be written), but swallowing the error lets the
    trail develop gaps nobody knows about. A failed append now emits
    `audit_persist_failed` to syslog. This is not hypothetical: `/userdata` is shared
    (`S50usbdevice` keeps `ums_shared.img` there), and **if the partition fails to
    mount at boot the vendor's `S20linkmount` runs `mke2fs -F` and reformats it** —
    which is the strongest argument yet for off-device collection rather than treating
    the on-device log as the only copy.
  **Console viewer** (the other half of the row): the log was readable only over
  serial/SSH, which in practice meant it was never read. Now on SatiSense under
  *Other → Utilities → Security event log* and on media-gateway on the Configuration
  page. Built to cost the data plane nothing, which was the explicit requirement:
  on-demand only (never on the 1 Hz diagnostics/status poll), `tail -n` so response
  cost is bounded by lines requested rather than log size, `lines` clamped server-side
  (default 200, max 2000) because it is attacker-controlled and streaming 4 MB through
  a CGI on an RV1106 would be a DoS against the console, and it runs in a short-lived
  CGI so the daemon is never involved. Verified: **zero** audit calls exist in the
  SatiSense C daemon, and media-gateway's three daemon-side records are per
  *connection*, never per frame.
  Remaining on this row for both: no off-device forwarding by default — designed and
  written up in [`audit-log-forwarding-plan.md`](audit-log-forwarding-plan.md), deferred
  pending a product decision. That plan also records the strongest reason to do it: if
  `/userdata` fails to mount, the vendor's `S20linkmount` reformats it, so an
  on-device-only trail has a single point of failure we cannot fix in our own code.

- **2026-08-08 — Platform + SatiSense Edge, Annex I #1/#2/#3 (gap 4a and row #1):
  BSP attack surface removed and secure defaults turned on. Confirmed on hardware
  after a reflash.**

  *Attack surface (luckfox-pico #12).* Four unauthenticated or near-unauthenticated
  remote-access paths inherited from the Rockchip BSP are gone from the image:
  **adbd** (ran as root with both auth paths inert — RSA auth gated on an unset
  `ADBD_RSA_AUTH_ENABLE`, and `/usr/bin/adb_auth.sh` never installed — and listened
  on `0.0.0.0:5555` as well as USB), **telnetd** (plaintext root shell on :23),
  **Samba** (`smb.conf` exported `[public]` with `path = /`, `read only = no`, as
  root), and the buildroot **stunnel** init script running the upstream Windows
  *sample* config. The RNDIS gadget (`usb0`) is deliberately retained — it ships in
  the same package as adbd — as is the stunnel binary, which the console needs.
  MaskROM recovery and SocToolKit flashing are unaffected; only `adb reboot loader`
  is lost.

  *SSH.* `PermitRootLogin` moves from `yes` to `prohibit-password` and the image
  ships a Joral **public** key. This decouples SSH from the root password rather
  than changing it — the vendor default simply stops being reachable. No private
  key material is distributed; see
  [`image-ownership-and-ssh-key-plan.md`](image-ownership-and-ssh-key-plan.md) for
  the customer-access policy still to be decided.

  *Secure defaults (satisense-edge #39).* `opcua.security` now ships as
  `signencrypt` and `web.tls` as `true`. Flipping the config alone would have been
  worse than useless: `apply_secure()` falls back to plain `None` when no
  certificate exists, so the config would have described a server that was not
  encrypted. `S60intelligence-edge` therefore mints each unit's own server
  certificate on first boot, mirroring what it already did for the console. Both
  fall back rather than fail if a keygen breaks.

  *Verified on hardware:* SSH accepts the key and refuses passwords; the console
  requires HTTPS; OPC UA refuses `None` and connects under Sign&Encrypt.

  *Known caveat, recorded deliberately:* `sshd` runs with `StrictModes no`, because
  `build.sh` packs the rootfs with `mkfs.ext4 -d` and no `fakeroot`, so **every
  inode in the image is owned by the build user (uid 1000)** — including `/`,
  `/etc` and `/etc/shadow`. StrictModes can never pass. The larger risk is latent:
  a service account added with an automatic UID lands at 1000 or above and would
  own the entire root filesystem, which matters precisely because CRA hardening
  pushes toward running daemons unprivileged. Planned in
  [`image-ownership-and-ssh-key-plan.md`](image-ownership-and-ssh-key-plan.md).

## Remaining work (verified against both trees 2026-08-07, refreshed 2026-08-08)

The documentation/build items (SBOM, compliance matrices, Annex II fact sheets) and
gap items 4c/4d/4e are closed above. What is actually left, deadline item first:

1. **Disclosure channel** — *deadline-bound: reporting obligations start 11 Sep 2026,
   ~5 weeks out, and apply to already-shipped units.* Blocked on Carl creating the
   security email alias; once it exists, wiring it into manuals + on-device Help via
   `/help-docs` is quick. The signed-firmware-update decision (4b) also sits with
   Carl — raise both together.
2. ~~**Attack surface (4a)**~~ — **largely done 2026-08-08**, see the status entry
   below. telnetd, adbd and Samba are out of the image and root SSH login is
   key-only. The root password itself is *unchanged* — still `luckfox` from
   `BR2_TARGET_GENERIC_ROOT_PASSWD` — but it is no longer reachable over the
   network. What is left on this row: the empty `/etc/iptables.conf` (the
   firewall restores a 0-byte ruleset, and IPv6 is uncovered entirely).
3. **Secure defaults (row #1)** — **closed for SatiSense Edge 2026-08-08**:
   `opcua.security` ships as `signencrypt` and `web.tls` as `true`, both with
   per-unit certificates minted on first boot. Still open: the default
   `admin`/`joral` console credential on both products, and the media-gateway
   console, which has no TLS option at all and is deliberately unchanged pending
   a comparison against MACH production.
4. **OpenSSL 1.1.1 migration plan (4f)** — none yet. The SBOM now auto-flags the
   EOL component, so closure will be self-verifying.
5. **CVE check as a release gate (row #2)** — feed the generated SBOM into a CVE
   scan per release; the inventory exists as of 2026-08-06, the process does not.
6. **Audit-log off-device forwarding** — the one item left on Annex I #6; designed
   in `audit-log-forwarding-plan.md`, deferred pending a product decision (action
   plan item 5).
7. **Media-gateway loose ends from the matrix work** — no LICENSE file / SPDX
   headers (needs an outbound-license decision; our own components show as
   UNDECLARED in the SBOM), and no test coverage of the auth layer, CGIs, config
   writer or listeners.
8. **Hardware bench session** — TC-S3 leg c (MQTT TLS) has still never run
   (unblocked 2026-08-05); the secrets-CGI path, factory reset and audit-log
   viewer are so far validated off-device only and need a flashed-image pass.
9. **Secrets at rest** — restricted (0600 sidecar) but not encrypted; accepted for
   now, revisit with the OpenSSL 3 migration.

## Default network exposure (Annex II facts, current truth)

*Superseded by the per-product fact sheets (`docs/compliance/cra-annex2-facts.md`
in each tree, 2026-08-06), which are verified against the listening code. Kept
here as the cross-product summary.*

- Platform (both, from shared rootfs), **updated 2026-08-08**: :22 sshd (**key-only**,
  `PermitRootLogin prohibit-password`), serial getty. **Removed from the image:** :23
  telnetd, :139/:445 Samba, adbd (which also listened on **:5555 on all interfaces**,
  not only over USB as stated previously), and the stray buildroot stunnel running the
  upstream sample config. The root password remains `luckfox`
  (`BR2_TARGET_GENERIC_ROOT_PASSWD`) but is no longer reachable over the network.
  **Caveat:** `/etc/iptables.conf` is a 0-byte ruleset, so nothing is filtered on any
  interface, and IPv6 is not covered at all — `ip6tables` exists but `S35iptables`
  only calls `iptables-restore`.
- Media Gateway: :80 web console (**HTTP-only, no TLS option exists**), **:8001** CAN↔Ethernet UDP-or-TCP (unauthenticated), br0 L2 bridge (T1S↔100BASE-TX) so both are reachable from either medium.
  **Correction (2026-08-06): :8000 is NOT bound.** `can_gw_comm_port` defaults to 8000 but the socket binds `comm_port + 1` only (`src/can_gateway/can_gw.c:519`, `include/media_gateway.h:126-127`). The audit row above and `docs/manual/quick-start.md:83` both overstated the exposure.
- SatiSense Edge, **updated 2026-08-08**: :8080 web console (**https by default** via
  stunnel, per-unit self-signed cert minted on first boot), :4840 OPC UA
  (**`signencrypt` by default**, per-unit server cert minted on first boot; anonymous
  sessions are still permitted — disabling that needs a credential to exist first);
  outbound only: Modbus TCP :502, EtherNet/IP scanner, MQTT :1883/:8883, LLM HTTPS.

## Action plan (agreed priority order)

1. ~~**Compliance matrix per product**~~ — **done 2026-08-06**, `docs/compliance/cra-annex1-matrix.md` in each tree. Keep updating per release, in the same commit as any change that moves a row.
2. ~~**SBOM from the build**~~ — **done 2026-08-06**, `./build.sh sbom`. Regenerate per release and keep the output with the technical file.
3. ~~**Annex II fact sheet per product**~~ — **done 2026-08-06**, `docs/compliance/cra-annex2-facts.md` in each tree. Re-verify per release; a stale fact sheet is worse than none because it gets copied verbatim.
4. **Gap backlog with CRA dates as milestones**:
   a. ~~strip telnetd/adbd/Samba~~ — **done 2026-08-08**; root password left unchanged
      but made unreachable over SSH (key-only login). Firewall ruleset still empty;
   b. signed firmware update path — flag to Carl per the doc;
   c. ~~factory-reset function (both products)~~ — **done: SatiSense 2026-08-06, media-gateway 2026-08-07**;
   d. ~~security-event logging~~ — **done 2026-08-07, met on both** (incl. CAN-gateway peer
      identity and a console viewer); off-device export deferred, see item 5;
   e. encrypt-or-restrict secrets in `gateway.json` — **done (restrict) 2026-08-06**, see above;
   f. OpenSSL 1.1.1 migration plan.
5. **Audit log export / forwarding** — the one item left on Annex I #6. Design options,
   requirements and a recommendation are written up in
   [`audit-log-forwarding-plan.md`](audit-log-forwarding-plan.md); **deferred pending a
   product decision on the delivery model** (push to syslog vs. let a collector pull).
   Headline: busybox already has `CONFIG_FEATURE_REMOTE_LOG=y`, so opt-in
   `syslogd -R` forwarding is a half-day change with no build impact — but a pull model
   fits the isolated-control-network assumption better and reuses the console endpoint
   that already exists.
6. **Disclosure channel** — once Carl creates the security email alias, reference it in on-device Help + manuals via the `/help-docs` pipeline.

Out of scope for engineering: CE marking, business classification, EU Declaration of
Conformity (product/legal level).
