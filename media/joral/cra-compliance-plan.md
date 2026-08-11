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
| 1 | Secure by default | ✅ **closed 2026-08-09**: default credential replaced on first sign-in (enforced in `require_auth`), console over HTTPS on 443 with a per-unit certificate minted on first boot. Residual: falls back to plain HTTP if the certificate or stunnel fails (availability trade — the daemon publishes which it is serving, so session cookies stay correct), and first-use trust rests on a self-signed certificate | ✅ default credential closed 2026-08-09; OPC UA `signencrypt` + console HTTPS by default with per-unit certs (2026-08-08). Residual: both still degrade to an open endpoint if a keygen or stunnel fails (by design, availability trade — the console now reports it), and first-use trust rests on comparing a self-signed fingerprint |
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
  legacy-plaintext redaction. **Bench-confirmed on the 2026-08-12 image**
  (operator verification): a secret stored from the console lands in the 0600
  sidecar, `gateway.json` stays secret-free, and the console API serves only
  the `__SECRET_UNCHANGED__` sentinel. That closes the "validated off-device
  only" caveat this entry originally carried — the automated suite pins the
  contract, but only a flashed unit proves the CGI, the daemon and the
  filesystem agree at runtime. Remaining for row #3: secrets are restricted,
  not encrypted at rest (no key store on this platform — accepted for now; the
  named revisit trigger, the OpenSSL 3 migration, fired 2026-08-12, so an
  encrypted sidecar is now implementable and awaits a product decision).
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
  has. ~~**Row #6 is now met for both products.**~~

  **Correction, 2026-08-12 (found in review of t1s-media-gateway #27):** that
  closing sentence was wrong, and wrong in the direction that matters. The work
  above instruments `accept()`, which exists only on the **TCP** path — but
  `can_gw_proto=udp` is the shipped default (`src/main.c:84`,
  `scripts/default/gateway.conf:33`). UDP is connectionless: no accept, no client
  lifecycle, no record. `handle_udp_rx()` *does* receive the source address from
  `recvfrom()` and uses it solely to suppress our own broadcast echo, so the
  address is available and deliberately discarded. The consequence is precisely
  the one this entry claimed to close: **on a factory-configured unit, the write
  path equivalent to CAN bus access has no accountability at all.** Row #6 is
  **partial** for media-gateway, not met. Interim mitigation is `can_gw_proto=tcp`
  where accountability is required; the fix under consideration is a
  first-seen-peer record backed by a small recent-source table, because
  per-datagram logging would evict the entire audit history in seconds — the same
  rotation-as-evidence-destruction failure as the original 256 KB cap.

  *Worth recording as a review lesson:* this survived the original implementation,
  its tests, the matrix write-up and a hardware bench pass, because every one of
  them exercised the TCP path. A control verified only on a non-default
  configuration has not been verified.

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

- **2026-08-09 — both products, Annex I Part II §4–6 (disclosure channel): the
  engineering half is done.** The address is decided — **`security@joralllc.com`**,
  chosen over `psirt@` because RFC 2142 makes `security@` the address researchers
  try unprompted, and a small vendor is found by convention, not by PSIRT branding
  (recommendation: also create `psirt@` as a free alias to the same group). Wired
  into both products: a *Reporting a security vulnerability* entry in each user
  manual's maintenance section (media-gateway §8, SatiSense §12.3) telling the
  operator what to include (build identifier, description, repro) and what never
  to include (secrets), regenerated into the on-device Help HTML and all customer
  PDFs; and a coordinated-disclosure policy as `SECURITY.md` in each tree —
  report contents, response commitments (receipt confirmation, coordinated
  disclosure date, plain-language fix notes naming affected builds, free
  updates, credit), scope, and the documented deployment context as the severity
  baseline. Matrix rows Part II §5/§6 move to **partial**: what is left is not
  engineering — **the mailbox itself must be created** (Workspace group:
  product management + at least one engineer, `psirt@` aliased in) and the
  policy published on joralllc.com (`/.well-known/security.txt`). Until mail to
  the address is actually received, the row is not "met", and the documents
  must not ship to customers before the mailbox is live.

- **2026-08-09 — both products, Annex I Part I §2 / Part II §2 (CVE screening): the
  release gate exists, and its first run says the image is not shippable as it
  stands.** `./build.sh cve` → `scripts/compliance/cve-check.py`, the companion to
  the SBOM: the SBOM says what is in the image, this says what is known to be wrong
  with it, and both derive their component list from the same Buildroot `.config` so
  they cannot describe different images. Exit status *is* the gate — 0 clean, 1
  blocking findings, **2 the check could not be completed**, which is a deliberate
  third state so a CI job can tell "we found problems" from "we learned nothing".
  Documented in `scripts/compliance/README.md`; 39 contract tests in
  `scripts/compliance/test-cve-check.py` (no network — `--offline` reads only the
  cache, which makes the cache the test seam), each confirmed to fail against a
  checker mutated back to the wrong behaviour.

  Four things came out of building it that were not visible from the plan line
  ("feed the SBOM into a CVE check"):
  - **Buildroot's own CVE checker is dead in this tree.** `support/scripts/cve.py`
    downloads NVD's JSON 1.1 data feeds, which NIST retired — the URLs answer
    **403** now, so `make pkg-stats` cannot produce CVE data at all. The gate uses
    the NVD 2.0 REST API and lets NVD resolve version ranges server-side
    (`virtualMatchString`), which is the part a hand-rolled matcher gets subtly
    wrong.
  - **Component identity is Buildroot's, not ours.** `make show-info` emits the
    resolved `cpe-id` for each package *at the version actually built*, plus any
    `<PKG>_IGNORE_CVES` upstream recorded — so there is no name→CPE table to
    maintain and rot. 73 of the 130 target packages carry one. The other 57 are
    reported as **NOT CHECKED, by name**, never counted as clean; that honesty is
    the difference between a gate and a rubber stamp.
  - **The kernel, U-Boot and the Rockchip SDK are not Buildroot packages**, so a
    package-list-driven check would have omitted the largest components in the
    image entirely. `cpe-extra.csv` adds them. The kernel matches **5098** NVD
    records (1683 at CVSS ≥ 7.0) and U-Boot 2017.09 matches 41 — which is why they
    are `MODE=report-only`: a vendor kernel is remediated by moving its base, not
    by dispositioning five thousand records against a version we do not control.
    Counted and listed, never blocking, so the decision to treat them differently
    is visible instead of implicit.
  - **Triage carries an expiry date.** A finding stops blocking only via a row in
    `cve-triage.csv` with a decision, a checkable justification, an owner and a
    `REVIEW_BY` date; past that date it blocks again, and a malformed row is
    rejected rather than ignored. An unexpiring allowlist turns "accepted for now"
    into "forgotten", which is the exact failure "without delay" is aimed at.

  **First run (2026-08-09, build `v1.0.0-61-g6ba7406eb`): 100 blocking, 120 below
  threshold, 15 suppressed by Buildroot's own `ignore_cves`, 76 of 141 components
  checked.** Two findings to act on by name: **CVE-2025-27363 in freetype 2.12.1**
  is the one entry in **CISA KEV** — an out-of-bounds write in font subglyph
  parsing, i.e. known-exploited, which is precisely the wording Annex I Part I §2
  uses — and **CVE-2025-54349 in iperf3 3.14** scores **10.0**.

  **The result that changes the remediation order: 73 of the 100 blocking findings
  are in packages neither product needs.** They are inherited from the Luckfox BSP
  defconfig, and `show-info`'s reverse-dependency data says exactly why each is
  present: ffmpeg (**23 findings**) only because **mpv** is selected; python-pillow
  (13); libglib2 (14) and python3 (5), which come from the unused
  bluez/pulseaudio/dbus-python/dbus-glib stack — `avahi.mk` links both only *if
  they happen to be enabled* (`ifeq ($(BR2_PACKAGE_LIBGLIB2),y)`, and it configures
  `--disable-glib --disable-python` without them), so mDNS does not hold them in;
  freetype (the KEV) via harfbuzz/libass/python-pillow/sdl2_ttf; and rsync (7),
  p7zip, python-werkzeug, iperf3, lrzsz, zip and python-setuptools selected
  **directly in the defconfig**. Verified against both product trees: no
  dbus/bluetoothd/pulseaudio reference in either product's runtime code or init
  scripts, no PIL import, and no invocation of ffmpeg/mpv/rsync/7z/madplay.

  **8 more (expat) cannot be removed**: both avahi-daemon and dbus require it, and
  avahi is *deliberate* — it was added 2026-08-04 (ADR-147, satisense-edge #30) to
  publish `satisense.local` so the OPC UA server certificate's DNS SANs survive a
  DHCP lease change. That is the one place where a security control we added last
  week is itself the reason a CVE surface stays; it belongs in the triage file with
  that reasoning, not in the removal list.

  Only **19** findings sit in components the products actually use — libopenssl (13,
  already tracked as the EOL migration), busybox, libcurl (the LLM client), libzlib,
  dhcpcd and busybox-selected wget.

  So the cheapest path to closing row #2 is **not** 100 triage rows: it is trimming
  the defconfig, which removes ~80% of the blocking findings and narrows Annex I #4
  at the same time (avahi is network-facing mDNS on :5353). This is the same
  defconfig-inheritance problem as telnetd/adbd/Samba on 2026-08-08 — the BSP ships
  a media/desktop package set for camera/IPC products, and ours use almost none of
  it. Recorded as the next item rather than done, because removing packages from a
  shared rootfs needs a build-and-bench pass on both products, not just a
  `.config` edit.

  **Row #2 therefore moves from ❌ (no process) to "process in place, findings
  open"** for both products — the machinery is closed, the image is not clean, and
  the gate now says so on every run. Also recorded as a coverage gap: 56 components
  have no CPE from any source (mostly `python-*` and leaf libraries), listed by name
  in every report; `cve-check.py --suggest-cpe` resolves candidates against the NVD
  CPE dictionary and Buildroot's `make missing-cpe` can upstream the mapping.

- **2026-08-10 — both products, Annex I #4: two more BSP leftovers found while
  refreshing the compliance matrices against the *built* image** (rather than
  against the tree, which is how both had been checked before):
  - **`S99python` executes `/root/main.py` — or `/root/boot.py` — as root at every
    boot** if the file exists. It is a Luckfox convenience feature for their
    MicroPython-style demos and has no place in a product image: it is an
    unauthenticated, persistent root code-execution hook that no product component
    uses. It also compounds the uid-1000 image-ownership caveat already recorded in
    [`image-ownership-and-ssh-key-plan.md`](image-ownership-and-ssh-key-plan.md) —
    `/root` is owned by uid 1000 in the packed image, so write access as that uid
    becomes root execution on the next boot.
  - **`S40bluetoothd` starts a root Bluetooth daemon, with `S99hciinit`** attaching
    an HCI UART when an `aic8800` module is present. Neither product has any
    Bluetooth function. `bluetoothd` runs regardless of whether the radio attaches.
  Both are in the current image (`output/out/rootfs_uclibc_rv1106/etc/init.d/`,
  built 2026-08-09), i.e. *after* the 2026-08-08 hardening — that pass removed
  network daemons (telnetd, adbd, Samba, the stray stunnel) and did not look at
  locally-started ones. Folded into gap item 4a with the package trim, since it is
  the same defconfig-inheritance root cause and the same build-and-bench pass.

  Method note worth keeping: both were invisible to every previous review because
  the matrices were checked against the source tree. Checking the **packed rootfs**
  found them in minutes. Annex I #4 should be re-verified against the image, not
  the tree, at each release.

- **2026-08-10 — correction to the 2026-08-09 CVE entry.** That entry, and the row
  it created in both product matrices, said "~81 of the 100 blocking findings are in
  packages neither product uses" and listed **avahi** among the unused. That was
  wrong: avahi is deliberate — added 2026-08-04 (ADR-147, satisense-edge #30) to
  publish `satisense.local` so the OPC UA certificate's DNS SANs survive a DHCP
  lease change. The corrected split is **73 removable / 8 held in by avahi / 19 in
  components we use**: avahi-daemon and dbus both require **expat** (8 findings), but
  `avahi.mk` links libglib2 and python3 only *if they are already enabled*
  (`ifeq ($(BR2_PACKAGE_LIBGLIB2),y)`, configuring `--disable-glib --disable-python`
  otherwise), so those 19 findings are held in by the unused
  bluez/pulseaudio/dbus-python stack and not by mDNS. The plan text and both
  matrices are corrected.

- **2026-08-10 — Platform (both products), Annex I #2 and #4: the BSP package set
  is trimmed and the image rebuilt. The CVE gate goes from 100 blocking findings
  to 19, and the only known-exploited component is gone.**

  `luckfox_pico_w_defconfig` now deselects the media/desktop package set the
  Luckfox BSP ships for camera and MicroPython demo boards: **339 → 221 config
  entries, 118 packages removed, none added.** mpv was the root of most of it —
  it pulled ffmpeg (23 findings), sdl2, and libass → harfbuzz → **freetype**,
  which carried the image's only CISA-KEV entry (CVE-2025-27363). Also out:
  bluez5_utils, pulseaudio, jack2, sox, madplay, ALSA, iperf3 (the CVSS 10.0),
  iperf, rsync, lrzsz, p7zip, zip, and every third-party python module
  (pillow, werkzeug, setuptools, aiohttp, …) with their ~15 transitive deps.

  Deselecting `bluez5_utils` also removed **dbus** and **libglib2**, which only it
  and pulseaudio held in — confirming the 2026-08-10 correction above: avahi
  needs expat, not glib or python.

  *Three things this pass established that the plan line ("trim the defconfig")
  did not anticipate:*
  - **A config edit alone would have changed nothing.** Buildroot never
    *uninstalls* a package: deselecting mpv stops it being built, but its files
    stay in `output/target` from the previous build and ride into the image. The
    trim only became real by clearing `output/` and rebuilding from empty. Any
    future package removal needs the same, and the verification has to be against
    the packed rootfs — checking the tree would have shown a clean result either
    way.
  - **python3 is not what the 2026-08-09 entry said it was.** It is not held in by
    the dbus stack; it is selected directly, and the on-device bench tooling
    (`satisense-edge/scripts/bench/*.py` — how TC-S3 and the commissioning gates
    are actually executed against a flashed image) needs it. Removing it in the
    same pass would have meant validating an image we do not ship. The
    interpreter is kept and its 5 findings are recorded as a dated
    `accepted-risk`, with dropping it and running bench tooling from a separate
    test image as the stated end state. The `S99python` boot hook was removed the
    same day, so nothing invokes it at runtime.
  - **The expat decision is now evidence-backed rather than asserted.** Verified
    in avahi-0.8: expat is included only by `avahi-daemon/static-services.c`,
    which parses `AVAHI_SERVICE_DIR "/*.service"` (static-services.c:904) —
    root-owned local files. mDNS wire packets are decoded by avahi's own record
    parser, never by expat, so no network input reaches the vulnerable code.
    Recorded as 8 `not-affected` rows rather than an accepted risk.

  Removed in the same pass, from the board overlay: **`S99python`** (executed
  `/root/main.py` as root at every boot) and **`S99hciinit`**. `S40bluetoothd`
  and `S30dbus` left with their packages. All four verified absent from the
  packed rootfs, along with mpv, ffmpeg, iperf3, rsync, 7z, zip, and the
  libav*/SDL2/freetype/harfbuzz/glib/dbus/asound/pulse libraries.

  **Gate result (build `v1.0.0-61-g6ba7406eb`, 2026-08-10): 19 blocking** (was
  100), 80 monitor (was 120), 13 suppressed by triage, 15 by Buildroot's own
  `ignore_cves`; 40 of 68 components checked (was 76 of 141), so the unchecked
  count falls from 56 to 28. **Zero CISA-KEV entries.** The 19 that remain are
  exactly the set the 2026-08-09 entry predicted — **libopenssl ×13, wget ×2,
  busybox, libzlib, libcurl, dhcpcd** — all components the products genuinely
  use, so none can be removed. 13 of 19 are the OpenSSL 1.1.1 migration, which
  makes item 4 below *the* remaining item on row #2 rather than one of several.

  *New finding, from checking the packed image rather than the tree:*
  **10 prebuilt vendor binaries ship in `/usr/bin` that neither the SBOM nor the
  CVE gate can see.** `project/app/wifi_app/` copies three `wpa_supplicant`
  variants, `wpa_cli` ×2, **`hostapd`**, **`dnsmasq`**, `iperf` and
  `rkwifi_server` (plus 3 libraries) into the rootfs via `build.sh:1424`, outside
  Buildroot entirely — so they appear in neither the Buildroot-derived component
  list nor the hand-declared `app-manifest.csv`. They are stripped, carry no
  version, and no init script starts any of them. This is the same class of blind
  spot `cpe-extra.csv` closed for the kernel and U-Boot, and it is why the
  surviving `iperf` binary did not disappear when `BR2_PACKAGE_IPERF` was
  deselected. Recorded as the next item; the decision is whether to declare them
  or stop shipping them.

- **2026-08-11 — the console-proxy work of 2026-08-10/11 was REVERTED, and the
  two defects it found on hardware were NOT introduced by it.**

  A day and a half of work replaced each product's stunnel with a single nginx
  reverse proxy (ADR-151), moved ports twice, and added an `RK_JORAL_PRODUCT`
  selector. It was reverted at the operator's request: the SDK layer and the
  product layer had become entangled — an init script in the board overlay knew
  both products' names, ports, backend sockets and URL paths — and the design was
  churning faster than it could be verified on hardware. The console is back on
  the ADR-129 stunnel arrangement. **ADR-151 is withdrawn, not superseded.**

  Kept from that period, because it is independent of the console: the Buildroot
  package trim (100 → 19 blocking findings), the CVE gate and its triage record,
  the removal of `S99python`/`S99hciinit`, and the `wifi_app` finding below.

  **Two defects were found by putting the design on a device, and both are
  PRE-EXISTING — the revert restores them, it does not remove them:**

  1. **The media-gateway console backend binds every interface, not loopback.**
     `start_httpd()` passes a bare port number to busybox httpd, so the backend
     is reachable directly on **:18080**, bypassing stunnel and therefore
     bypassing TLS. Both this product's Annex I and Annex II sheets state it
     binds `127.0.0.1` only. That claim is false today, at HEAD, and has been
     since the loopback split was introduced.

  2. **The audit log records the tunnel, not the operator.** `audit_log()` uses
     `REMOTE_ADDR`, which behind stunnel is always loopback — and, because of
     defect 1, arrives in the IPv4-mapped form `[::ffff:127.0.0.1]`. Every
     console action on this product is attributed to the device itself. Verified
     on hardware 2026-08-11: SATISense logged `src=172.32.0.100` (it binds
     loopback explicitly and had forwarded-header handling at the time) while
     media-gateway logged `src=[::ffff:127.0.0.1]` on the same unit and the same
     build. The **Annex I §6 trail for the media gateway is therefore complete,
     well-formed, and attributed to the wrong principal.**

  Neither is visible from a browser: the console works correctly in both cases.
  Both need fixing on the reverted design, independently of any console
  architecture — an explicit `127.0.0.1:<port>` bind spec, and a peer identity
  that survives a local TLS terminator. **Until then both products' Annex I #6
  and Annex II port rows overstate what the shipped image does.**

  *The process lesson, recorded because it cost the whole period:* the fault that
  started it was diagnosed three times from source and never once from the
  device, because the init script ran nginx as `>/dev/null 2>&1` and threw away
  the one line that named the cause. A service that can fail at boot must be
  built so its first failure is legible from the boot log. That applies equally
  to the stunnel path this revert restores, which discards its output the same
  way.

- **2026-08-12 — defect 1 above is CLOSED, and it was hiding a third defect: the
  two products were serving each other's consoles.**

  Reported from a browser: `https://<ip>:8080` — satisense-edge's console port —
  returned the **media-gateway** UI. Root cause is defect 1 plus a shared port.
  Both products terminate TLS with their own stunnel in front of their own
  busybox httpd, and both backends were on **18080**. media-gateway starts first
  (S50 vs S60) and, because of defect 1's bare `-p`, bound it on *every*
  interface; satisense's backend then died silently on `EADDRINUSE`
  (`start-stop-daemon -b` reports the fork, not the outcome), and satisense's
  stunnel bound :8080 and forwarded to whatever owned 18080 — the other product.
  Both init paths then reported a clean start, because each verified only that
  its **public** port was listening, which its own stunnel satisfied either way.

  Fixed in both trees:
  - **Explicit loopback bind** — `start_httpd()` now takes a bind *spec* and the
    TLS path passes `127.0.0.1:<port>`. This is what closes defect 1: the
    backend is no longer reachable in the clear from the network, so **both
    products' Annex I #6 and Annex II port rows are now true of the shipped
    image.** The plaintext path still passes a bare port, deliberately.
  - **Per-product backend ports** — satisense keeps 18080, media-gateway moves to
    **18081**. Both constants carry a comment naming the other product, since
    neither tree can see the other and nothing else would catch a future clash.
  - **Backend liveness** — readiness now requires *our* httpd **and** *our*
    stunnel **and** the public port, and the backend is confirmed **before**
    stunnel is started, so a misrouting proxy is never stood up rather than
    unwound afterwards. Both fall back to plaintext and say which half failed;
    the last-resort plaintext path reports a console that could not bind instead
    of assuming it came up. Note the wait before the check is load-bearing — a
    just-forked child is trivially alive, so the old check would have passed.

  Verified: clean cross-compile, and 10 new source-level regression assertions
  across both suites, each confirmed to FAIL against the pre-fix code.
  **Bench-confirmed 2026-08-12, both halves.** `http://<ip>:18081` is refused
  from the network — though that flash also carried the new firewall, which
  refuses the port regardless of where the backend bound, so the probe alone
  could not isolate the bind. The isolating check was run on the device and
  passes:

      # netstat -ltn | grep 1808
      tcp  0  0  127.0.0.1:18080  0.0.0.0:*  LISTEN
      tcp  0  0  127.0.0.1:18081  0.0.0.0:*  LISTEN

  Both backends are bound to loopback **only** — no `0.0.0.0` or `:::` line —
  so the per-product port split (18080 satisense / 18081 media-gateway) and
  the explicit bind spec are both live in the shipped image. The Annex I #6
  and Annex II port rows on both products are now true of a flashed unit, with
  the firewall as a second, independent control rather than the only one.
  **Bench 2026-08-12 (same day, see entry below): both consoles confirmed serving
  their own UI over HTTPS — the functional half of this fix.** The explicit
  loopback-reachability check (`netstat -ltn`, direct `http://<ip>:18081`
  refused) has still not been run; until it is, the Annex II port rows rest on
  the source-level assertions rather than a device observation.

- **2026-08-12 — defect 2: the false attribution is removed; the true identity
  is NOT yet inline. Partial close, and the scope was wider than recorded.**

  **Correction to the 2026-08-11 entry: this is not a media-gateway-only defect.**
  That entry credited satisense with "forwarded-header handling at the time" —
  that handling belonged to the withdrawn ADR-151 nginx and went away with the
  revert. Both products' `_audit_principal` are byte-identical today, and
  satisense ships `web.tls: true`, so **both** log every console action as
  loopback. The Annex I §6 trail names the wrong principal on both products.

  **Why it cannot simply be fixed with a forwarded header:** stunnel 5.65 — the
  version in the image — *cannot* add `X-Forwarded-For`. It is an unimplemented
  entry in the shipped `TODO.md`, not a config option. stunnel can emit PROXY
  protocol (`protocol = proxy`), but busybox 1.36.1 httpd cannot consume it
  (`FEATURE_HTTPD_PROXY` is an outbound reverse-proxy feature, unrelated). So
  inline attribution needs one of: patching busybox httpd, a PROXY-aware shim,
  TPROXY (`transparent = source`, needing kernel + iptables work), or a
  different terminator — which is ADR-151, withdrawn. All are production-
  affecting; none were taken.

  **What was done instead, in both trees** (`_audit_src()` in `webauth.sh`):
  - **Stop asserting a falsehood.** Loopback while TLS is on is recorded as
    `src=unknown-via-tls` — deliberately not an address, so no reader mistakes
    it for the operator. This is the part that was actually wrong: the old
    record was not merely incomplete, it was *confidently incorrect*.
  - **Trust a forwarded address only from our own terminator** — loopback AND
    TLS on. The backend binds `127.0.0.1` exclusively on that path (closed the
    same day, above), so nothing on the network can reach httpd to forge it.
    On the plaintext path httpd owns the public port and the header is ignored,
    because there it is attacker-supplied. This is inert with stunnel 5.65 and
    becomes live the moment any terminator supplies the header.
  - Forwarded values still pass `_audit_principal`, so they cannot forge fields.

  **The true peer identity already exists on the device:** stunnel logs
  `Service [web] accepted connection from <ip>:<port>` at LOG_NOTICE, and
  `log_syslog` defaults to on, so it is in syslog today on both products. The
  audit trail is therefore **correlatable by timestamp** rather than
  self-contained. That is a real limitation to state in the Annex II sheet, not
  a closure: concurrent sessions cannot be told apart by timestamp alone.

  Verified: 20 new assertions across both audit suites, the 4 behavioural ones
  confirmed to FAIL against pre-fix code. **Bench-confirmed on SatiSense
  2026-08-12**: the durable trail on `/userdata/satisense/audit.log` carries a
  full operator session — `login … default_password=true`, `password_change`,
  `config_save` with `cfg_sha` fingerprints, `service_restart` — every record
  attributed `src=unknown-via-tls`, none to the pre-fix false loopback
  address. (The same pass first found the file *absent*: reflashing rewrites
  the userdata partition, so a flash destroys the trail exactly as the
  `S20linkmount` reformat would — recorded as a further argument for
  off-device forwarding, item 6 of the remaining-work list.) Still to spot-check:
  the same durable-file write on the media-gateway path
  (`/userdata/media-gateway/audit.log`), and a failed-login record correlated
  against stunnel's `accepted connection from <ip>` syslog line. **Annex I #6
  still reads "attribution incomplete, correlatable via syslog" — the
  sentinel is confirmed working, but it is by design not the operator's
  address, so the row stays open.**

- **2026-08-12 — both products, Annex I #2 (item 4f): the OpenSSL 1.1.1 → 3.5 LTS
  migration is implemented; the rebuild and verification are pending.** Full
  write-up in [`openssl-3-migration-plan.md`](openssl-3-migration-plan.md);
  headlines:
  - **Target is 3.5.7 (LTS to 2030-04), not 3.0** — 3.0 goes EOL 2026-09-07,
    four days before our reporting obligations begin; migrating onto it would
    recreate the finding being closed.
  - Scoping came back clean: 1.1.1v is *stock* Buildroot 2023.02 (verified
    against the pristine tarball — not a Luckfox pin), **no Rockchip vendor blob
    links libssl/libcrypto**, the `wifi_app` prebuilts carry their own static
    crypto, no `openssl` CLI exists in the image, and our `certgen.c` was
    already written against the 3.x-safe EVP API. Every consumer is rebuildable.
  - Package recipes backported from buildroot 2025.08.x as tracked masters
    (`sysdrv/tools/board/buildroot/{libopenssl,open62541}/`) with a copy step in
    `sysdrv/Makefile`, following the `busybox.config` precedent; the seven
    1.1.1-only patches are removed by that step. **open62541 goes v1.3.4 →
    v1.3.15 in the same pass** — 1.3.4 predates OpenSSL 3 support in its series;
    1.3.15 is the version upstream pairs with OpenSSL 3.x (recipe diff is the
    version string alone).
  - The 3.x recipe's algorithm-gating options default on, so no dependent
    package (pppd's DES, python's BLAKE2) silently loses a feature and the
    defconfig is untouched.
  - Buildroot `output/` was wiped 2026-08-12 (the soname change makes the
    never-uninstalls hazard worse than usual: an incremental build would ship
    both libssl generations with consumers split between them), and both new
    source tarballs are already downloaded and hash-verified in `dl/`.
  - Verification is scripted: `scripts/compliance/verify-openssl3-migration.sh`
    (no stale 1.1 linkage, old libs gone, daemons on `.so.3`, open62541 at
    1.3.15, ADR-151 nginx leftovers gone), then `make test` in both product
    trees, `./build.sh sbom` (the EOL flag clears itself) and `./build.sh cve`
    (13 of 19 blocking findings should resolve). Hardware bench items fold into
    the pending bench session (item 8), which now also re-validates OPC UA
    Sign&Encrypt under open62541 1.3.15.

  **Build + verification completed 2026-08-12** (image `update.img` built from
  `v1.0.0-66-g2d4b29958-dirty`). Two build-fallout items, both fixed and
  recorded in the migration doc: pppd 2.4.9's EAP-TLS needs the OpenSSL ENGINE
  API (3.x builds without it — disabled via a tracked `pppd.mk` overlay; no
  product uses PPP EAP-TLS, MSCHAP keeps OpenSSL DES), and **the live buildroot
  tree was still building the ADR-151 nginx** because defconfigs are only
  copied at extract time — the revert never reached the built tree, and this
  run had already installed 20 files including an `S50nginx` init script (all
  purged; masters re-synced). Verification: all five image checks pass, both
  product suites green, SBOM reports **libopenssl 3.5.7 supported branch**
  (51 platform components), CVE gate **19 → 6 blocking** — every libopenssl
  1.1.1 finding resolved; one new match against 3.5.7 (CVE-2019-0190) is an
  Apache-httpd-only false positive, triaged `not-affected` with the CPE-config
  evidence. The remaining 6 (busybox, libzlib, wget ×2, libcurl, dhcpcd) are
  the pre-existing item-5b set. **Hardware-confirmed the same day**: the
  flashed image serves the console over HTTPS by default and establishes an
  OPC UA Sign&Encrypt session under open62541 1.3.15 / OpenSSL 3.5.7, so
  row #2's OpenSSL resolution is bench-backed. MQTT TLS (TC-S3 leg c) has
  still never run on any stack and stays with item 8.

- **2026-08-12 — hardware bench (partial): the trimmed image is confirmed on
  hardware.** The package-trimmed image was flashed and verified on a device:
  boot, console **HTTPS on both products** (each serving its own console — the
  functional confirmation the same-day port-collision fix was waiting on),
  OPC UA **Sign&Encrypt**, mDNS (`satisense.local` still published with avahi
  running without dbus), CAN, and the on-device bench scripts (the reason
  python3 was kept). That closes the bench caveat on the 2026-08-10 trim:
  **nothing either product depends on was among the 118 removed packages.**
  Not run this session, so still open from the two 2026-08-12 fix entries
  above: the explicit loopback-bind check (`netstat -ltn` showing 18080/18081
  on 127.0.0.1 only, a direct `http://<ip>:18081` refused) and the
  audit-attribution records. Deferred by decision for now: TC-S3 leg c (MQTT
  TLS), the secrets-CGI path, factory reset and the audit-log viewer on
  hardware.

- **2026-08-12 — Platform (both products), Annex I #2 and #4: the CVE gate
  PASSES (0 blocking, was 6), the firewall exists (IPv4 **and** IPv6,
  default-deny), and the unscannable `wifi_app` binaries are dropped from the
  build. All of it flashed and bench-confirmed the same day — see the
  verification note at the end of this entry.**

  *CVE gate to zero (item 5b/5c).* The 6 blocking findings that survived the
  OpenSSL 3.5.7 migration are triaged with checkable evidence in
  `cve-triage.csv`, none of them by waving: **busybox CVE-2022-48174** is fixed
  upstream before 1.35 (we build 1.36.1) and matches only because the NVD
  configuration carries no version bound; **libzlib CVE-2023-45853** is in
  contrib/minizip, which `libzlib.mk` never compiles; **wget CVE-2026-58469**
  is in metalink code that is only built `--with-metalink` against a
  libmetalink Buildroot does not have; **libcurl CVE-2025-0725** requires zlib
  ≤ 1.2.0.3 at runtime (image ships 1.2.13); **wget CVE-2024-38428** is real at
  our version and is an *expiring* accepted-risk — GNU wget is invoked by
  nothing in either tree (verified; busybox has its own applet), and the
  resolution recorded is dropping the package at the next respin; **dhcpcd
  CVE-2026-56116** is `fixed-pending-release`: `/etc/dhcpcd.conf` now sets
  `ipv4only`, so the vulnerable RA parser can never receive input. The CPE
  coverage gap closed the same day: all 19 remaining unmapped components were
  resolved against the NVD CPE dictionary — exactly one (GNU nano) has an NVD
  identity and is now queried; the other 18 are documented `CPE=NONE` rows
  (Buildroot-internal skeletons, data-only ca-certificates, and projects NVD
  has never issued against under any name — htop, bmon, can-utils, libiconv,
  libdrm, libv4l, dialog/cdialog, GNU time, evtest, argp-standalone,
  libpthread-stubs). **Gate result: 0 blocking, 74 monitor, 41 of 68
  components checked + 27 with documented no-NVD-presence, exit 0.** The
  compliance suite grew to 45 checks, all passing.

  *Firewall (the largest single Annex I #4 item).* The board overlay
  (`overlay-luckfox-buildroot-init`) now ships `/etc/iptables.conf`,
  `/etc/ip6tables.conf`, an `S35iptables` override that loads **both** families
  and reports a failed restore to syslog (the boot-legibility lesson from the
  nginx period, applied), and the `ipv4only` dhcpcd.conf. Design points worth
  recording: IPv4 INPUT is default-deny admitting only the ports the Annex II
  fact sheets document (22, 443, 8080, 4840, 8001 TCP+UDP, mDNS 5353, DHCP
  client 68, rate-limited ping, IGMP — the last so IGMP-snooping switches do
  not prune mDNS); **IPv6 admits no service at all** — this closes a real gap,
  since several daemons bind dual-stack and every console was silently
  reachable over IPv6 link-local, outside anything the fact sheets stated. RAs
  are dropped (no SLAAC) and NS/NA kept. FORWARD is DROP on both families,
  which is safe for the media-gateway T1S bridge because
  `CONFIG_BRIDGE_NETFILTER` is not built — verified in the kernel `.config`,
  as was every match/target the rulesets use (conntrack, limit, icmp/icmp6 all
  present as `=y` + the userspace extensions in the packed image). EtherNet/IP
  implicit I/O (UDP 2222) is deliberately not opened; the rule ships
  commented with instructions. The stock `S35iptables` `stop` had a lockout
  bug waiting: it flushed rules without resetting policies — harmless with
  empty chains, a total network cutoff with default-deny ones — so the
  override resets policies to ACCEPT before flushing.

  *wifi_app (item 5e): dropped, not declared.* The trigger was
  `RK_ENABLE_WIFI=y` in the Ultra board config — with SSID/PSK still at the
  BSP's literal `"Your wifi ssid"` placeholders, so the stack could never have
  associated with anything. Now `n`; the stale `install_out`/`app_out`
  payloads (hostapd 2.6, wpa_supplicant 2.6, dnsmasq, iperf, rkwifi_server +
  libs) are cleared so a repack cannot resurrect them — the same
  "Buildroot never uninstalls" failure mode as the package trim, one layer up.

  **Bench-confirmed 2026-08-12 on a flashed unit**, and the checks were the
  affirmative kind, not just "services still work" (an unfiltered unit answers
  on the allowed ports identically to a filtered one, so service reachability
  alone proves nothing about the filter):
  - **both rulesets loaded** — `iptables -L` / `ip6tables -L` show the
    default-deny chains on the device;
  - **a blocked port probed and refused** from the network (`:18081`, the
    console backend);
  - **services confirmed through the filter** — OPC UA Sign&Encrypt from
    UaExpert, console HTTPS, CAN, SSH;
  - **wifi binaries absent** from `/usr/bin` on the flashed image, and the
    unit **acquires its DHCP lease under `ipv4only`** (the dhcpcd
    CVE-2026-56116 fix is therefore deployed and non-breaking).
  One scope note: with the firewall active, the `:18081` refusal no longer
  *isolates* the loopback-bind fix — the filter would refuse that port even if
  the backend had bound every interface. The externally observable claim
  (backend unreachable in the clear) is confirmed, with two independent
  controls now behind it; `netstat -ltn` on the device remains the check that
  would isolate the bind itself.

- **2026-08-12 — correction to the defect-2 entry above: the forwarded-header
  rule was itself a forgery vector, and it is removed. Both products.** Caught
  by automated review (Greptile) on the two PRs, which scored them down for it
  — and the finding survives scrutiny. The entry above reasoned that a
  forwarded address could be trusted "only from loopback while TLS is on"
  because the backend binds `127.0.0.1` and "nothing on the network can reach
  httpd to forge the header", and called the branch "inert with stunnel 5.65".
  Both claims were wrong the day they were written: **stunnel is a byte-level
  tunnel** — it relays the remote client's HTTP request verbatim and neither
  adds nor strips headers — so on exactly the loopback+TLS path,
  `X-Forwarded-For` is *remote-client-supplied*. The branch was not inert; it
  let any HTTPS client name an arbitrary `src=` for every audited action,
  which is strictly worse than the loopback bug it replaced (an attacker
  could frame a specific address instead of everything reading as the
  device). Fixed in both trees: the header is **never consulted**; loopback
  under TLS always records `unknown-via-tls`, and correlation stays via
  stunnel's syslog peer line as designed. Trusting a forwarded address again
  requires a terminator that both strips inbound copies and injects its own
  (or PROXY protocol end-to-end) — a future console-architecture decision,
  not a config tweak. Tests flipped accordingly (the two trust-codifying
  assertions now assert the header is ignored) and confirmed to FAIL against
  the pre-fix code. The same review also caught that the **satisense
  plaintext last-resort still trusted a just-forked httpd pid** — the same
  async-bind-failure race the TLS path already guarded ("the wait is
  load-bearing"), unapplied to the fallback of last resort; it now polls the
  port with the same loop shape, with two new guarding assertions.
  *Method note: this is the second time in two days that reasoning about
  this exact boundary was wrong in review-visible ways (2026-08-11's
  satisense "forwarded-header handling" mis-credit, and now this). The
  boundary — who supplied which bytes on the tunnel path — evidently needs
  adversarial review, not authorship-time reasoning.*

## Remaining work (verified against both trees 2026-08-07, refreshed 2026-08-10)

The documentation/build items (SBOM, compliance matrices, Annex II fact sheets) and
gap items 4c/4d/4e are closed above. What is actually left, deadline item first:

1. **Disclosure channel** — *deadline-bound: reporting obligations start 11 Sep 2026,
   ~4.5 weeks out, and apply to already-shipped units.* **Engineering half done
   2026-08-09** (see the dated entry above): `security@joralllc.com` is documented
   in both manuals, the on-device Help, the customer PDFs and each tree's
   `SECURITY.md`. What is left sits with Carl: **create the
   `security@joralllc.com` Workspace group** (product management + at least one
   engineer; alias `psirt@` to it), and publish the policy on joralllc.com
   (`/.well-known/security.txt`). The signed-firmware-update decision (4b) also
   sits with Carl — raise both together. The docs must not ship to customers
   before the mailbox is live.
2. ~~**Attack surface (4a)**~~ — **done 2026-08-08 and 2026-08-10.** telnetd, adbd
   and Samba are out of the image and root SSH login is key-only (08-08);
   `S40bluetoothd`, `S30dbus`, `S99hciinit`, the `S99python` root-execution boot
   hook and 118 unused packages are out (08-10). The root password itself is
   *unchanged* — still `luckfox` from `BR2_TARGET_GENERIC_ROOT_PASSWD` — but it is
   no longer reachable over the network. **The firewall gap closed 2026-08-12
   and is bench-confirmed on a flashed unit** (default-deny IPv4 + IPv6
   rulesets in the board overlay; rules loaded, blocked-port probe refused,
   services verified through the filter — see the dated entry above), and the
   `wifi_app` binaries are dropped from the build and confirmed absent from
   the flashed image the same day (5e). What is left on this row: the uid-1000
   image ownership problem, root CGIs, and the root password *value*
   (unreachable but unchanged).
3. **Secure defaults (row #1)** — **closed on both products** *(text reconciled
   2026-08-12 — this item had gone stale against action-plan items 4g/4h)*:
   SatiSense ships `signencrypt` + `web.tls: true` (2026-08-08), the
   media-gateway console runs HTTPS on 443 with a per-unit certificate
   (2026-08-09, 4h), and the `admin`/`joral` credential buys only a forced
   password change on both products (2026-08-09, 4g). Residual, not blocking:
   first-use trust rests on self-signed fingerprints (documented out-of-band
   check), and disabling anonymous OPC UA sessions is an unlocked product
   decision.
4. ~~**OpenSSL 1.1.1 migration (4f)**~~ — **done 2026-08-12, build-verified and
   bench-confirmed** (see the dated entry above and
   [`openssl-3-migration-plan.md`](openssl-3-migration-plan.md)): 3.5.7 LTS +
   open62541 1.3.15, image rebuilt clean, all verification checks pass, SBOM
   shows "supported branch", CVE gate 19 → 6 blocking with libopenssl clean,
   and the migrated TLS surfaces (default console HTTPS, OPC UA Sign&Encrypt)
   confirmed on flashed hardware. MQTT TLS remains with item 8, as before.
5. ~~**CVE check as a release gate (row #2)**~~ — **process done 2026-08-09**,
   `./build.sh cve` (see the dated entry above). What the first run leaves open, in
   priority order:
   a. ~~**Trim the BSP defconfig**~~ — **done 2026-08-10**, see the dated entry
      above. 118 packages removed, image rebuilt clean, **100 blocking → 19**,
      zero CISA-KEV. avahi kept as intended (expat only, not glib or python).
      **Bench pass done 2026-08-12** — boot, console HTTPS on both products,
      OPC UA Sign&Encrypt, mDNS, CAN and the bench scripts all confirmed on
      hardware.
   b. ~~**Triage what remains**~~ — **done 2026-08-12, the gate PASSES (0
      blocking)**, see the dated entry above. Both quick wins predicted here
      survived the source check (minizip not built; zlib 1.2.13 vs the
      ≤ 1.2.0.3 the curl finding needs); busybox and the second wget finding
      fell to version/build facts; wget CVE-2024-38428 is the one *expiring*
      accepted-risk (drop GNU wget at the next respin); dhcpcd is
      `fixed-pending-release` via `ipv4only`. 20 triage rows total, first
      expiries 2026-11.
   c. ~~**Close the coverage gap**~~ — **done 2026-08-12**: all 19 remaining
      unmapped components resolved against the NVD CPE dictionary (one real
      CPE — GNU nano — and 18 documented `CPE=NONE` rows). 0 components are
      now unmapped; the report's NOT CHECKED section is empty.
   e. ~~**Declare or drop the prebuilt `wifi_app` binaries**~~ — **dropped
      2026-08-12** (`RK_ENABLE_WIFI=n`, see the dated entry above): they were
      never product function — the build config still carried the BSP's
      placeholder Wi-Fi credentials. Stale copies cleared from every build
      output; absence from the packed rootfs must be re-verified after the
      next rebuild.
   d. **Kernel/U-Boot currency** — report-only today (5098 and 41 findings). The
      remediation is a vendor-base move, so it needs scoping against Rockchip's
      releases rather than triage.
6. **Audit-log off-device forwarding** — the one item left on Annex I #6; designed
   in `audit-log-forwarding-plan.md`, deferred pending a product decision (action
   plan item 5).
7. **Media-gateway loose ends from the matrix work** — no LICENSE file / SPDX
   headers (needs an outbound-license decision; our own components show as
   UNDECLARED in the SBOM), and no test coverage of the auth layer, CGIs, config
   writer or listeners.
8. **Hardware bench session** — **partially done 2026-08-12** (see the dated
   entry above): the trimmed image boots and console HTTPS, OPC UA Sign&Encrypt,
   mDNS, CAN and the bench scripts are confirmed on hardware, so nothing
   depended on the 118 removed packages. **A repacked image carrying the
   firewall, `ipv4only` and wifi_app removal was flashed and bench-confirmed
   2026-08-12** (see the dated entry above): both rulesets loaded,
   blocked-port probe refused, OPC UA Sign&Encrypt from UaExpert / console
   HTTPS / CAN / SSH all through the filter, DHCP lease under `ipv4only`,
   wifi binaries absent. **Also confirmed on that flash:** loopback-only
   backend binds via `netstat -ltn` (127.0.0.1:18080 and :18081, no wildcard
   line — the isolating check the firewalled `:18081` probe could not give),
   factory reset on both products, the audit-log viewer, and the SatiSense
   durable audit trail with `src=unknown-via-tls` attribution (full session
   captured incl. `default_password=true` on first login — see the
   attribution entry above), and the **secrets-CGI path** (sidecar 0600,
   secret-free `gateway.json`, sentinel-only over the API). **Still open:**
   TC-S3 leg c (MQTT TLS, never run — deferred by decision for now), the
   media-gateway durable-audit spot-check, and a failed-login record
   correlated against stunnel's peer line in syslog. With those three, the
   bench backlog that accumulated since 2026-08-05 is cleared.
9. **Secrets at rest** — restricted (0600 sidecar) but not encrypted; accepted
   for now. The named revisit trigger — the OpenSSL 3 migration — fired
   2026-08-12, so an encrypted sidecar is now implementable; pending a product
   decision.

## Default network exposure (Annex II facts, current truth)

*Superseded by the per-product fact sheets (`docs/compliance/cra-annex2-facts.md`
in each tree, 2026-08-06), which are verified against the listening code. Kept
here as the cross-product summary.*

- Platform (both, from shared rootfs), **updated 2026-08-10**: :22 sshd (**key-only**,
  `PermitRootLogin prohibit-password`), serial getty. **Removed from the image:** :23
  telnetd, :139/:445 Samba, adbd (which also listened on **:5555 on all interfaces**,
  not only over USB as stated previously), and the stray buildroot stunnel running the
  upstream sample config (all 2026-08-08); plus `S40bluetoothd`, `S30dbus`,
  `S99hciinit` and the `S99python` root-execution boot hook (2026-08-10).
  **Dropped from the build 2026-08-12, confirmed absent on the flashed image**:
  the prebuilt `wifi_app` binaries — `hostapd`, `dnsmasq`, `wpa_supplicant` ×3,
  `wpa_cli` ×2, `iperf`, `rkwifi_server` — no longer install (`RK_ENABLE_WIFI=n`);
  they sat in `/usr/bin` unstarted and invisible to the SBOM and the gate. The
  root password remains `luckfox` (`BR2_TARGET_GENERIC_ROOT_PASSWD`) but is no
  longer reachable over the network.
  **Firewall (2026-08-12, bench-confirmed on a flashed unit):**
  `/etc/iptables.conf` and `/etc/ip6tables.conf` ship default-deny INPUT
  rulesets (documented service ports only on IPv4; nothing served over IPv6,
  RAs dropped, `dhcpcd` runs `ipv4only`), loaded by an overridden `S35iptables`
  that restores both families and logs a failed restore to syslog. Verified on
  hardware: rules listed, blocked port refused, services reachable, DHCP lease
  acquired. **Units flashed before 2026-08-12 still run unfiltered.**
- Media Gateway, **updated 2026-08-12** *(the ":80 HTTP-only, no TLS option" wording here had gone stale against 4h)*: **:443** web console (HTTPS by default via stunnel since 2026-08-09, per-unit cert, plain-HTTP fallback on the same port; backend on 127.0.0.1:18081 only), **:8001** CAN↔Ethernet UDP-or-TCP (unauthenticated), br0 L2 bridge (T1S↔100BASE-TX) so both are reachable from either medium.
  **Correction (2026-08-06): :8000 is NOT bound.** `can_gw_comm_port` defaults to 8000 but the socket binds `comm_port + 1` only (`src/can_gateway/can_gw.c:519`, `include/media_gateway.h:126-127`). The audit row above and `docs/manual/quick-start.md:83` both overstated the exposure.
- SatiSense Edge, **updated 2026-08-08**: :8080 web console (**https by default** via
  stunnel, per-unit self-signed cert minted on first boot), :4840 OPC UA
  (**`signencrypt` by default**, per-unit server cert minted on first boot; anonymous
  sessions are still permitted — disabling that needs a credential to exist first);
  outbound only: Modbus TCP :502, EtherNet/IP scanner, MQTT :1883/:8883, LLM HTTPS.
  **Both defaults degrade rather than fail** (a failed keygen leaves OPC UA on
  SecurityPolicy None; a failed stunnel start leaves the console on plain HTTP), so
  the console reports the mode the server **negotiated** rather than the one
  configured, in red with the reason, and publishes both certificate fingerprints —
  an operator can no longer be shown "encrypted" by a unit that is not
  (satisense-edge #44/#46). First-use trust is the residual gap the self-signed
  defaults create: the certificates prove nothing about *which* unit answered until
  someone compares a fingerprint, so User Manual §2.1 documents that check
  out-of-band (serial console `--cert-fingerprint`, or commissioning over a direct
  link) for both the browser warning and an OPC UA client's trust prompt.

## Action plan (agreed priority order)

1. ~~**Compliance matrix per product**~~ — **done 2026-08-06**, `docs/compliance/cra-annex1-matrix.md` in each tree. Keep updating per release, in the same commit as any change that moves a row.
2. ~~**SBOM from the build**~~ — **done 2026-08-06**, `./build.sh sbom`. Regenerate per release and keep the output with the technical file.
3. ~~**Annex II fact sheet per product**~~ — **done 2026-08-06**, `docs/compliance/cra-annex2-facts.md` in each tree. Re-verify per release; a stale fact sheet is worse than none because it gets copied verbatim.
4. **Gap backlog with CRA dates as milestones**:
   a. ~~strip telnetd/adbd/Samba~~ — **done 2026-08-08**; root password left unchanged
      but made unreachable over SSH (key-only login). Firewall ruleset still empty.
      **Reopened in a second form 2026-08-09** by the CVE gate: the defconfig also
      inherits a media/desktop package set (mpv → ffmpeg, bluez/pulseaudio, pillow,
      sdl2, rsync, p7zip, iperf3, …) that neither product uses and that carries 73
      of the 100 blocking CVE findings — including the only CISA-KEV one. Same root
      cause as the daemons stripped on 2026-08-08, one layer down. **And 2026-08-10**:
      the built image still starts `S40bluetoothd` (root Bluetooth daemon) and
      `S99python`, which executes `/root/main.py` as root at every boot. Both go in
      the same pass. **All of this closed 2026-08-10** — 118 packages removed, the
      four init scripts gone, verified against the packed rootfs, gate at 19
      blocking. Firewall ruleset and the `wifi_app` prebuilt binaries remain;
   b. signed firmware update path — flag to Carl per the doc;
   c. ~~factory-reset function (both products)~~ — **done: SatiSense 2026-08-06, media-gateway 2026-08-07**;
   d. **security-event logging** — console layer and viewer **done 2026-08-07,
      met on both**; CAN-gateway peer identity covers the **TCP path only**, and
      UDP is the shipped default, so media-gateway row #6 is **partial** (found
      in review 2026-08-12, see the correction above); off-device export
      deferred, see item 5;
   e. encrypt-or-restrict secrets in `gateway.json` — **done (restrict) 2026-08-06**, see above;
   f. OpenSSL 1.1.1 migration plan — now also the largest single block of CVE
      findings in a component we actually use (13 at CVSS ≥ 7.0 as of 2026-08-09),
      so the gate re-states the case for it on every run;
   g. ~~kill the shipped default console password (both products)~~ — **done
      2026-08-09**, satisense-edge #48 / t1s-media-gateway #24. `admin`/`joral`
      now buys a session that can do exactly one thing: change itself. Enforced
      in `require_auth`, so it covers every guarded endpoint and a new endpoint
      inherits it — not in the console JavaScript, which would stop nobody able
      to call the CGI directly. A factory reset returns the unit to the gated
      state. Verified on both products 2026-08-09, at both layers — the console
      forces the change on first login and again after a reset, **and** a signed-in
      factory session driven directly against the CGI (`curl` with the session
      cookie, bypassing the browser entirely) is refused with
      `403 {"code":"password_change_required"}` instead of being served the
      configuration. The second half is the one that matters for this row: it is
      the difference between a control and a screen, and it is the evidence to
      cite if an assessor asks how the requirement is enforced.
      **Unlocks** disabling anonymous OPC UA sessions, which the Annex II sheet
      records as waiting on "a credential to exist first" — that is no longer
      true, so it is now a product decision rather than a blocker.
   h. ~~console TLS on media-gateway~~ — **done 2026-08-09**, t1s-media-gateway #25.
      Ports the stunnel pattern satisense already runs: HTTPS on 443 with a
      per-unit certificate minted on first boot, falling back to plain HTTP on the
      same port rather than becoming unreachable. This closes row #1 on that
      product — the credential half (4g) was meaningless while the sign-in and the
      password change it forces still crossed the wire in the clear.
      Review caught three defects worth recording, because each is a pattern
      rather than a typo: (1) the fallback served plaintext while `tls_on()` still
      read the CONFIGURED intent, so cookies stayed marked Secure, browsers
      withheld them, and the fallback console became a sign-in loop — the same
      "report negotiated, not configured" failure as satisense #44; (2) the
      readiness probe accepted any listener on the port, so a squatter would have
      been mistaken for our own TLS terminator; (3) certificates were checked for
      existence rather than validity, so a truncated or mismatched pair pinned the
      console to plaintext on every boot. All three verified fixed on hardware.
      **Carry to satisense:** its init script has the same existence-only
      certificate check, and `certgen_pair_valid()` is now a divergence between the
      two vendored copies of `certgen.c`.
5. **Audit log export / forwarding** — the one item left on Annex I #6. Design options,
   requirements and a recommendation are written up in
   [`audit-log-forwarding-plan.md`](audit-log-forwarding-plan.md); **deferred pending a
   product decision on the delivery model** (push to syslog vs. let a collector pull).
   Headline: busybox already has `CONFIG_FEATURE_REMOTE_LOG=y`, so opt-in
   `syslogd -R` forwarding is a half-day change with no build impact — but a pull model
   fits the isolated-control-network assumption better and reuses the console endpoint
   that already exists.
6. **Disclosure channel** — **engineering half done 2026-08-09**: `security@joralllc.com` is referenced in both manuals, on-device Help, customer PDFs and each tree's `SECURITY.md`. Remaining (Carl): create the Workspace group and publish `/.well-known/security.txt` on joralllc.com.

Out of scope for engineering: CE marking, business classification, EU Declaration of
Conformity (product/legal level).
