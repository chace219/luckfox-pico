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

## Status at a glance (2026-08-18)

*The table above is the 2026-07-26 audit and stays frozen. This one is the
current position, and it is what to read first. "met" means a path in the tree
demonstrates it; "bench" means a flashed unit demonstrates it. Where the two
disagree, the bench column wins — every defect that mattered in this programme
was found by executing, not by reading. Per-product detail lives in each tree's
`docs/compliance/cra-annex1-matrix.md`; this is the cross-product roll-up.*

| Annex I | Media Gateway | SatiSense Edge | Bench | Residual |
|---|---|---|---|---|
| 1 Secure by default | **met** — HTTPS on 443 by default, per-unit cert, factory credential buys only a password change | **met** — `signencrypt` + `web.tls` by default, same credential gate | ✅ 08-09/08-12 | first-use trust is a self-signed fingerprint; **anonymous OPC UA closed 2026-08-19** — factory `allow_anonymous: false`, no shipped OPC UA credential, not yet on a unit |
| 2 No known CVEs at shipment | **met at the gate** — `./build.sh cve` **0 blocking**, OpenSSL 3.5.7 LTS | same (shared rootfs) | ✅ 08-12 | kernel (5155) + U-Boot (41) are report-only. the GNU wget accepted-risk was **resolved 08-16 by dropping the package**, leaving **python3 ×5** as the only accepted-risk. **dhcpcd was reclassified `not-affected` 2026-08-19** — it had been mis-filed `fixed-pending-release` for a mitigation that was ours and had already shipped, so it would have expired 2026-11-12 into a blocking finding for an unreachable code path; the config it rests on is now guarded by a test. **python3 removal was staged the same day and then reversed** — the interpreter is **kept** and the fix is a version bump, 3.11.6 → **3.11.16** (12 Aug 2026), carried as a tracked package replacement. **CVE-2020-29396 was reclassified `not-affected` 2026-08-19** — it is an Odoo sandbox escape with python listed only as the running-with platform, so it was never a CPython defect and no bump could ever have retired it. **BUILT AND GATED 2026-08-19**: the image carries 3.11.16 (read out of `rootfs.img`), `./build.sh cve` **0 blocking**. The bump retired **two** of the four — CVE-2024-6232 and CVE-2024-7592 now match nothing and their triage rows were deleted — and did **not** retire **CVE-2026-15308 and CVE-2026-4519**, which still match 3.11.16 and remain accepted-risk on the unchanged reachability argument. So: python3 ×2, not ×0 |
| 3 Confidentiality / integrity | **met** for the console path | **met** — secrets in a 0600 sidecar, **encrypted at rest and bound to the board since 08-16**, never served to the browser; MQTT TLS verification proven enforced | ✅ 08-12/13, ⚠️ sealing not yet on a unit | the sealing protects the stored file, **not** a running unit against root (no secure element); MQTT mutual TLS unexercised; **`/oem` still carries build-user ownership on every fielded unit and no update can fix it — only a reflash** (item 14). Nothing loads from it any more: the daemon since 2026.08.5 (`ldd`-confirmed on a unit), interactive root shells since 2026.08.6 (`RkEnv.sh` removed) |
| 4 Minimise attack surface | **met** — BSP daemons and 118 packages gone, default-deny IPv4+IPv6 firewall, `wifi_app` dropped, image inodes root-owned | same (shared rootfs) | ✅ 08-12/08-16 | httpd + CGIs run as root; root password is off the **published** vendor default since 08-16 (`$6$`, undocumented to customers) but is still one short shared value — unreachable over the network, serial-console login unverified |
| 5 Access control | **met** for the console | **met** for the console and, since 2026-08-19, the OPC UA endpoint | ✅ 08-09, OPC UA identity ⚠️ not on a unit | CAN :8001 unauthenticated by protocol design |
| 6 Security-event logging | **met** — console trail complete, and CAN peer identity is recorded on **both** transports since the 08-18 recovery (`50ec9b9`) | **met** | ✅ 08-12 (IE) | the UDP peer record has not been exercised on a unit (`logread` for `can_udp_peer_seen` after sending from two hosts); no off-device forwarding on either |
| 7 Update mechanism | **met** — signed A/B SWUpdate, ordered releases, downgrade gate | same | ⚠️ partial | DEV signing key only; downgrade **refusal** never run on hardware. Partition layout **frozen 2026-08-19** (gated by `./build.sh partitions`) |
| 8 Factory reset | **met** | **met** | ✅ 08-12 | — |

| Annex I Part II | Status |
|---|---|
| §1 SBOM per release | **met** — `./build.sh sbom`, Buildroot legal-info + hand-declared app layer |
| §2 Address vulnerabilities without delay | **met at the gate** — triage rows carry an owner and a `REVIEW_BY` date; first expiries 2026-11 |
| §3 Periodic security testing | **partial** — hardware bench is the loop that finds the real defects; **seven** legs outstanding (item 8 a–g) |
| §4–6 Coordinated disclosure | **partial — the only deadline-bound row, and nothing on it is engineering's.** Policy, address and the publishable `security.txt` + policy page are all done (08-09, 08-18, `disclosure/`); the **mailbox does not exist yet**, and until mail is received the row is not met |

**The one date that binds: 11 Sep 2026**, ~3.5 weeks out. Nothing on the
engineering list is required by it; the mailbox is — and as of 2026-08-18 the
files that go with it are written, validated and waiting in `disclosure/`, so
what remains is a Workspace group and a web upload, in that order.

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

  **Closed the same day (t1s-media-gateway #27).** `can_udp_peer_seen` records a
  source's **first** datagram with `peer=ip:port` and then stays quiet until that
  source has been silent for five minutes. The interesting part is what the
  design has to defend against, since the log is now reachable from the network:
  peers are keyed on **address only** (address+port would make an ephemeral-port
  sender a new peer on every datagram — the flood the record exists to avoid),
  and the record rate is bounded **independently of the table size**, because
  spraying novel source addresses is itself a log-eviction primitive. Past the
  budget, new peers are counted and reported once per window as
  `can_udp_peer_flood suppressed=N`, so a flood reads as a flood instead of
  silently pushing history out, and the budget refreshes so a flood cannot
  permanently mute a later genuine access. Attribution happens *before* decoding,
  so a sender whose datagrams do not parse — what probing the port looks like —
  is recorded too. 17 checks in `tests/test_udp_peers.c` (time injected, so the
  shipped logic is the tested logic), each confirmed to fail against the code
  mutated back to per-datagram logging, address+port keying and no rate limit.
  ~~**Row #6 is met on both products again — this time on both transports.**~~
  Bench-unverified: the daemon change needs a flash, and the check is a `logread`
  for `can_udp_peer_seen` after sending from two hosts.

  **Correction, 2026-08-16 — this never landed, and the entry above was wrong
  for four days.** The work exists as exactly one commit, 1a7bd8e
  (*feat(can): recorded who reaches the bus over UDP…*), pushed on 2026-08-12
  to the branch `docs/manual-audit-src-and-console-troubleshooting` — **after
  that branch's PR (#27) had already merged**. No later PR picked it up, so
  the commit sits on the branch and on `origin/`, and is **not an ancestor of
  `main`**: `grep -r udp_peer` over the checked-out product tree returns
  nothing, there is no `tests/test_udp_peers.c`, and no image ever built from
  `main` contains it. The gap the entry claimed to close is therefore **still
  open in shipped code**: on a factory-configured unit (`can_gw_proto=udp`)
  the write path equivalent to CAN bus access has no accountability at all.
  **Row #6 is met for SatiSense and PARTIAL for media-gateway.**

  The product's own Annex I matrix never repeated the error — it still
  records the UDP row as *"NOT recorded — open gap, found 2026-08-12"* with
  the interim `can_gw_proto=tcp` mitigation. The tree was right and this plan
  was wrong, which is the opposite of the usual direction and worth stating
  plainly: this entry was written from the commit, not from `main`.

  **And it happened twice on the same day, in both repositories.** Sweeping
  every branch in both trees for commits that are not ancestors of the release
  branch turned up a sibling: satisense-edge d4cfaa2
  (*docs(manual): documented the on-device firewall for operators*), pushed
  2026-08-12 at 08:07 — 30 seconds before the media-gateway one — to the
  identically-named branch, also after its PR had merged. So the **operator
  documentation for the firewall never reached the SatiSense user manual**,
  the on-device Help or the customer PDFs: `grep -i firewall docs/manual/`
  on `master` finds only an unrelated Modbus troubleshooting line. That is an
  Annex II accuracy item in its own right — the manual describes a network
  behaviour the product no longer has, and the commit specifically covers the
  two effects a customer sees from outside the box (IPv6 serves nothing, and
  "I cannot reach the unit" has a new cause). Nothing else in either tree is
  orphaned: every other branch tip that is not an ancestor is a bare merge
  commit with no content.

  *The process lesson, and it is a new one:* every earlier correction in this
  document came from a claim that was wrong about **behaviour**. These two were
  right about the behaviour of code and documentation that are not in the
  product. Merging is part of the evidence — a fix is only shipped once it is
  an ancestor of the branch the build takes, and that is a one-command check
  (`git merge-base --is-ancestor <commit> main`) which nothing in the release
  path currently runs. Recovering both is a small PR off each commit, not a
  reimplementation; the code, its 17 tests and the manual sections are intact
  on the branches. The generalisation worth keeping: **a claim in this plan
  cites a commit, and a commit is not evidence until it is an ancestor of the
  release branch.** Everything else in this document was written from what a
  tree does; these two were written from what a diff did.

- **2026-08-07 — both products, Annex I #6 hardened and made usable: console viewer,
  bigger history, no silent loss.** Three things came out of working out what the
  storage layout actually *is* rather than reading the code:
  - **`logger` alone was never going to be enough, confirmed.** `/var/log` is a symlink
    to `/tmp` (tmpfs), so the system log is RAM-only. The durable copy lives on
    `/userdata` = **eMMC `/dev/mmcblk0p8`, 512 MB ext4** (`p6`/256 MB when this
    was written — the A/B layout moved and doubled it; see the 2026-08-19
    freeze entry), mounted by
    `/etc/init.d/S20linkmount` (generated at pack time from `RK_PARTITION_FS_TYPE_CFG`)
    at S20 — before the product services at S39/S50/S60, so it is always available by
    the time anything logs.
  - **The 256 KB cap was a forensics weakness, not a storage choice.** Rotation
    *evicts* history, so a single 256 KB generation (~2900 records) let an attacker
    push their own earlier activity out of the log by generating failed logins — a
    size limit doubling as an evidence-destruction primitive. Now 1 MB × 4 generations
    (~45k records, **0.8% of the 512 MB partition** as it now stands, 1.6% of the
    256 MB one this was measured against — the old cap used 0.1%), aged out so
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
  CVE-2026-56116** was filed `fixed-pending-release`: `/etc/dhcpcd.conf` now sets
  `ipv4only`, so the vulnerable RA parser can never receive input. *(The decision
  was right and the label was wrong — reclassified `not-affected` 2026-08-19, see
  the dated entry below.)* The CPE
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

- **2026-08-12/13 — SatiSense Edge, Annex I #3 (transmitted data): TC-S3 leg c
  (MQTT TLS) is EXECUTED — the last never-run leg, open since ADR-127 on
  2026-07-04 — and it found a keepalive defect that had nothing to do with TLS.**
  Method and evidence in
  [`satisense-edge/docs/implementation-artifacts/mqtt-tls-bench-runbook.md`](../../media/joral/satisense-edge/docs/implementation-artifacts/mqtt-tls-bench-runbook.md)
  §6a/§6b.

  *Why it kept slipping, and what unblocked it.* The leg needed a TLS broker on
  the bench and never got one. `test.mosquitto.org` removed that dependency
  entirely: it serves a CA-signed endpoint (:8883), a **deliberately expired**
  certificate on :8887, and a Let's Encrypt endpoint on :8886 — so the positive
  case, the validity-failure case and the system-trust-store case are three port
  numbers rather than three certificates to mint. The far side of the session was
  watched by an **independent subscriber on the build host**, which matters
  because Diagnostics' `published` counter is the device's own account of itself;
  a message decoded off the wire is not.

  *What is proven on hardware.* TLS 1.3 with the broker certificate verified
  against a CA **uploaded through the console** (no shell), and real tag data
  arriving. Verification is enforced on **both** trust paths, each established by
  a pair rather than a single observation:
  - `:8887` (expired) **refused**, and the same endpoint **connected** with
    `tls_insecure: true` — the control that isolates the refusal to certificate
    validation instead of reachability.
  - with `ca_path` blank, `:8883` (mosquitto's self-signed CA, absent from the
    image's bundle) **refused** while `:8886` **connected** — proving the device's
    own `/etc/ssl/certs` is reachable *and* constraining. Neither run alone shows
    that: an empty store also refuses everything, and a bypassed check also
    accepts everything. This is also the first on-device evidence that the CA
    bundle works at all, which the LLM connector's libcurl HTTPS shares.

  *Still unexercised:* mutual TLS and credentials-inside-the-channel. Both need a
  broker whose authentication we control — `:8885` rejected its own documented
  `rw`/`readwrite` credentials during the session, and `:8884` needs a CSR signed
  through a web form. They move to the local-mosquitto session (runbook §2–§5).

  **The defect: MQTT sessions did not survive their own keepalive.**
  `connected_session()` scheduled PINGREQ from `last_tx`, but updated `last_tx`
  whenever a new model *snapshot* arrived rather than when bytes were actually
  sent — `publish_changed()` reported success identically whether it published
  fifty points or none. A steady process yields a fresh snapshot every
  `publish_interval_ms` in which nothing changed, so the deadline was never
  reached and **no PINGREQ was ever sent**. With shipped defaults
  (`publish_interval_ms` 1000 vs `keepalive_s` 60) the condition could never be
  satisfied. **Not a TLS defect** — the plaintext path had it too — and it bit
  *precisely when the gateway was healthy*, since static values are the normal
  steady state and universal while quality is BAD. Every subscriber watching
  `$status` saw the gateway flap offline once a minute.

  Worth recording is how it was isolated, because two of the three steps were
  cheap and decisive: payload `ts` climbing **continuously across the drops**
  ruled out a daemon restart in one observation; changing `keepalive_s` 60 → 30
  and seeing **no change in the period** ruled out our own keepalive; and probing
  the broker directly established that it caps *idle* sessions at
  `min(1.5×keepalive, 60)` while a client that pings survives indefinitely —
  which located the fault at "the device is silent", not "the broker is strict".

  Fixed (`publish_changed()` returns the count sent; only a non-zero count resets
  `last_tx`) and guarded by `tests/test_mqtt_keepalive.c`, which stands a minimal
  MQTT broker on loopback and runs the **real** worker against an unchanging
  model — the bug is in *when* state is updated across two cooperating functions,
  which no pure-function test could catch. Confirmed to fail against the pre-fix
  code and pass after; **bench-confirmed by a 185s session with zero drops** where
  the previous build dropped three times in the same window.

  *The review lesson:* `tests/test_mqtt.c` already asserted that
  `mqtt_enc_pingreq()` **encodes** two correct bytes. It never asserted that the
  loop **calls** it. The encoder was verified and the scheduling was not — the
  same shape as the CAN audit gap that covered TCP while UDP was the shipped
  default.

  *Two further findings from the same session, both filed rather than fixed:*
  - **The SatiSense daemon writes no log anywhere.** `S60intelligence-edge`
    starts it with `start-stop-daemon -b`, and busybox 1.36.1 implements `-b` as
    `bb_daemon_helper(DAEMON_DEVNULL_STDIO …)` (`start_stop_daemon.c:527`), so the
    daemon's stdio goes to `/dev/null` — the shell's `>> "$LOG" 2>&1` only ever
    applied to `start-stop-daemon` itself, which `-q` silences. `main.c`'s 22
    `fprintf(stderr, …)` calls are discarded, the daemon uses no syslog, and
    `/var/log/intelligence-edge.log` is **0 bytes on a running unit** — while
    `user-manual.md:1047` tells operators it contains "config load, connections,
    rule engine, MQTT, AI". An MQTT failure reason exists **only** in the
    console's Diagnostics field, which a restart clears. This is the 2026-08-11
    nginx lesson ("a service that can fail at boot must be built so its first
    failure is legible from the boot log") never applied to this init script, and
    it is why this whole session had to be diagnosed from the broker side.
    **Check media-gateway for the same pattern.** It weakens the *legibility*
    half of Annex I #3 in the documented channel — the refusal is correct and
    reported, but not where the manual says to look.
  - **`dhcpcd` is running DHCP against `can0`**, logging `if_setmtu: Device or
    resource busy` plus privilege-separation errors on a loop. `can0` is AF_CAN
    and has no business in a DHCP client; `denyinterfaces can0` in
    `/etc/dhcpcd.conf` (beside the `ipv4only` the firewall work added) settles it.
    Cosmetic, except that a log full of errors that are not real makes a genuine
    fault harder to see — the same theme as the item above.

  *Also confirmed incidentally, closing half of an open bench item:* stunnel's
  peer line is present in syslog on a running unit
  (`Service [web] accepted connection from ::ffff:172.32.0.100:54724`,
  `daemon.notice`) — the correlation source the `src=unknown-via-tls` audit
  design depends on. Correlating an actual audit record against it is still owed.

  *Hygiene:* the bench pointed a unit at a **public** broker, so the run used an
  unguessable topic prefix; the three retained topics were cleared afterwards
  (verified clean) and the unit was factory-reset. The staged factory config
  restores `mqtt.enabled: false` with an empty host, so a reset cannot leave a
  unit talking to a public broker.

- **2026-08-15 — both products, Annex I #7 / Annex II §2: the update mechanism
  can tell an upgrade from a rollback. One-way door #4 is closed.**

  The A/B updater shipped and bench-passed on 2026-08-14 with one hole left
  open in its own plan: `build_swu()` took the release identity from
  `git describe` on an untagged tree, which yields a bare commit hash. **A hash
  has no order**, so nothing on the device could compare a package against what
  it was running, and the downgrade policy the `sw-description` comment
  advertised was never implemented. The consequence is specific and it is not
  theoretical: **a properly signed older release — one a published advisory
  already covers — installed over a fixed one in complete silence.** No
  signature check can catch that, because CMS attests *who* built an image and
  never *when*, so this is not a gap the signing ceremony would have closed.

  Releases now carry `YYYY.MM.PATCH` (`media/joral/RELEASE_VERSION`, currently
  `2026.08.1`). Date-ordered rather than semantic, because one `.swu` carries a
  rootfs shared by both products — there is no single API whose compatibility a
  major number could describe — while what the field actually has to support is
  *order*, and a date gives that without a release database while staying
  readable as an age to whoever is holding the unit.

  Four things are worth recording, none of them visible from the plan line
  ("decide a monotonic version scheme"):

  - **The manifest version is read back OUT of the packed rootfs**
    (`debugfs -R "cat /etc/sw-versions"`), never asserted from
    `RELEASE_VERSION` a second time. A unit believes the rootfs it boots, so a
    version declared *beside* the payload can disagree with it — and that
    disagreement is invisible until an operator installs, when it shows up as
    a downgrade prompt for an upgrade or as silence for a genuine rollback.
    This was not hypothetical: the first revision of the change had a
    "helpful" fallback to the staging tree, and the first real run of it
    **packed a manifest claiming 2026.08.1 over a rootfs carrying no version
    at all**. The fallback is gone; the build now refuses an image with no
    identity, one whose identity is unorderable, and one where the staging
    tree names a different release than the packed image.
  - **The gate is warn-and-confirm in the console, not SWUpdate's
    `install-if-higher`.** A hard installer gate would make rollback
    *impossible*, and rolling back to a known-good release is a legitimate
    recovery action — one an operator may need precisely when the automatic
    A/B rollback has already been consumed. So it lives where the operator and
    the audit log are: anything not ordered `newer` or `same` needs the typed
    phrase `DOWNGRADE`, re-checked **server-side** so it also covers `curl`,
    and the attempt is audited either way with `from=`/`to=`/`order=`. State
    plainly what this buys: it does **not** stop an attacker holding console
    credentials, who can type the phrase. It converts a silent signed rollback
    into a warned, explicitly confirmed and recorded one — and the audit record
    is what lets an incident review answer "was this unit ever running an
    affected build", which the previous trail (`target=b`) could not.
  - **`unknown` is refused by default.** Every image built before this scheme
    reports no version, so the unorderable case is not an edge case — it is the
    state of the whole existing fleet-of-none. A gate that defaults open there
    is a gate that does nothing on exactly the units that have it.
  - **The comparison is numeric per field, never a string compare.**
    `2026.08.10` is newer than `2026.08.9`, and every lexicographic shortcut
    inverts it. That is not an exotic input: the tenth patch of a month is the
    release that has seen the most fixes, so the inverted gate would nag on
    routine upgrades and stay quiet on the rollback that mattered.

  One comparator serves all three callers — `./build.sh swu`, the console CGI
  and `make install` — so the build and the device cannot disagree about which
  release is newer. Pinned by `ab-boot/tests/test_swu_version.sh` (68 checks)
  and `ab-boot/tests/test_update_gate.sh` (47), the latter driving the **real
  CGI** through the gate against a scratch tree via a new `SWU_PREFIX` path
  root — the factory reset's `MG_RESET_PREFIX` idiom, so the shipped script is
  the tested script. It also fails when either product's instantiated copy of
  the CGI drifts from the template, which is the failure mode a hand-copied
  file invites: a stale copy is silently a console without the gate. Every
  behavioural check was confirmed to FAIL against the code mutated back to a
  lexicographic compare, a permissive `unknown`, a case-insensitive phrase, a
  gate applied to upgrades, and an audit line without the version transition.

  Verified end to end on this tree: `./build.sh media && ./build.sh firmware`
  stamps `/etc/sw-versions` into the packed rootfs, `./build.sh swu` reads
  `2026.08.1` back out of that image and signs a matching artifact, and both
  product suites stay green. Both user manuals gained a *Release numbers* and
  an *Installing an older release* section (markdown, on-device Help HTML and
  the customer PDFs regenerated), so the operator-facing description matches
  what the console does — the previous `sw-description` text claimed a
  confirmation that did not exist.

  **Bench 2026-08-15 — half confirmed.** A flashed unit reports
  `release 2026.08.1` in the SatiSense topbar and the Firmware update panel,
  read from `/etc/sw-versions` on the slot it booted, so Annex II §2's
  "identifying element readable on the device" now covers the *release*, not
  only the build hash. **The refusal has not run on hardware**: that session
  staged `2026.08.1` over a running `2026.08.1`, which orders `same` and is
  correctly offered without a prompt. Proving the gate needs a `.swu` built
  from an older `RELEASE_VERSION`, and the evidence to cite is the CGI driven
  directly with `curl` — a disabled button demonstrates a screen, not a
  control, which is the same distinction the default-password row rests on.

- **2026-08-15 — media-gateway, Annex I #5/#6 and Annex II §2: the console's
  auth layer, endpoints, write path and port facts now have tests. One defect
  found and fixed; three stale source citations corrected.**

  Remaining-work item 7 recorded "no test coverage of the auth layer, CGIs,
  config writer or listeners" on the product where `require_auth` is the
  enforcement point three Annex I rows now cite. The gate itself was covered
  (`test_force_password.sh`); nothing covered the machinery it is built from.
  Four suites, 200+ checks, all in `make test`:

  - `test_webauth.sh` — sessions, cookie parsing, credential storage, audit
    sanitisation.
  - `test_auth_endpoints.sh` — the four `auth-*.sh` endpoints EXECUTED, not
    grepped.
  - `test_config_writer.sh` — the one authenticated write path, round trip,
    validation, and what a refusal leaves on disk.
  - `test_listeners.sh` — the port facts, and whether the compliance documents
    still cite live lines.

  To execute the shipped CGIs rather than rewritten copies, all eight console
  endpoints gained `MG_CGI_PREFIX` — the idiom `factory-reset.sh`
  (`MG_RESET_PREFIX`) and `api-update.sh` (`SWU_PREFIX`) already use, empty on
  a device. The shipped script is the tested script.

  Four things worth recording:

  - **A defect the tests found in `config.sh`, now fixed.** A non-numeric value
    in any numeric field passed validation and was written to disk, because
    `[ abc -lt 1024 ]` is an ERROR rather than a false — so both halves of the
    range test failed open. For `can_gw_comm_port` the consequence was not a
    bad setting: the NEXT GET aborted at `$((CAN_COMM + 1))` (the shell treats
    arithmetic on a non-numeric string as fatal), so the configuration endpoint
    answered with headers and an **empty body, permanently, across reboots**.
    The ways back were SSH or a factory reset. Reachable by any signed-in
    operator with `curl`, so it is a self-inflicted denial of the management
    interface rather than a privilege boundary — but it is exactly the kind of
    thing a UI-only validator hides, since the console never sends such a
    value. Fixed on both sides: the writer refuses non-numeric fields with a
    named error, and the reader falls back to the documented default so a unit
    already in that state still renders and can be repaired **from the
    console** instead of over SSH.
  - **Three stale source citations in the Annex II fact sheet**, repeated in the
    Annex I matrix and in this plan: `src/main.c:125`,
    `include/media_gateway.h:126-127` and `src/can_gateway/can_gw.c:519` had all
    slid with the code (now 137, 224-225 and 563). They were accurate when
    written on 2026-08-06/07. The claim they support — that **:8000 is never
    bound** — is still true, and the correction is load-bearing because the
    original audit row and the quick-start table both overstated it. A citation
    that has slid to unrelated code is worse than none, because it still looks
    like evidence to whoever follows it. `test_listeners.sh` now finds where the
    code actually is and requires the documents to name that line, so it needs
    no hardcoded line numbers of its own and cannot go stale the same way —
    confirmed by re-introducing the old citation and watching it fail.
  - **Every suite was mutation-checked.** 47 mutations of the shipped code —
    dropping the session token's charset guard, un-anchoring the cookie match,
    fixing the salt, storing the plaintext, issuing a cookie on a FAILED login,
    removing `require_auth`, reverting the numeric repair, re-introducing the
    `web_port=80` regression — each had to make its suite fail. Two did not, at
    first, and both were tests that passed for the wrong reason: the traversal
    tokens pointed at paths that did not exist at the depth `$SESSDIR`
    resolves to, and the factory-password refusal was really the
    minimum-length rule firing, since `joral` is five characters. Both were
    rewritten until the mutation was caught. A suite that has never been seen
    to fail is a suite nobody has checked.
  - **What `test_listeners.sh` is NOT.** It is a contract test over the source
    and the compliance documents, not a runtime bind test — `open_udp()`,
    `open_tcp()` and `config_load()` are static, and linking `main.c` natively
    would drag in OpenSSL and the CAN headers. What a running unit actually has
    open is still bench evidence (`netstat -ltn`, 2026-08-12). The suite's job
    is to stop the code and the documents diverging *between* bench sessions.

  **Carry to satisense-edge — done the same day** (satisense-edge #56): its
  `web/cgi-lib/webauth.sh` is a separate vendored copy (175 lines differ, in
  paths, the cookie name and the audit tag) exposing the same primitives, and
  the survey found the same guards all **present** — the charset checks and the
  anchored cookie match. Nothing was missing there; the coverage was. It now
  carries `test_webauth.sh` and `test_auth_endpoints.sh` (~140 checks, in
  `make test`, 18 suites green) and `IE_CGI_PREFIX` across its fifteen console
  endpoints, so the shipped CGIs are the ones executed.

  Verified against that tree's own code rather than assumed from the port: 19
  mutations, each required to make its suite fail. The port itself produced the
  defect worth recording — the symlink standing in for the installed library
  was rewritten to the new path while the `mkdir` above it was not, so the
  endpoint suite briefly ran against CGIs that could not source the library at
  all. It reported failures rather than passing vacuously, but only because the
  assertions say what each endpoint must return rather than merely that it
  answered.

  Not carried across, deliberately: the config-writer and listener suites.
  satisense's configuration is JSON validated in C (`config_validate.c`,
  `test_config_validate.c`) rather than an INI file interpolated through shell,
  so the defect above has no analogue there — and its one arithmetic site
  (`api-update.sh:193-194`, on `CONTENT_LENGTH`) already carries exactly the
  `case … *[!0-9]*` guard that media-gateway's `config.sh` was missing. That
  idiom is the house style; the gap was older code that predated it.

- **2026-08-15 — platform (both products), Annex I #3/#5: the image no longer
  ships with every inode owned by the build user. `StrictModes no` is gone.**

  Recorded as a known caveat on 2026-08-08 and planned in
  [`image-ownership-and-ssh-key-plan.md`](image-ownership-and-ssh-key-plan.md):
  `mkfs.ext4 -d` copies the staging tree preserving build-host ownership, and
  the build runs unprivileged, so **every inode in the packed image was uid
  1000** — `/`, `/etc`, `/etc/shadow`, `/etc/ssh`, every init script, both
  product binaries and the OPC UA private key. Measured on the shipped
  `rootfs.img` before the fix: `/` was 0:0 (mkfs creates it) and all 2551
  copied entries were 1000:1000.

  Two consequences, the second much larger than the first: `sshd` had to ship
  `StrictModes no`, a weakened setting we would have had to explain in the
  technical file; and it was a latent privilege escalation — a service account
  added with an automatic UID lands at 1000 and would then own the entire root
  filesystem. Inert only because no such account exists, and CRA hardening
  pushes directly toward creating one by unprivileging daemons.

  **The planned fix was wrong, and how it fails is the point.** The plan
  proposed wrapping `chown -R 0:0` and `mkfs.ext4` in one `fakeroot` session.
  `mkfs_ext4.sh` puts its own directory on `PATH`, and the `mkfs.ext4` there is
  **statically linked** — `fakeroot` works by `LD_PRELOAD`, which a static
  binary never consults. Measured both ways on the real staging tree: SDK
  binary under fakeroot → uid 1000; host's dynamic binary under fakeroot →
  uid 0. So the planned change would have run, passed its own
  `command -v fakeroot` check, printed no warning, and shipped **the identical
  defect** — while the plan and the `sshd_config` comment both said it was
  fixed. The check it proposed ("is fakeroot installed?") is not the question
  that matters.

  Switching to the host's `mkfs.ext4` was rejected as the remedy: this script
  pins the SDK's e2fsprogs to control the on-disk feature set (hence the
  explicit `-O ^64bit,^huge_file`), and a newer host `mke2fs` enables features
  the target kernel may refuse to mount. Trading a silent ownership bug for a
  possible silent mount bug is not an improvement.

  **What shipped instead:** the ownership is corrected in the *packed image*
  with `debugfs` — already a required build tool, since `build.sh` reads the
  release identity back out of the rootfs the same way. The path list is
  generated from the tree just packed, so it cannot drift from the image's
  contents. Three properties matter, and the first is the lesson:

  - **It verifies the image, not the tooling.** Every inode is `stat`ed back
    out of the image afterwards and the build FAILS if any is non-root. A build
    that merely ran the right command proves nothing — that is precisely how
    the fakeroot approach would have passed.
  - **It fails loudly in both directions.** No `debugfs` → hard error naming
    the consequence. Ownership that did not land → hard error with the count.
    `MKFS_EXT4_KEEP_BUILD_OWNERSHIP=1` is the documented deliberate opt-out.
  - **It loses no intent.** The staging tree is uniformly 1000:1000 (2551 of
    2551), because an unprivileged build cannot express any other ownership.

  Verified on the build host by running the real script against the real
  assembled tree: 2552 inodes set, `/`, `/etc/shadow`, `/etc/ssh/authorized_keys`,
  the init scripts and both product binaries all uid 0 / gid 0, image
  `e2fsck -fn` clean, ~1.1 s added. Both failure paths were exercised
  deliberately — a stub `debugfs` that accepts the write and does nothing (the
  fakeroot failure mode exactly) makes the build refuse the image rather than
  ship it, and a `PATH` without `debugfs` fails with the reason and the opt-out.

  One defect found in the fix while testing it, worth recording because it is
  the same shape as the `config.sh` one earlier the same day: `grep -c` exits 1
  when the count is zero — the success case — which tripped the script's `ERR`
  trap and aborted the build *after* the ownership pass but *before*
  `resize2fs`, silently emitting an unshrunk image. Caught only because the run
  was checked end to end rather than by its ownership output.

  `StrictModes no` is removed from `sshd_config`, with the comment rewritten to
  say that a future "Server refused our key" means the packing regressed and
  should be diagnosed with `debugfs`, not hidden by re-disabling the check.
  **CONFIRMED ON HARDWARE 2026-08-16 — the real acceptance test passed.** A
  unit updated to 2026.08.2 through the A/B updater (not reflashed, so the
  change travelled the way a customer's would) reports uid 0 / gid 0 on `/`,
  `/etc` and `/etc/ssh`, and accepts a fresh key-authenticated SSH session with
  `StrictModes` at its default. Ownership was indeed the only missing half; the
  modes on the key path were already 0755/0644.

  Two things about this one are worth keeping, because both would have shipped
  a defect that looked fixed. The `fakeroot` approach the plan proposed does
  nothing against a statically linked `mkfs.ext4` — it would have passed its own
  `command -v fakeroot` check silently. And the first real build after the fix
  packed the defect anyway, exit 0, because the build runs a COPY of the
  tracked tool that only `pctools` refreshes; `build_firmware` now warns when
  the file that will execute is not the file in git. In both cases the failure
  mode was a check that could not fail rather than a check that failed.

  Still owed by this change: a build-and-boot pass on the other board configs,
  since `mkfs_ext4.sh` is shared SDK tooling that packs rootfs, oem and
  userdata for every board (measured this build: 2552 + 217 + 1 inodes).


- **2026-08-16 — documentation reconciliation: the compliance artifacts were
  re-read against the code rather than against each other, and three of them
  had gone stale in the direction that flatters the product.** The Annex I
  matrices were re-verified on 2026-08-15 and were accurate; the **Annex II
  fact sheets were not fully carried with them**, and a fact sheet is the
  document that gets copied verbatim into the technical file.
  - **media-gateway `cra-annex2-facts.md` contradicted itself.** §3 (ports)
    had been corrected on 2026-08-15 to say the console is **HTTPS on 443 by
    default**, while §4 still listed *"Console TLS — not available at all,
    `tls_on()` is hard-coded false"* and *"Session cookie `Secure` — never set
    (no TLS to set it for)"*, and §7 told the customer the console is
    *"HTTP-only and cannot be encrypted"* and called that *"the largest
    remaining gap for this product"*. All three have been untrue since
    2026-08-09 (PR #25). §7 also still said *"no packet filtering ships"*,
    untrue since 2026-08-12. The §4 logging row still quoted the **256 KB**
    cap raised on 2026-08-07 and claimed the CAN data path is unlogged
    *"(peer address discarded on accept)"* — wrong for TCP, where
    `can_client_*` carries `peer=ip:port`, and right for UDP for a different
    reason (see the correction above). Corrected against the code.
  - **satisense-edge `cra-annex2-facts.md`** still carried `sshd runs with
    StrictModes no` as a caveat *"that must be stated accurately in the
    technical file"*, with the uid-1000 explanation and *"a fix is planned"*.
    Fixed 2026-08-15 and hardware-confirmed 2026-08-16. Corrected, keeping the
    honest half: units flashed from an image built before 2026-08-15 still
    carry build-user ownership.
  - **satisense-edge `cra-annex1-matrix.md`** §4's *to close* line listed the
    uid-1000 problem as outstanding. Now root CGIs and the root password value
    only.

  *Worth recording, because it is the same shape as the CVE work:* a stale
  document is not a documentation problem, it is an **evidence** problem — a
  fact sheet that understates a control will be believed exactly as readily as
  one that overstates it, and here the same file did both at once in different
  sections. The per-release re-verification has to cover the fact sheets and
  the matrices in one pass, not the matrices alone.

- **2026-08-16 — the diagnosability items filed from the 2026-08-12/13 MQTT
  bench session are fixed in the tree (build-verified, not yet flashed), and
  the wget respin promise is kept.**

  *SatiSense daemon log (remaining-work item 12, first bullet).* The daemon
  now routes its own stdio to `/var/log/intelligence-edge.log`
  (`core/logfile.c`, called at the top of daemon mode only — every CLI mode
  keeps its stderr on the caller's terminal). The init script never could:
  busybox `start-stop-daemon -b` reopens the child's stdio on `/dev/null`,
  so the script's `>> $LOG` only ever redirected `start-stop-daemon`'s own
  silenced output — the same reason the ENIP scanner already wrote its own
  file (`ENIP_LOG_FILE`), which is the pattern followed. Three design points
  worth keeping:
  - **`dup2`, not `freopen`** — a failed `freopen` *closes* the stream, so
    the failure mode of the fix would have been the defect, permanently; a
    failed `open` here leaves stdio exactly as it was. Best-effort by the
    same contract as `audit_log`: a log that cannot open must not cost the
    gateway.
  - **Capped, because `/var/log` is tmpfs** — an unbounded reconnect loop is
    RAM exhaustion in slow motion on a 256 MB device. 1 MB with one `.old`
    generation; the runtime cap is copy-then-truncate from a watchdog thread
    so the live `O_APPEND` writers are never touched (no cross-thread stdio
    surgery).
  - **The mutation the suite missed first.** `tests/test_logfile.c` (in
    `make test`) was mutation-checked five ways; four failed as required,
    but dropping `O_APPEND` **survived** — nothing asserted that a restart
    appends rather than clobbers, and the boot after a crash is exactly the
    log that matters. The test now seeds the file as a previous run and
    requires the seed to survive. Same lesson as the config-page suite on
    2026-08-15: a test that has never been seen to fail is a test nobody
    has checked.

  One cross-build finding: uclibc does not declare `truncate()` under
  `_POSIX_C_SOURCE 200809L` (implicit declaration on the RV1106 build — a
  real hazard on a 32-bit target), so the cap uses `ftruncate` on an
  explicit fd. Full satisense suite green including the new checks; the
  cross build links clean and warning-free. The manual's §13 claim about
  this file is now true and documents the rotation (markdown + Help HTML +
  PDFs regenerated); `docs/project-context.md` no longer claims the init
  script captures the log. **media-gateway checked for the same pattern:
  not affected** — its daemon has used `syslog(LOG_DAEMON, …)` throughout;
  its only stderr writes are CLI usage text.

  *dhcpcd vs can0 (item 12, second bullet).* `denyinterfaces can*` added to
  the board overlay `dhcpcd.conf` beside `ipv4only` — dhcpcd claims every
  interface by default, AF_CAN included. The glob also covers a second
  controller or a vcan test interface.

  *GNU wget dropped (the one expiring accepted-risk, CVE-2024-38428).*
  `BR2_PACKAGE_WGET` deselected in the tracked defconfig master **and** the
  live buildroot `.config` (the tracked-masters gotcha), and the stale GNU
  ELF + `/etc/wgetrc` purged from **both** staging trees (`output/target`
  and `output/out/rootfs_uclibc_rv1106`) with the busybox applet symlink
  restored in each, so a repack cannot resurrect the binary — the wifi_app
  lesson applied. Both wget triage rows are retired: the gate itself flagged
  them stale once the component left the list, which is the CSV working as
  designed. Offline gate re-run: **0 blocking, 45/45 compliance checks
  green.** Verification owed at the next packed image: `/usr/bin/wget` must
  be the busybox symlink, not an ELF.

  **Bench-confirmed the same day, on hardware, delivered the customer way.**
  Release bumped to `2026.08.3`, built (`media` → `firmware` → `swu`) and
  installed on the unit through the A/B updater; the audit trail carries the
  full transition (`fw_upload version=2026.08.3 running=2026.08.2
  order=newer` → `fw_apply … from=2026.08.2 to=2026.08.3 order=newer
  downgrade=false` → `ab_slot_marked_successful slot=b`), which is also the
  §9 evidence the bench runbook asks to be quoted. Observed on the unit:
  - `/var/log/intelligence-edge.log` is **745 bytes where it was always 0**,
    opening with the version line (`intelligence_edge_opcua: version
    8ba0e45-dirty`), the config summary and the OPC UA security-policy
    setup — a support bundle now names the build and says what the daemon
    did at boot.
  - `/usr/bin/wget` is the **busybox symlink** on the running rootfs and
    invoking it prints the BusyBox banner — the triage rows' owed check,
    closed on-device rather than only in the packed image.
  - **dhcpcd no longer touches the CAN bus.** `/var/log/messages` carries
    **zero** `can0` lines this boot — no `if_setmtu: Device or resource
    busy`, no privilege-separation loop — where the pre-fix unit logged them
    continuously. Confirmed by a *pair*, not by the silence alone, because an
    absent error is also what a dead daemon looks like: dhcpcd is
    demonstrably alive and working in the same log (`usb0: carrier
    acquired` → `soliciting a DHCP lease` → lease), and `ip link show can0`
    reports the interface still `UP` with `mtu 16`, i.e. denied to dhcpcd but
    untouched as a CAN device. The one-line-only startup complaint (`no
    valid interfaces found`, before any carrier exists) is the expected
    consequence of the deny rule, not a regression.
    *Method note for the runbook:* the check as first written used
    `logread`, which **this image does not ship** — the command failed and
    the `grep -c` in the pipeline reported `0`, which reads exactly like a
    pass. A check that cannot fail is not a check; the syslog file is the
    right target here.
  Incidental but worth keeping: the 2026-08-15 19:46 audit line already
  shows `fw_upload version=2026.08.1 running=2026.08.2 order=older` — the
  **upload half of bench leg 2 has therefore already executed and ordered
  correctly**; what remains for the downgrade refusal is only the `fw_apply`
  attempt without the typed phrase, one `curl` against the CGI.

- **2026-08-16 (second pass) — four product decisions were taken and
  implemented: the root password leaves the published vendor default, the
  secrets sidecar is encrypted at rest, and both products now declare an
  outbound licence. Build-verified; three of the four are bench-unverified.**

  *Root password (remaining-work item 2).* The image shipped `luckfox` — the
  value **Luckfox publishes in their own documentation**, so it was a secret on
  no unit that carried it. It is now a Joral-chosen value, deliberately absent
  from every customer-facing document (manuals, quick-start, on-device Help),
  and the guard `scripts/compliance/test-root-credential.sh` (8 checks on the
  tracked sources, 12 when handed a packed tree — it also guards the file's
  **mode** since 2026-08-19) keeps it that way. Three things came out of doing it that the plan line ("the root
  password value") did not anticipate:

  - **The defconfig was never the effective source.** The board overlay
    (`overlay-luckfox-buildroot-shadow/etc/shadow`) is rsynced over the rootfs
    *after* buildroot's target-finalize, so `BR2_TARGET_GENERIC_ROOT_PASSWD`
    only ever supplied a value that was then overwritten. Every prior document
    — this plan, both Annex II fact sheets, both matrices — cited the
    defconfig. The value they named was right; the mechanism was not, and a
    change made only there would have shipped nothing while reading as fixed.
  - **The two disagreed in strength as well as origin.** Buildroot was
    generating `$5$` (SHA-256) while the overlay shipped `$1$` — **MD5-crypt**,
    which is the weakest hash the platform still accepts. Now `$6$` (SHA-512)
    in both, safe because busybox 1.36.1 is built `CONFIG_USE_BB_CRYPT_SHA=y`
    and resolves `$5$`/`$6$` with **its own** implementation
    (`libbb/pw_encrypt.c:113-118`), not uClibc's — the check that mattered,
    since login and `su` are busybox applets and a hash format the binary
    cannot parse would have locked the serial console.
  - **The guard has to recompute, not compare.** Re-hashing the *same vendor
    word* under a fresh salt looks like a change in a diff, so the test derives
    `luckfox` against each file's own salt and fails if it matches. Confirmed
    against three mutations (the original `$1$` hash, `luckfox` re-hashed as
    `$6$` with a new salt, and the defconfig reverted); each was caught.

  Stated plainly, because the technical file has to: this is **one shared value
  across units**, short, and offline-recoverable from an image. It is not a
  strength improvement — it removes a *published* default. What makes it
  acceptable is unchanged: it is unreachable over the network (key-only SSH, no
  telnet/adbd, default-deny firewall) and is a physical-access recovery
  credential, on a platform where physical access is already equivalent to full
  control. Per-unit passwords remain the open option. **Owed: a serial-console
  login on a flashed unit** — the `$6$` path has not run on hardware.

  *Secrets encrypted at rest (item 9).* The 0600 sidecar is now sealed with
  **AES-256-GCM**, key = HKDF-SHA256 over this board's **SoC OTP** and **eMMC
  CID** — hardware identity, present in no filesystem. `core/secretbox.c`,
  wired into the two functions that already owned the sidecar's bytes.
  The claim is deliberately narrow and the documents state it that way:
  **confidentiality of the stored bytes once they leave the device** — a pulled
  eMMC, a copied `/userdata`, an RMA return, a support bundle. It is **not**
  protection against root on a running unit, and on a platform with no secure
  element nothing can be. Four design points worth keeping:

  - **An unprogrammed identity is refused rather than used.** A provider
    reading all-`00`/all-`ff` yields *no* binding, because a key derived from
    it would be byte-identical on every unit off the line — the CWE-321 shape
    that got image-embedded certificates rejected on 2026-07-31. A fleet-wide
    key that *looks* encrypted is worse than plaintext that admits what it is.
  - **The fallback is reported, not silent.** No readable identity → the file
    is written as before (0600, clear) and the daemon says so in its startup
    log and in `diagnostics.json` → *Diagnostics → Stored secrets at rest*.
    Same rule as the OPC UA security row: publish what was **achieved**, never
    what was configured.
  - **A sidecar from another board is not a boot failure.** It opens as "no
    secrets stored", is reported `unreadable` with a reason, and the operator
    re-enters the three values. The alternative — refusing to start — would
    turn a cloned image into a brick.
  - **The header is authenticated.** `binding`, `v`, `cipher` and `kdf` travel
    in the clear (a reader needs them before it has a key) and are fed to GCM
    as AAD, so rewriting `binding` to name a weaker provider set breaks the tag
    instead of steering the next read.

  Pinned by `tests/test_secretbox.c` (33 checks — including *a file sealed on
  board A cannot be opened on board B*, with fake boards under
  `IE_BINDING_ROOT`) and 12 integration checks in `tests/test_config_json.c`.
  Five mutations of the shipped module were each confirmed to fail the suite:
  accepting a blank identity, ignoring the recorded binding, dropping the AAD,
  a fixed salt/IV, and skipping a named-but-missing provider. The integration
  checks exist because **the build host has neither binding source**, so every
  pre-existing test in that file exercises the plaintext fallback — a
  regression that quietly stopped encrypting would have passed all of them.
  **Owed: the binding has never been READ on a unit.** `CONFIG_ROCKCHIP_OTP=y`,
  `CONFIG_NVMEM_SYSFS=y` and `CONFIG_MMC_BLOCK=y` are confirmed in the built
  kernel config, but until a flashed unit reports
  `secrets_at_rest.mode = encrypted` this rests on source-level evidence.

  *Outbound licence (item 7) — and a contradiction it exposed.* The decision is
  **MPL-2.0**, which is what Joral already publishes: satisense-edge has
  carried an MPL-2.0 `LICENSE` since its initial commit and declares MPL-2.0 in
  its SBOM application layer. media-gateway now has the same `LICENSE`
  (byte-identical), a README licence section, and `SPDX-License-Identifier:
  MPL-2.0` + a copyright line on all 42 first-party files; its
  `app-manifest.csv` moves from `UNDECLARED (no LICENSE file in tree, no SPDX
  headers)` to `MPL-2.0`, so the SBOM stops describing our own components as
  unlicensed.

  Doing it surfaced a defect nobody had noticed: **87 satisense-edge files
  carried `SPDX-License-Identifier: GPL-2.0+`**, contradicting both that tree's
  own LICENSE file and its own SBOM entry *for the same files*. The tags were
  boilerplate — nothing GPL is linked (open62541 MPL-2.0, EIPScanner MIT,
  libcurl MIT-like, OpenSSL 3 Apache-2.0) — and every one now reads `MPL-2.0`,
  with a copyright line the tree previously had **nowhere**. This is a legal
  determination made from the evidence in the tree, not a licence change on
  someone's instruction: **Carl should confirm it**, and reversing it is one
  substitution in `scripts/compliance/apply-license-headers.sh`. MPL-2.0 is
  file-level weak copyleft — it obliges us to offer the source of *these* files
  to whoever receives a binary — so if that is not the intent, now is the
  moment to say so, before the first customer shipment.
  **It was not the intent — superseded 2026-08-19, see the entry below.** The
  sentence above is left standing because it is the one that got the decision
  asked, and because the window it names is exactly the one the reversal used.

  *Caught by the tests, and worth recording:* inserting two header lines into
  every source file shifted every line number in both trees, and
  `test_listeners.sh` — written on 2026-08-15 specifically to stop compliance
  citations going stale — **failed on five checks** naming `src/main.c:137`,
  `media_gateway.h:224-225` and `can_gw.c:563`. The documents were corrected to
  139 / 226-227 / 565. A licence-header pass is exactly the kind of change
  nobody would think to re-verify citations after; the suite did it instead.

  Also in this pass: the **`dhcpcd` vs `can0`** and **SatiSense daemon log**
  items were already fixed and bench-confirmed earlier the same day (see the
  entry above), and both product suites are green — media-gateway all suites,
  satisense **19 suites** including the new `test_secretbox.c`. Clean
  cross-build of both daemons; SPA rebuilt; the SatiSense user manual §12.1
  gained a *Where stored passwords live* subsection (markdown + on-device Help
  + all three PDFs regenerated).

- **2026-08-19 — both products, outbound licence: MPL-2.0 → proprietary
  (`LicenseRef-Joral-Proprietary`).** Carl's determination, taken on the
  question the 2026-08-16 entry above put to him. Nothing here is a CRA
  requirement in either direction, and it is worth writing that down because
  the question arrived as "must we publish our code to be CRA compliant?":
  **no.** Annex I Part II §1 and Art. 13 ask for an **SBOM in the technical
  documentation** — component metadata, supplied to market-surveillance
  authorities on request. Nothing in the Regulation asks anyone to publish
  source. Open-sourcing would also not have bought relief: the open-source
  steward provisions (Art. 24) and the non-commercial FOSS carve-out do not
  reach a manufacturer selling hardware with the software on it.

  What MPL-2.0 *was* costing us is the reason it went. MPL obligations trigger
  on distribution, and shipping firmware to a customer is distribution of
  Executable Form (§3.2): every file carrying the tag — 43 in media-gateway,
  148 in satisense-edge, including both daemons, both consoles, the auth path
  and the secrets sidecar — obliged us to tell each recipient how to obtain its
  Source Code Form at no charge, while both repositories stayed **private**.
  That is the obligation without the benefit. **Nothing in the dependency stack
  ever required it**: open62541 is MPL-2.0, but MPL is *file-level* copyleft and
  §1.10/§3.3 expressly permit combining it into a Larger Work under terms of our
  choosing — static linking does not change that, and only open62541's own files
  (and our modifications to them, if any) stay MPL. EIPScanner is MIT, libcurl
  MIT-like, OpenSSL 3 Apache-2.0, uClibc-ng LGPL. The GPL/LGPL platform layer
  carries source obligations that were always ours and are unaffected by this
  change; the written offer for them is now `EULA.md` §7, valid three years from
  receipt of the unit.

  **The timing was the whole point.** MPL §2.1 grants are irrevocable for
  whatever has already been distributed, so this was reversible only while no
  customer unit had shipped. That window closes at first shipment, and it is
  the same window as the partition-layout freeze (item 11) — two one-way doors
  that both shut on the first customer delivery.

  Shipped in this pass:
  - `scripts/compliance/apply-license-headers.sh` — the tag is now
    `LicenseRef-Joral-Proprietary` (the SPDX convention for a licence not on
    the SPDX list) and the copyright line carries "All rights reserved."; the
    script also **normalises an existing** Joral copyright line, since without
    that the tag would have read proprietary beside wording written for an open
    licence. 43 + 148 files rewritten, **line counts unchanged**, so no
    compliance citation moved this time.
  - **A vendored-file defect the 08-16 pass introduced and this one caught:**
    `satisense-edge/core/ai/rknn_api.h` had been stamped
    `SPDX-License-Identifier: MPL-2.0` + a Joral copyright line — on top of
    Rockchip's own trade-secret notice, and contradicting the tree's own SBOM
    row, which correctly reads "proprietary (Rockchip)". Declaring another
    party's confidential header under our outbound licence is a
    misdeclaration, not a formality. The Joral lines are removed and the path
    is excluded in `is_excluded()` so no future pass re-stamps it. The general
    rule now in the script's header: **a vendored file carries somebody else's
    notice.**
  - `LICENSE` (repository notice) and **`EULA.md`** (customer terms) in both
    trees. The EULA's load-bearing clauses for this programme are §5 (signed
    updates + declared support period, pointing at
    `firmware-signing-and-support-policy.md`), §6 (reporting a vulnerability —
    and an explicit statement that the reverse-engineering restriction does
    **not** bar good-faith security research or vulnerability reporting, which
    would otherwise sit badly beside `SECURITY.md`), §7 (third-party software +
    the written source offer), and §12 (mandatory law, including CRA rights,
    prevails over the agreement).
  - Both `docs/compliance/app-manifest.csv` first-party rows, both READMEs, and
    a new **Outbound licensing** section in *both* Annex I matrices — satisense
    had no statement of its outbound licence anywhere in its matrix, so nothing
    there would have caught the tag and the manifest drifting apart again, which
    is exactly what happened in the GPL-2.0+ episode.
  - **Two stale claims corrected in media-gateway's Annex I matrix**, both
    found while editing around them: it still said "**no LICENSE file**" and
    "no `LICENSE` file and no SPDX headers anywhere in this tree" (untrue since
    08-16), and its summary blockquote still said CAN connections "are logged
    on the **TCP path only**" — which contradicted §6 of the *same document*
    from the moment the UDP peer record was recovered on 08-18.

  Verified: both `make test` suites green (media-gateway including
  `test_listeners.sh`, whose citation checks are the guard against exactly this
  kind of sweeping edit), SBOM regenerated — **52 platform + 8 application
  components, 5 first-party rows now `LicenseRef-Joral-Proprietary`, zero
  UNDECLARED**, third-party rows untouched.

  **Owed, and none of it engineering** — tracked with owners and acceptance
  criteria in [`outbound-licence-plan.md`](outbound-licence-plan.md), because
  a follow-up list that lives only inside a paragraph of this document is how
  the stale-citation problem started: (1) **counsel review of `EULA.md`** —
  it is drafted from the facts in these trees, not from a template a lawyer has
  signed off; (2) **§12 governing law** is a literal
  `[[JURISDICTION — to be confirmed by counsel]]` placeholder; (3)
  **`support@joralllc.com`**, the address the §7 written source offer directs
  requests to, has not been confirmed to exist — the same failure mode as
  `security@joralllc.com`, which is printed in shipped documents and still has
  no mailbox (item 1); (4) a decision on **how the EULA reaches the customer**
  — no manual in either tree has a legal section today, so adding one means a
  documentation pass and PDF/on-device-Help regeneration.


- **2026-08-19 — platform, Annex I #7 / item 11: the partition layout is
  FROZEN, and freezing it turned up a document describing a product we do not
  ship.** One-way door #1, closed ahead of the key ceremony (door #2) as the
  ordering requires: a unit shipped on a wrong layout cannot be corrected by
  any update, whereas a DEV-keyed trust store at least fails closed.

  The table itself did not change. It has been the value of
  `RK_PARTITION_CMD_IN_ENV` in the `-IPC-AB` board profile since 2026-08-14,
  the spike closed on hardware the same day (sixth pass), and releases
  2026.08.3 and 2026.08.4 were both delivered onto it through the A/B updater
  and bench-confirmed. **What was missing was not the decision — it was
  anything that made the decision hold:**

```
32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),512M(oem),512M(userdata),1536M(rootfs_a),1536M(rootfs_b)
```

  4165 MiB of the nominal 8 G eMMC; ~3 G deliberately unallocated at the tail,
  which is the only post-freeze escape hatch (a partition appended there shifts
  no existing index).

  **Considered and declined the same day: growing `userdata` 512 M → 1024 M.**
  Recorded because the sizing question will come back. Measured use is 18 MiB
  of 512 M (3%), and — the point that settled it — **on-device audit retention
  is not bounded by the partition at all.** It is bounded by rotation:
  `AUDIT_MAX_BYTES` (1 MB) × `AUDIT_KEEP` (3), giving 4 MiB per product, and
  both are shell variables in the rootfs, so retention can be raised by an
  ordinary release through the updater at any time — even to ~128 MiB per
  product within the existing 512 M. The partition only bounds what cannot be
  resized after shipment, and no such claim on the space could be priced today.
  The unallocated tail remains available if one appears **before** first
  shipment.

  Costed while the question was open, so it does not need re-deriving: growing
  p8 moves the `rootfs_a`/`rootfs_b` byte offsets but **no partition index**,
  so `sw-description.in` (which names `/dev/mmcblk0p9`/`p10`) and the initramfs
  (which resolves by `PARTNAME`) would need no edit. It is a six-file change —
  the frozen constant, the board profile, both SocToolKit maps and both
  documents — plus a **reflash** of every already-flashed unit, since the
  updater cannot repartition.

  **The trial change also found a defect in this gate, now fixed.** The first
  version checked `output/image/.env.txt`; `build.sh` regenerates that file
  from the board config during its own startup, so by the time
  `./build.sh partitions` ran it had just been rewritten and agreed by
  construction. It reported ok against an image set still carrying the previous
  table. The check now reads the **packed** artifacts instead — the
  `blkdevparts` string inside `env.img`, and the `S20linkmount` inside
  `rootfs.img` via debugfs — neither of which a build.sh startup touches. Third
  instance in four days of the same failure: a verification sharing an input
  with the thing it verifies. It was caught only because the table was changed
  and the check did not go red.

  **The layout is written once and consumed in six places. Three are
  hand-maintained, and one of those three was wrong.**

  - **The plan document was wrong, and had been for the entire
    implementation.** `swupdate-implementation-plan.md` §"Partition layout"
    specified `uboot_a`/`uboot_b` and `boot_a` — four partitions that no board
    profile has ever carried and no unit was ever flashed with. Nothing was
    built from it, because the board config was always the real source; the
    damage is that this document is the **technical file's** description of the
    update mechanism, and Annex II asks for the *real* update procedure. An
    assessor reading it would have been told about a layout that does not
    exist. Corrected to the shipped table, with per-partition offsets and the
    reason for each size.
  - **`sysdrv/tools/board/emmc/emmc_fstab` still carried single-slot indices**
    — `/oem` on `p5`, which under the A/B table is `boot`, a raw FIT image. It
    is harmless *only* because nothing installs it: no rule in `sysdrv/Makefile`
    or `build.sh` copies it, the shipped `/etc/fstab` is buildroot's skeleton,
    and `/oem` + `/userdata` are mounted by `/etc/init.d/S20linkmount`, which
    `build.sh` **generates** from the partition table and which therefore cannot
    disagree with it. Three documents nonetheless listed editing that file as a
    step of the A/B change, including the board profile's own comment — a
    build step that had never done anything, believed by everyone who read it.
    File corrected and headed with what it is; the same note added to
    `emmc_filesystem_resize.sh`, which resizes `p5/p6/p7` and would take
    `resize2fs` to two FIT images if it were ever wired up.
  - `tools/{linux,windows}/SocToolKit/ipc.json` and
    `ab-boot/swupdate/sw-description.in` were both correct — checked
    offset-by-offset rather than assumed, because these are the two that cost
    hardware: the first is read by the factory flashing station and a stale
    offset writes an image over the wrong partition; the second names
    `/dev/mmcblk0p9` and `p10`, the partitions an update installs onto.

  **The freeze is now `scripts/compliance/check-partition-layout.sh`, wired as
  `./build.sh partitions`** — source-level like `cited`, so it runs on a clean
  checkout, and it holds the frozen string as its **own** constant rather than
  reading it from the board config, because a gate that reads its expectation
  out of the file it is checking cannot fail. That is the 2026-08-19
  `test-image-ownership.sh` lesson applied before the fact rather than after
  it. It asserts the board profile, both flashing maps' names *and* byte
  offsets, the install targets, the generated `blkdevparts` and by-name links,
  image occupancy against every frozen size, and the structural invariants
  (`misc` unsuffixed — `spl_ab_append_part_slot()` special-cases the literal
  name; slots equal; `oem`/`userdata` single-copy so they survive a slot
  switch; contiguous from offset 0; fits the part). Verified by injecting drift
  rather than by passing: a moved `oem` offset, an install target changed to
  `p8`, a shrunk `rootfs_b`, a suffixed `misc`, per-slot `oem`, a gap in the
  table and slots grown past the eMMC are each caught, named and exit 1.

  **Occupancy at the freeze** (release 2026.08.5): rootfs 117 MiB in a 1536 MiB
  slot (7%), `oem` 7%, `userdata` 3%, `boot` 14%. The rootfs slot is 13×
  oversized on purpose — it is the one dimension that cannot be widened on a
  fielded unit.

  *Recorded and deliberately not fixed:* `RK_PARTITION_FS_TYPE_CFG` lists only
  `rootfs_a`, so the generated `S20linkmount` resizes the filesystem to 1536 M
  on slot A and **never on slot B** — a unit running on B keeps the 117 MiB
  filesystem the image was packed at, ~2.5 MB free. Benign today (`/var/log`,
  `/var/tmp`, `/var/spool` are symlinks to the `/tmp` tmpfs, all mutable state
  is on `/userdata` since Phase 0, the rootfs is not written at runtime) and,
  more to the point, **not a one-way door**: `S20linkmount` is generated into
  the rootfs, which an update replaces wholesale, so the fix ships as an
  ordinary release. Changing resize behaviour on both slots days before
  freezing the layout would have wanted its own bench pass to buy nothing.

  *Worth recording:* every one of the three hand-maintained consumers is
  invisible to a build. The board config is checked by the compiler of nothing;
  a wrong `ipc.json` produces a clean build and a bricked unit at the factory;
  a wrong `sw-description.in` produces a clean build and an update that
  installs onto `userdata`. **A one-way door with no gate on it is a
  convention, and this one had been a convention for five days while two
  releases shipped through it.**


- **2026-08-19 — media-gateway, Annex I Part II §3: a stale row corrected, in the
  direction nobody audits.** The matrix still read "`make test` now exists and runs
  all three suites" and "**no coverage of the auth layer, the config writer or the
  listeners**". That had been untrue since the 2026-08-15 coverage pass (item 7):
  `make test` runs **eleven** suites — three host C suites and eight shell suites
  carrying **352 checks**, including `test_webauth.sh` (80), `test_auth_endpoints.sh`
  (58), `test_config_writer.sh` (73) and `test_listeners.sh` (19), which are precisely
  the three gaps the row named. Corrected against a run of the suite, not against this
  document.

  Worth recording as a *class*. Every stale-citation defect this programme has caught
  — the `:565` → `:658` shift, the three fact-sheet citations, the "no LICENSE file"
  and "TCP path only" claims on 08-19 — was a document **overstating** the product,
  which is what an assessor and a reviewer both go looking for. This one understated
  it: the row conceded a gap that had been closed four days earlier, and no test,
  gate or review would ever have flagged it, because nothing is harmed by a product
  being better than its paperwork claims. It was found only by reading the row against
  `ls tests/`. The cited-commit gate does not cover prose of this kind and cannot;
  the practical guard is that **a row's status must be re-derived from the tree in
  the same pass that touches the tree** — which is what action-plan item 1 already
  says, and what did not happen on 08-15.

  Also fixed in the same pass: `docs/project-context.md` pointed at a
  `tests/results/` directory of "integration tests documented as Markdown
  checklists" that has never existed — the one true half of the old row. It now
  describes the shell suites that do exist. `make test` green after both edits,
  including `test_listeners.sh`'s citation checks.

- **2026-08-19 — SatiSense Edge, Annex I #1 and #5: anonymous OPC UA sessions
  closed, and the residual turned out to be describing the wrong risk.**
  ADR-151. The question that started it was whether anonymous could even be
  disabled. It could — the config keys, the console checkbox and the daemon
  support have all been there since ADR-128, and TC-S3 refused an anonymous
  session on hardware on 2026-07-31. What was left was only the shipped default,
  and that is now `allow_anonymous: false`, in `scripts/default/gateway.json`
  **and** in `config_set_defaults()` so an omitted key fails secure. **No factory
  OPC UA credential ships** — that would have rebuilt the default-credential
  problem 4g closed on 08-09 — so a factory unit accepts no OPC UA session until
  an operator sets a username and password, which is what the trust folder
  already did to client certificates.

  **Three things this pass found that were more important than the change
  itself.**

  *The residual was mis-stated.* "Anonymous sessions permitted" was being read
  across these documents as "unauthenticated", and it never was. OPC UA
  authenticates the **channel** by client certificate and the **session** by user
  token; `trust_path` has shipped set since 2026-08-04 (`25b3d6c`), and an absent
  or empty trust folder rejects **every** client. So the default posture was
  already closed, in a way none of our compliance documents said. The Annex II
  fact sheet claimed "client certificates are accept-all — `trust_path` is empty
  by default" from its creation on 08-06, and told the reader that "any host on
  that network can open an encrypted session, read all points and write any tag
  marked writable". Both corrected. That is a fact sheet stating the product is
  **more exposed** than it is, in the document the plan's own action-plan item 3
  warns "gets copied verbatim" — a second instance, in the opposite direction, of
  the class recorded for media-gateway earlier the same day.

  *A control that reported one thing and did another.* `apply_access_control()`
  carried `if (!allow_anon && nlogin == 0) allow_anon = true;` — "never lock
  everyone out". A unit configured `allow_anonymous: false` with no username
  therefore **served anonymous sessions**, while `gateway.json`, the console and
  Diagnostics all said anonymous was off. Diagnostics made it worse by reporting
  the configured value four lines below its own comment explaining why the
  negotiated value must be reported instead — the exact defect that comment was
  written to prevent, in the same JSON object. Had the default simply been
  flipped without reading that function, the change would have shipped as a
  no-op that every surface reported as a success. It is the strongest argument
  yet for the bench: nothing here was visible in the configuration.

  *A fail-open that does not exist.* ADR-131 traded security for availability on
  a trust-folder load error, and the code comment, `epic-09`, and the TC-S3
  runbook all repeated it. In open62541 1.3.15
  `UA_CertificateVerification_CertFolders` only allocates the three path strings
  and **always returns GOOD**; it never touches the filesystem. The branch is
  unreachable, and a missing folder fails **closed**. Corrected in all three
  places, because the two claims send an operator in opposite directions when a
  client will not connect.

  Shipped: `core/opcua_identity.c` — the policy, deliberately free of open62541
  headers so the decision itself is host-testable (18 checks; three mutations —
  restoring the silent re-enable, dropping the accept-all guard, over-reaching
  into `security: none` — each confirmed to fail it). Anonymous is now refused
  outright, whatever the config says, when client certificates are accept-all on
  a secure channel, since that pair is the only configuration in which nothing
  identifies the caller; `security: none` is left alone, being honestly named and
  reported. Diagnostics gains `sessions_possible`, `client_certs_pinned`,
  `user_login` and an `identity_reason`, and now reports **effective** anonymity
  with the configured value alongside it. Console warnings rewritten — there was
  one for the harmless combination and none for the open one. Manual §3.2 gains
  the two-layer table and the commissioning step; Help and the Annex I/II
  documents regenerated. `make test` + `make test-config` green, both changed
  sources cross-compile clean against the real open62541 with
  `UA_ENABLE_ENCRYPTION` set.

  **Owed: the bench leg (item 8f).** Everything above is a host claim. The
  assertion that matters — a real OPC UA client turned away from a
  factory-configured unit — has been made only by a test harness.

- **2026-08-19 — Annex I #2, the two dated triage rows: one closed outright, one
  staged.** The gate has passed at 0 blocking since 08-12, but two rows were
  carrying that pass on a timer — dhcpcd expiring 2026-11-12 and five python3
  rows expiring 2026-11-09. Both were examined against the build rather than
  against their own justifications, and both turned out to be cheaper to resolve
  than to re-review.

  **dhcpcd CVE-2026-56116 — reclassified `not-affected`, `REVIEW_BY` 2027-02-19.**
  The row said `fixed-pending-release`, which this file defines as "the fix is
  merged and this is the window before it ships". No upstream release was
  pending: the mitigation is our own `ipv4only` line and it shipped on 08-12. The
  row would therefore have expired into a blocking finding for a code path that
  cannot execute. Verified in dhcpcd-9.4.1's own source rather than taken on
  trust — `ipv4only` maps to case `'4'` (`src/if-options.c:120`) which clears
  `DHCPCD_IPV6` (`src/dhcpcd.c:1250`), and the ICMPv6 ND socket is opened only
  inside `if (ctx->options & DHCPCD_IPV6)` (`src/privsep-inet.c:159`). Nothing
  reaches the RA route-information parser. Replacing dhcpcd with busybox
  `udhcpc` was considered and rejected: media-gateway's `S39` writes a managed
  block into `dhcpcd.conf`, `S50` drives `dhcpcd -k`/`-n` for the bridge, and
  the factory reset knows about the block — a product change for no security
  gain.

  **The reclassification came with a guard, and would not have been correct
  without one.** `not-affected` divides into two kinds that do not age alike: a
  decision resting on a compiled-out feature or a version fact stays true by
  itself, while a decision resting on a **configuration line** can be undone by
  an edit, an overlay that fails to apply, or a runtime script that rewrites the
  file — and when that happens `./build.sh cve` keeps passing, because the gate
  reads the triage row, not the config the row is talking about. So the file
  `scripts/compliance/test-cve-mitigations.sh` now proves the sentences the row
  makes: `ipv4only` and `denyinterfaces can*` active in the overlay, IPv6 INPUT
  policy DROP with no rule admitting RA/RS, and — by **running S39's own
  marker-strip awk over the file** rather than reading it — that the
  media-gateway managed block cannot eat the mitigation at boot. Given a packed
  rootfs it also checks the image, discriminating post-overlay trees by the
  presence of `/etc/ip6tables.conf` so buildroot's pre-overlay staging does not
  raise a false alarm nobody would keep listening to. Seven checks, each
  confirmed to fail against a mutation of the thing it guards. The general rule
  is now in the compliance README: **a config-level `not-affected` needs a check
  before it is written, and the justification must name it** — otherwise you
  have traded a dated review for a silent regression, which is the worse of the
  two. As a side effect the triage file now carries **no
  `fixed-pending-release` rows at all**.

  **python3 ×5 — the premise of the row was wrong, and the fix is smaller than
  it claimed.** The row, and the defconfig comment beside it, said the
  interpreter had to stay because the on-device bench tooling needed it, and
  that shipping without it would mean validating an image we do not test on.
  Reading all six bench scripts showed **five of them never run on the device**:
  `gate5-copilot.py` says so in its own docstring, `gate2-commission.py`,
  `mvad-capture.py` and `enable-llm.py` are `--host` network clients, and
  `modbus-slave.py` runs on-device only as a convenience ("no second machine").
  Only `encoder-sim.py` genuinely needed AF_CAN on the unit. So an 18 MB
  interpreter was in every shipped image for one CAN frame generator — and
  can-utils, which is already in the image, can replay one.

  `encoder-sim.py` gained `--emit-log` and `--segment DUR:RPM[,DRIVE]`: the
  trajectory is generated on the bench PC as a candump log and replayed on the
  unit with `canplayer`. The live sender and the log emitter now share one
  `Shaft` integrator and one `build_payload()`, because the claim is that the
  replay is a *substitute* for the live simulator and that is only cheap to keep
  true with one copy of the arithmetic. `tests/test_encoder_sim.sh` (14 checks)
  is that claim: it drives the **real** live loop with a fake socket and a
  virtual clock and proves 900 frames **byte-identical** to the emitted log;
  it holds the log to the format `canplayer` actually parses; and it decodes the
  log through the **daemon's own `j1939_spn_decode()`** against the seven
  phase-C `encoder` SPNs — a second decoder written for the test would only
  prove the test agrees with itself. The walk decodes to 90/54/30 rpm on the
  minute with the count reaching 174, and the gate-4 `corr_break` fault reports
  30 rpm while the shaft advances 180 revolutions in 120 s. Five mutations, all
  caught.

  Two format traps were found by compiling against **can-utils 2021.08.0's own
  `lib.c`**, the copy built for this image, rather than by reading its
  documentation. Both fail silently: `canplayer.c:411` scans the timestamp with
  `"(%lu.%lu)"`, so microseconds must be zero-padded to six digits or the replay
  runs at the wrong speed with no error; and `lib.c:181` treats an identifier as
  extended only at exactly 8 hex digits, so a short id parses as 11-bit, the
  profile's source address never matches, and the console simply shows a silent
  bus. The `gate4-gate5` runbook now carries both paths — replay for images
  without python, the live simulator for older ones — and the caveat that
  `canplayer -l i` restarts the revolution **count** on every wrap while
  position and rpm stay continuous, which is a trajectory no encoder can produce
  and which the anomaly detector is entitled to fire on.

  **Staged for removal, then reversed the same day — the fix is a version bump.**
  `BR2_PACKAGE_PYTHON3` was turned off with the evidence and preconditions written
  beside it, and then turned back on. The reachability findings above all stand and
  are why the `canplayer` replay path exists; what changed is the conclusion drawn
  from them. Keeping a working interpreter on the device was judged worth more than
  the ~18 MB, and — decisively — **the CVE case for removal was weaker than it
  looked**. Of the five rows, `CVE-2020-29396` is not a CPython defect at all: it is
  an Odoo 11.0–13.0 sandbox escape that NVD matches against us only because python is
  listed as Odoo's running-with platform, the same false-match shape as
  `CVE-2019-0190` (openssl as the platform of Apache httpd `mod_ssl`) and
  `CVE-2022-48174` (a busybox CPE with no version bound), both already `not-affected`
  in the file. It is now reclassified `not-affected`, and it is worth being blunt
  about why it mattered: carrying it as accepted-risk implied a removal or a bump
  would eventually clear it, and **neither ever would have**.

  The remaining four are closed by moving off buildroot 2023.02.6's stock **3.11.6**
  to **3.11.16** (12 Aug 2026; the 3.11 branch is security-only until Oct 2027).
  `CVE-2024-6232` (tarfile ReDoS) and `CVE-2024-7592` (http.cookies quadratic) are
  fixed in 3.11.10. `CVE-2026-4519` and `CVE-2026-15308` both postdate 3.11.15
  (03 Mar 2026) and predate 3.11.16, so 3.11.16 is expected to carry them — expected,
  not asserted: only the `./build.sh cve` re-run at the new version settles it, and
  the four rows stay accepted-risk until it does.

  The bump is a whole-package replacement at
  `sysdrv/tools/board/buildroot/python3/`, copied in by `sysdrv/Makefile` exactly as
  `libopenssl` (3.5.7) and `open62541` (1.3.15) are, because `sysdrv/.gitignore`
  treats `sysdrv/source/buildroot/**` as throwaway. All **31 stock patches were
  verified to apply against 3.11.16 sequentially, as buildroot applies them — 0
  failures**, 3 with fuzz within tolerance. Checking them independently against a
  pristine tree instead reports 14 failures, which is an artefact: most insert into
  the same `configure.ac` region and depend on their predecessors. The tarball's
  sha256 was confirmed against the `messageDigest` in the CPython release's
  `.sigstore` bundle, i.e. the digest committed to the Rekor transparency log.

  **3.12+ was considered and rejected as out of reach for this tree**, not merely
  expensive. Eleven of the 31 patches target files CPython has since deleted or
  moved: `setup.py` (7 patches; deleted in 3.12, module building moved to
  `configure.ac` + `Modules/Setup.stdlib.in`), `Lib/distutils` (2; deleted in 3.12
  per PEP 632), `Lib/crypt.py` (1; deleted in 3.13 per PEP 594) and `Tools/scripts`
  (1; moved in 3.12). One of the `setup.py` casualties is patch 0003, the
  infrastructure every `BR2_PACKAGE_PYTHON3_*` toggle rests on — it would need
  reimplementing, not porting. The external Rockchip toolchain is **gcc 8.3.0**
  (crosstool-NG 1.24.0) targeting uclibc-ng and is not ours to move. The one point in
  favour was that no third-party python module packages are enabled here (verified:
  zero `BR2_PACKAGE_PYTHON_*` set), so the distutils removal in `pkg-python.mk` would
  not have bitten — but that does not touch the eleven dead patches.

  Still owed: the rebuild, then `./build.sh cve` to retire the four rows; buildroot
  never uninstalls, so this needs a clean rootfs rebuild, the trap that kept mpv,
  iperf and the `wifi_app` binaries alive after the 08-10 trim. Bench leg **8g** (one
  `canplayer` replay on a unit) is no longer a shipping precondition now that the
  interpreter stays, but the replay path is validated and worth keeping. Two loose
  ends were cleanup rather than blockers, and one of them turned out to be a real
  defect. `/usr/bin/smtpd.py.11` — CPython's stdlib demo SMTP **server**, 31 KB and
  executable — has shipped on the device's PATH in **every** image, because stock
  `python3.mk` removes `smtpd.py.3` while CPython installs it as
  `smtpd.py.<minor>`, so buildroot's own cleanup `rm` has always been a silent
  no-op. Globbed in the package replacement — **but as of 2026-08-19 it has not
  taken effect, and the reason is worth more than the file.** 3.11.16 installed
  at 05:01 and stamped `.stamp_target_installed`; the corrected `python3.mk`
  reached the live buildroot tree at 08:33, *after* that stamp. Buildroot never
  re-runs an install it has already stamped, so the hook has never fired and
  `smtpd.py.11` is still in the packed `rootfs.img` — verified with `debugfs`.
  A fix that lives in a **post-install hook** is inert against an
  already-installed package: it needs `python3-reinstall` (or `-dirclean`), the
  same family as the busybox-config trap. The interpreter bump itself DID land —
  `libpython3.11.so.1.0` in the image reports 3.11.16.

  **Resolved the same day.** `python3-reinstall` cleared it, and the rebuilt
  `rootfs.img` (release 2026.08.5) reads back 3.11.16 with **no
  `smtpd.py.*`**. `./build.sh cve` after a fresh SBOM: **0 blocking, 68
  monitor, 32 suppressed**. Two of the four accepted-risk rows are genuinely
  gone — **CVE-2024-6232** and **CVE-2024-7592** no longer match the image at
  all, and the gate said so itself, warning that both triage entries had
  become stale. Their rows are deleted: the triage vocabulary has no "fixed"
  state on purpose, because an upgraded component simply stops matching, and
  **a suppression that outlives its finding is the same evidence problem as a
  stale fact sheet** — it silently covers a future re-introduction.
  **CVE-2026-15308 and CVE-2026-4519 still match 3.11.16** and stay
  accepted-risk on the unchanged reachability argument; the bump was never
  going to retire them. The honest count is python3 ×2, and the row that said
  "×4 pending the rebuild" now says so.

  `/usr/bin/event_rpcgen.py` remains, but it comes from libevent rather than
  python3 — a **build** tool carrying `#!/usr/bin/env python`,
  already broken since there is no python2. `/sbin/routel` keeps working, since
  python3 stays. Only the Pico Ultra profile is changed; the
  other board profiles remain untouched and unexercised (item 13).

- **2026-08-19 — platform (shared SDK tooling), Annex I #3/#5: the other board
  configs (item 13). The ext4 packer is clean on all eleven boards that use it.
  Asking the question found two defects in the packer, one in every image this
  product has ever shipped, and an entire packing path where the 2026-08-15
  ownership fix was never in force at all.**

  **What the SDK actually contains.** Sixteen board configs, and the useful
  question was never "do all sixteen build" but "where does the shared packer
  run". Eleven use ext4 and therefore `mkfs_ext4.sh` — **26 partitions**: the
  five EMMC Buildroot boards (86Panel, Pi, Ultra, Ultra-AB, Zero) at
  rootfs+oem+userdata, the EMMC Busybox FASTBOOT board at `userdata` only, and
  the five SD_CARD boards (RV1103 Pico/Mini/Plus/WebBee, RV1106 Pro Max) at
  rootfs+userdata. The remaining five are SPI_NAND profiles whose partitions are
  ubifs and erofs; `mkfs_ext4.sh` never runs for them, which turned out to be
  the important half of the answer (below).

  **All 26 pack clean.** Each was packed with the tracked packer at *that
  board's own geometry* — including the `-(rootfs)` growup partition the SD_CARD
  boards use and the Ultra profile never takes, where the size is derived from
  the tree rather than read from the partition table — against the real
  assembled staging trees, and then verified by reading every inode's uid and
  gid back out of the image: 2551/2551 in rootfs, 217/217 in oem, `e2fsck -fn`
  clean on all 26. Geometry ranges from 268 MB to 6 GB with no behaviour change.
  What this does **not** cover is stated below: the nine non-Ultra buildroot
  boards assemble their tree from `luckfox_pico_defconfig`, which has never been
  built here.

  **One real build, and a control.** `./build.sh firmware` was run end to end
  against the **single-slot Pico Ultra** config (6144 MB `rootfs`, 256 MB
  `userdata`) and then again against the A/B config we ship (1536 MB `rootfs_a`,
  512 MB `userdata`). Both packed all three partitions root-owned; both then
  failed at exactly the same later step, `update.img`, for a missing
  `download.bin` — a u-boot artifact absent from a pruned `output/image`, not
  anything board-specific. Running the shipping board as the control is what
  makes that claim worth anything.

  **Defect 1 — the packer's guard did not check what its comment claimed.**
  `debugfs` addresses inodes by quoted path, so a name containing a double quote
  or a newline cannot be expressed. The code refused the first and silently
  accepted the second, while the comment above it said both. Measured on a tree
  containing `/etc/shadow\nevil`: **packer exit 0, its own verification
  reporting zero bad inodes, and the file still 1000:1000 in the packed image.**
  Precisely the shape of the `fakeroot` approach this pass exists to replace — a
  check that could not fail.

  **Defect 2 — the verification could not see past the list that caused the
  problem.** It was derived from the applied command file by `sed`, so it could
  only ever catch `debugfs` refusing a line, never a tree the list had failed to
  describe: the same defect wrote both files. It also grepped `User:` only, so a
  root uid with a **non-root gid** passed. Replaced with a walk of the image's
  own directory tree, breadth first, addressing every directory by **inode
  number** (`ls -l <n>`) so that no filename is ever quoted and nothing a
  filename can do will break it; uid and gid are both read back, and inodes the
  path list could not name are caught anyway. One `debugfs` run per tree level —
  about ten for a full rootfs, no measurable cost. The build now prints
  `walked 2551 inode(s) ... all uid/gid 0`.

  Guarded by `scripts/compliance/test-image-ownership.sh`, seven checks, added
  to the source-level gates in the release procedure. It needs no build — it
  packs its own throwaway trees with the tracked SDK e2fsprogs — and it asserts
  the packer **fails** when it should: a hostile path is refused; with the
  guard disabled the walk still finds the unowned inode; and a gid-only
  regression is rejected. A test that only proves the happy path
  would have passed against both defects above.

  **Defect 3 — `/etc/shadow` has shipped world-readable in every image.** Found
  while reading modes out of the packed rootfs: `0755`, root-owned since 08-15
  but readable and executable by everyone, carrying the hash. Inert for exactly
  the reason the uid-1000 bug was inert — nothing runs unprivileged yet — and it
  goes live the moment CRA hardening unprivileges a daemon, which is the
  direction all of this work points. The interesting part is why it survived:
  **three mechanisms each look like the place to fix it and none of them can.**
  Git stores only the executable bit, so a 0600 file in the tree checks out 0644
  for the next person. `RK_POST_BUILD_SCRIPT` runs *before* `post_overlay`, so
  the overlay overwrites whatever it sets — already recorded as a gotcha, now
  with a consequence. And `post_overlay` installs with
  `rsync --chmod=u=rwX,go=rX`, which **cannot express a mode narrower than
  0644**: every overlay file is world-readable by construction. So the fix is a
  hook in `build_firmware` immediately after `post_overlay`
  (`__HARDEN_SECRET_FILE_MODES`), and the mode is verified by reading it back
  out of the packed image: `100600`, uid 0, gid 0. Two checks in
  `test-root-credential.sh` now assert both the mode in a packed tree and that
  the hook still runs *after* `post_overlay` — both were negative-tested.

  **The half of the SDK the 08-15 fix never reached.** `mkfs_ext4.sh` was fixed;
  the ubifs and erofs packers were not, and `mkfs_ubi.sh` "handles" ownership
  with **the exact `fakeroot` approach that 2026-08-15 proved does nothing**: it
  writes `chown -h -R 0:0` and the packer invocation into one script and runs it
  under `fakeroot`. `mkfs.ubifs` and `mkfs.erofs` are both statically linked, so
  neither consults `LD_PRELOAD`; `mksquashfs` is dynamic, so fakeroot works for
  squashfs and silently fails for the other two. Measured rather than reasoned:
  a static SDK packer run *inside* that fakeroot session, after that chown,
  still wrote `1000:1000`; `mkfs.erofs` on the real staging tree reported
  `/etc/shadow` as `Uid: 1000 Gid: 1000` via `dump.erofs`.

  **erofs is fixed and measured**: `mkfs.erofs --all-root`, verified by reading
  `/`, `/etc`, `/etc/shadow` and `/etc/ssh/authorized_keys` back out with
  `dump.erofs` (all 0:0) and `fsck.erofs` clean. **ubifs is deliberately NOT
  fixed**, because the bundled mtd-utils 2.0.1 cannot express the fix
  completely and shipping a half-fix that looks whole is the failure mode this
  entry is about. Parsing the inode nodes out of the raw ubifs image directly:
  `--squash-uids` moves three of four inodes to 0:0 and **leaves the root inode
  at 1000:1000**, and a device table cannot cover it either — `mkfs.ubifs`
  rejects `/` with "device table entries require absolute paths". A `/` owned by
  the build uid is not cosmetic; it is create and unlink at the filesystem root.
  Left as a precondition on ever shipping a SPI_NAND profile rather than as a
  fix nobody verified.

  **What item 13 asked for that this is not.** No boot pass: fifteen of the
  sixteen configs are for boards we do not have, and the ext4 evidence above is
  image-level, not a running unit. The nine non-Ultra buildroot boards build
  their rootfs from `luckfox_pico_defconfig`, which has never been packed here,
  so the *geometry* half of those boards is verified and the *tree-content* half
  is not. And the finding that makes the rest of it moot for now: **14 of the 16
  configs are stock BSP profiles.** Only the two Pico Ultra configs carry
  `RK_POST_BUILD_SCRIPT=luckfox-hardening-post.sh`; four still set
  `RK_ENABLE_WIFI=y` (which reinstalls hostapd 2.6 / wpa_supplicant 2.6 and the
  prebuilt `wifi_app` binaries, outside the SBOM and the CVE gate), and
  `luckfox_pico_defconfig` still carries `BR2_PACKAGE_WGET=y` — the package
  dropped from the `_w` defconfig on 2026-08-16 to retire the one expiring
  accepted-risk CVE. **An image built for any board other than the Pico Ultra
  today is not a compliant artifact**, whatever the packer does, and that is a
  larger statement than "the build passes".

  **CONFIRMED ON HARDWARE 2026-08-19 — the ext4 half of item 13 is closed on a
  unit.** A SatiSense Edge bench unit was updated to **2026.08.4 through the
  A/B updater** (not reflashed, so the change travelled the way a customer's
  would) and reports: `/etc/shadow` at `-rw------- 0 0` — the world-readable
  mode is gone from a running unit, not just from a build log; `/`, `/etc`,
  `/etc/ssh` and `/etc/ssh/authorized_keys` all `0 0`; and
  `find / -xdev \( ! -user 0 -o ! -group 0 \)` **empty** — no inode on the root
  filesystem is owned by anything but root. Key-authenticated SSH succeeds with
  `StrictModes` at its default, which is the acceptance test the ownership pass
  exists to satisfy. `misc_ab` shows both slots bootable and
  `successful_boot=1` with the previous release intact on the other slot, and
  the daemon came up on the new slot (OPC UA on :4840 in
  `/var/log/intelligence-edge.log`). The same run surfaced the `oem` gap
  recorded in the next entry.

  *Worth recording:* every one of the three packer defects was a check that
  could not fail, and each was found by asking a different question than the one
  the check answered. The guard was found by asking what the comment claimed
  rather than what the code did; the verification by asking where its input came
  from; the erofs and ubifs paths by asking which boards the fixed tool does not
  run on. The 08-15 entry drew the lesson "verify the image, not the tooling".
  The sharper version after this pass is **verify the image independently of
  whatever produced it** — a verification that shares an input with the thing it
  verifies is part of the same mechanism, not a check on it.


- **2026-08-19 — SatiSense Edge, Annex I #1/#3/#5: the root daemon loads a
  library from a partition the updater cannot reach, and that partition is
  owned by the build user on every unit in the field.** Found by running the
  ownership sweep on hardware rather than on a build.

  Three facts that are individually dull and together are not:

  - **`/oem` is not in the update.**
    [`sw-description.in`](ab-boot/swupdate/sw-description.in) carries exactly
    one payload, `rootfs.img`, to `p9` or `p10`. The `oem` partition (p7) is
    single-copy — there is no `oem_b` — so it is never written by an update and
    could not be written safely by one: a power cut mid-write would leave a
    corrupt `oem` with nothing to roll back to. The payload is rootfs-only for
    a good reason.
  - **So the 2026-08-15 ownership fix never reaches it.** Measured on the bench
    unit after updating to 2026.08.4: `/oem/usr` is `drwxrwxr-x 1000 1000` —
    owned by the build user *and* group-writable by it. The freshly built
    `oem.img` is correct (218/218 root-owned), so a **reflash** fixes this and
    **no update ever will**. Every unit flashed before 2026-08-15 is in this
    state permanently.
  - **The daemon's library search path points there.**
    `S60intelligence-edge` exports
    `LD_LIBRARY_PATH=/oem/usr/lib:/oem/lib` for the daemon *and* for every
    console CGI that re-execs it, because `intelligence_edge_opcua` carries a
    hard `NEEDED` entry for `librknnmrt.so` (190 KB) which ships **only** in
    `oem`. Every one of its other ten `NEEDED` libraries resolves inside the
    rootfs; this is the single exception.

  Put together: a uid-1000 or gid-1000 process can replace a shared object that
  a **root** daemon loads at its next start. That is a privilege escalation
  with a concrete path, not the latent kind — it is inert today only because no
  uid-1000 account exists in `/etc/passwd`, the same thread that has now run
  through the rootfs ownership bug, the `/etc/shadow` mode and this. The
  difference is that the first two were fixed by shipping a new image and this
  one cannot be.

  media-gateway does not link `librknnmrt.so` and does not export the path, so
  this is SatiSense-only.

  **The remedy is to move the 190 KB library into the rootfs** and drop the
  `/oem` search path, which puts every library a root daemon loads on the
  partition the updater actually writes, verifies and owns. Not done here: it
  changes what ships and wants its own bench pass. Filed as remaining-work item
  14. Fielded units still need a reflash regardless — that is what "no update
  can fix it" means, and it should be stated in the Annex II fact sheet next to
  the existing flash-date caveats rather than discovered by a customer.

  **REMEDY SHIPPED AND BENCH-CONFIRMED 2026-08-19, release 2026.08.5.** The
  library now installs into the rootfs from satisense-edge's own `make install`,
  guarded by the *same* `wildcard` test that adds `-lrknnmrt` to the link — so
  the daemon can never carry a `NEEDED` entry for a library this package does
  not ship — and the `/oem` export is gone from `S60intelligence-edge`. On the
  unit after updating: the daemon is up (pid 726, OPC UA on :4840) and `ldd`
  resolves **every one of its thirteen libraries inside the rootfs**, with
  `librknnmrt.so => /usr/lib/librknnmrt.so` and **no path under `/oem` at all**.
  `ldd` is the right evidence here rather than "it started": it enumerates what
  the loader actually bound, so it distinguishes a fixed search path from a
  lucky one.

  **Not closed, and the same sweep found why.** `/etc/profile.d/RkEnv.sh` — BSP
  boilerplate for the Rockchip IPC app, which this image does not run — still
  exports `HOME=/oem`, puts `/oem/{,usr/}{bin,sbin}` on `PATH` and **prepends
  `/oem/usr/lib:/oem/lib` to `LD_LIBRARY_PATH`**. `profile.d` is sourced by
  interactive login shells only, so it never touched the daemon (which is why
  the `ldd` above is clean), but it means **an administrator's own root SSH or
  serial session still searches a uid-1000-writable partition for libraries
  first** — prepended, so ahead of `/usr/lib`. The daemon was the loud half of
  this exposure; this is the quiet half, and it survived because the fix was
  aimed at the service rather than at the partition. Nothing in either product
  needs the file (rkipc is deliberately not started, `S21appinit`), so the
  remedy is to delete it in `luckfox-hardening-post.sh`, which runs after the
  rootfs is assembled and before the overlay — the one hook that can reach it.
  **Done in release 2026.08.6**, verified absent from the packed image and then
  measured on the unit — in an **interactive login session**, which is the only
  shell that sources `profile.d` and therefore the only place the claim can be
  tested: `LD_LIBRARY_PATH=[]`, `/etc/profile.d` holding only
  `enable_coredump.sh` and `umask.sh`, and `ldd` on the daemon reporting **0**
  paths under `/oem`. A non-login `ssh host "echo $LD_LIBRARY_PATH"` prints
  empty on *every* release, including ones that still ship the file, so that
  form would have been another check that could not fail. Corroborated
  incidentally by the shell prompt itself, which reverted from showing a
  directory name to `~` once `HOME=/oem` stopped being set. Removing it was safe to establish rather than assume:
  its only consumer is `S60micinit`, which guards everything behind
  `command -v amixer`, and `amixer` is in neither the rootfs nor `oem` — so
  that script has been a no-op on every boot this image has ever had, and the
  `[ -f ... ] &&` around its `source` makes the deletion inert for it.

  `/oem` ownership is unchanged on the unit, exactly as predicted:
  `/oem/usr` still reads `drwxrwxr-x 1000 1000` after the update. This release
  removes the daemon's *reachability*, not the ownership. Only a reflash clears
  the ownership.

  *Worth recording:* the sweep that found this is the one the build already
  runs — every inode root-owned — and the build had been passing it for four
  days. It passed because the build can only ever check the image it just
  packed, and `oem.img` was correct. The device is the only place where "the
  partition we do not rewrite" and "the partition on the daemon's library path"
  are the same sentence. **Verify the image, then verify the unit** — they are
  different claims, and this one was only ever visible on the unit.


- **2026-08-19/20 — bench session: four legs closed, four findings, three plan
  corrections.** Run against release 2026.08.6 on the Pico Ultra bench unit,
  driven from the bench PC; every command and its output is in the session
  record. The pattern of the day was the one this programme keeps re-learning:
  three of the four findings were invisible to review and only appeared because
  something was executed.

  **Leg f (OPC UA identity, ADR-151) — CLOSED.** The assertion that had only
  ever been made by a host harness has now been made by UaExpert against a
  board, in both directions and with the layers separated:

  | Config | Token | Result |
  |---|---|---|
  | `anon:true`, no user, `trust_path:""` | anonymous | `BadIdentityTokenInvalid` ×2 |
  | `anon:false`, no user, **pinned** | username/pw | `BadUserAccessDenied` ×8 |
  | `anon:false`, no user, pinned | — | `sessions_possible:false` + the exact `identity_reason` |
  | `anon:false`, user set, pinned | username/pw | **session established**, address space browsed |
  | `anon:false`, user set, pinned | anonymous | `BadIdentityTokenInvalid` |

  Pinning the client certificate first is what makes this evidence rather than
  noise: with an empty trust folder the refusal lands at the *channel* layer
  (`BadCertificateUntrusted`) and never reaches identity at all. Every refusal
  above sits behind a `Reloading the trust-list` line, so the channel succeeded
  and the only variable was the user token.

  **Correction 1 — item 8f's expected status code was wrong by half.** It said
  every refusal is `BadIdentityTokenInvalid`. Per open62541 1.3.15's
  `ua_accesscontrol_default.c`, that is right for an anonymous token but a
  well-formed *username* token against a server with no configured logins
  returns `BadUserAccessDenied` (the loop over `usernamePasswordLogin` finds no
  match). Both are refusals; they are different rows and a runbook that expects
  only one of them reads a pass as a failure.

  **Correction 2 — and this one was mine, corrected by the bench.** Reading the
  same source, the anonymous `UserTokenPolicy` is only advertised
  `if(allowAnonymous)`, from which it follows that a conforming client should
  never send the token and no refusal should ever be logged. UaExpert sends it
  anyway and the server refuses it at `ActivateSession`, logged. The source read
  was a plausible inference; the client is the fact.

  **Leg e (secrets at rest) — half CLOSED, half withdrawn by a product
  decision.** `diagnostics.json` reports
  `"secrets_at_rest":{"mode":"encrypted","binding":"soc-otp+emmc-cid"}` on a
  flashed unit, and both binding sources were read from real hardware for the
  first time (the OTP carries the SoC part string, the eMMC CID its vendor id —
  the host suite fakes both). A password stored through the console minutes
  earlier appears in neither `gateway.json` nor the sidecar, and the sidecar is
  a `{"v":1,"cipher":"aes-256-gcm","kdf":"hkdf-sha256",...}` envelope at 0600.
  That discharges what item 9 owed. The `$6$` serial-console login is not
  outstanding any more — it is **withdrawn**, see the product decision below.

  **Leg c (media-gateway durable audit) — CLOSED.** A deliberately failed login
  produced `event=login result=fail user=admin src=unknown-via-tls` with no
  password, and stunnel logged `accepted connection from ::ffff:172.32.0.100`
  in the **same second**. That join is the attribution chain: behind the TLS
  terminator every request arrives from 127.0.0.1, so recording that would name
  the wrong principal. Durability is exact — 2425 → 2426 lines, the record
  surviving a reboot that wiped `/var/log` as the tmpfs it is.

  **Leg a (downgrade refusal) — CLOSED, both outcomes.** The gate that had never
  run on hardware:

  ```
  fw_upload success version=2026.08.5 running=2026.08.6 order=older   <- "verified":true
  fw_apply  fail    reason=downgrade_unconfirmed order=older from=2026.08.6 to=2026.08.5
  fw_apply  fail    reason=downgrade_unconfirmed   (phrase in the wrong case)
  fw_apply  started from=2026.08.6 to=2026.08.5 order=older downgrade=true
  fw_apply  success target=a
  ```

  Driven with `curl` against the CGI, never through the browser — the
  difference between a control and a screen. A **valid** CMS signature on a
  package the gate still refused is the point: CMS attests who built it, never
  when. What it buys is honest and limited: it does not stop an attacker holding
  console credentials, it converts a silent signed rollback into a warned,
  confirmed and recorded one.

  **Correction 3 — the runbook's expected audit token does not exist.**
  §6 says to look for `fw_apply refused …`; the shipped CGI writes
  `fw_apply fail … reason=downgrade_unconfirmed …`. A bench operator matching
  the runbook literally would have recorded a miss.

  **Finding A — SSH host keys are per-slot, and Phase 0 missed them.**
  `/etc/ssh` ships no host keys; `S50sshd` runs `ssh-keygen -A` into `/etc/ssh`,
  which is on the **rootfs slot**. Phase 0 moved config, secrets, the console
  credential and per-unit TLS material to `/userdata` and did not move these.
  So every A/B update mints a new SSH identity, each slot keeps its own, and
  switching slots flips between them. The operator-facing consequence is the
  serious one: a routine update is indistinguishable from a man-in-the-middle,
  which trains people to delete the warning. Observed as a real
  `REMOTE HOST IDENTIFICATION HAS CHANGED` on the bench.

  **Finding B — an updated unit keeps pre-Phase-0 paths forever.** The bench
  unit's `gateway.json` still points `cert_path`/`key_path` at
  `/etc/intelligence-edge/` and `usage_state_path` at
  `/etc/intelligence-edge/usage-state`. Those files exist and are live —
  the OPC UA **private key** and the usage state are on the partition every
  update replaces — while an unused correct pair sits in
  `/userdata/satisense/state/`. The factory default ships `/userdata/...`
  paths and `S60` seeds state *only when absent*, so a unit updated from a
  pre-2026-08-14 release never migrates. Same class as Finding A: per-unit
  identity on a slot.

  **Finding C — the TLS readiness probe accepts any listener, on satisense
  too.** A console-driven service restart logged
  `Binding service [web] to 0.0.0.0:8080: Address already in use (98)` while
  `S60` printed `(https:8080) OK` — the probe took the *old* stunnel as proof
  the new one had started. This is defect (2) from the media-gateway TLS work
  of 2026-08-09, which that entry explicitly flagged as needing carrying
  across. It recovered on its own here, so it is a latent defect rather than an
  outage, but the fix has a known shape and has been sitting in the other tree
  for ten days.

  **Finding D — a completion audit record names no version.**
  `fw_apply result=success target=a` carries the slot and nothing else; only the
  `started` record names the transition. That is half of the problem the
  `started` record was written to solve — "target=b alone cannot answer whether
  this unit ever ran an affected build" — reappearing one record later.

  **Product decision, taken 2026-08-19: serial console access is not provided
  on production images.** That withdraws the last use of the shared root
  password (SSH has been `PermitRootLogin prohibit-password` since 2026-08-08,
  so it was already unreachable over the network), and with it the objection
  that had blocked the strongest option on the standing three-way decision.
  Both halves are implemented together, because either alone is worse than
  either together — a live getty in front of a locked account is a prompt
  nobody can pass, and a removed getty in front of a live shared password
  leaves a fleet secret behind a door that is merely closed:

  - the getty is removed in `luckfox-hardening-post.sh` (buildroot installs the
    skeleton `inittab` after both the defconfig and the overlay, so the
    post-build hook is the only place that can), and the build **fails** rather
    than shipping an image that still serves one;
  - the board overlay's `/etc/shadow` ships root as `*`, the same value every
    other system account in that file already carried;
  - `scripts/compliance/test-root-credential.sh` guards both halves in one
    file and now fails if either is lost — verified by running it against the
    pre-change staging tree, which it correctly rejects on the live directive.

  Kernel console *output* is unaffected; only the login goes.

  **The cost is ours, and it is worth stating.** Engineering loses the console
  too — the decision was "customers and developers", not customers alone — so a
  unit that will not boot far enough for sshd is now a reflash rather than a
  debug session, and `ab-boot/README.md` still lists a serial console among the
  prerequisites for the A/B bring-up spike it describes. That prerequisite was
  satisfiable when it was written and is not any more on a production image;
  bring-up of that kind needs a build with the hook disabled, which is a
  deliberate, non-shippable image rather than a flag on a released one.

  **`*` and `!` are not interchangeable here, and the difference would have
  bricked the unit.** openssh 9.3p2's `allowed_user()` (auth.c) calls
  `platform_locked_account()` whenever `UsePAM` is off — it is — and a true
  answer denies **every** authentication method, public keys included.
  `platform.c` decides that from three optional macros and this build's
  `config.h` defines exactly one: `LOCKED_PASSWD_PREFIX "!"`;
  `LOCKED_PASSWD_STRING` and `LOCKED_PASSWD_SUBSTR` are `#undef`. So `*`
  disables password login and leaves key auth working, while `!` — the value
  `passwd -l` writes and the one a reasonable person would reach for — would
  have denied key auth on an image with no console, leaving reflash as the only
  way in. The guard now **fails the build** on `!` and says why, mutation-tested
  in both directions.

  **Documentation reconciled the same day.** Eight documents described serial
  console access: both Annex II fact sheets (platform-interface table row and
  the whole root-password section, plus the "physical access is equivalent to
  full control" assumption, which was stale in both halves), both user manuals,
  both quick-starts, and media-gateway's installation and production-build
  guides. The load-bearing one was satisfaction of first-use trust —
  satisfaction User Manual §2.1 made the serial console step 1 of verifying a
  self-signed certificate fingerprint, and that path no longer exists. It is
  replaced by commissioning over a **direct Ethernet connection**, which was
  already documented as the alternative and is now the only out-of-band path a
  customer has: SSH cannot serve here, both because it is a vendor-only
  interface and because its host key is itself unverified on first contact
  (Finding A). On-device Help and the customer PDFs were regenerated from the
  corrected Markdown in both trees.

  **CONFIRMED ON HARDWARE 2026-08-19/20.** Proven in two stages, deliberately,
  because the failure mode is unrecoverable. First a pre-flight on the running
  2026.08.6, where the getty was still present as a fallback: `/etc/shadow`
  edited to `root:*` in place and a *second*, independent SSH session opened —
  it authenticated. Only then was 2026.08.7 built, uploaded and applied through
  the A/B updater (`"order":"newer","downgrade":false` — no phrase, correctly
  frictionless) and the unit rebooted into the new slot. It came back reporting
  `rootfs 2026.08.7`, `root:*`, no getty line in `/etc/inittab` and zero getty
  processes — over a key-authenticated SSH session, which is the assertion
  itself. Row #4's "one short shared value" residual is closed: there is no
  shared password on the unit at all.


- **2026-08-19 (late) — Annex I #7: the SWUpdate verification plan is complete,
  10 of 10, and the roll-up was wrong about how much of it was left.**

  Two things closed. The **`order=unknown` refusal**, which was the last
  genuinely untested item: a package that is correctly DEV-signed, whose payload
  matches its manifest, and whose declared version is `1.0.0` — what a build
  from before release numbering looks like. It verifies, and is then refused by
  the layer *after* verification, with a message that admits the unit cannot
  order it rather than guessing, and an audit record saying
  `reason=downgrade_unconfirmed order=unknown from=2026.08.9 to=1.0.0`. The rule
  it proves is that `unknown` counts as needing confirmation rather than as
  safe: a gate that silently allowed what it could not order would be bypassed
  by the oldest packages in existence, which are precisely the ones an advisory
  concerns. The artifact is reproducible per release —
  `scripts/compliance/make-negative-swu.sh` now builds it alongside the three
  corruption packages, because a negative test built from a different release
  proves nothing about the one on the bench.

  And **item 8d, which claimed six passing hardware tests were still open.** The
  correction is above; what belongs here is why it is worth an entry of its own.
  Every other stale-document finding in this programme has been an overclaim, and
  the discipline built around them — cite the evidence, prefer the bench, treat a
  documented control as unproven until executed — is all aimed in that direction.
  This one pointed the other way and the discipline did not catch it: the gates
  check that claims are true, not that they are current, and no gate anywhere
  asks whether a document *understates* what has been done. It cost a bench
  session that was about to re-run six passing tests and was caught by the
  operator remembering, which is not a control.

  The cheap structural fix is not another gate but a convention: the swupdate
  plan owns its verification results, and the compliance plan should cite that
  table rather than paraphrase it. Item 8d paraphrased, and the paraphrase went
  stale while the table stayed right. **Where two documents describe the same
  evidence, one of them is going to be wrong eventually, and it will be the copy.**


## Remaining work (refreshed 2026-08-16 against both trees and `main` on each)

The documentation/build items (SBOM, compliance matrices, Annex II fact sheets) and
gap items 4c/4d/4e are closed above. What is actually left, deadline item first:

1. **Disclosure channel** — *deadline-bound: reporting obligations start 11 Sep 2026,
   **~3.5 weeks out**, and apply to already-shipped units.* **Engineering half done
   2026-08-09** (see the dated entry above): `security@joralllc.com` is documented
   in both manuals, the on-device Help, the customer PDFs and each tree's
   `SECURITY.md`.

   **2026-08-18 — the publishable artifacts now exist too**, so nothing on this
   row is waiting on engineering. [`disclosure/`](disclosure/) holds a
   ready-to-upload RFC 9116 `security.txt` and the public, product-neutral
   `security-policy.md` the `Policy:` field names, plus a four-step publication
   runbook. `scripts/compliance/test-security-txt.sh` validates them (16 checks,
   six mutations each confirmed to fail it: a lapsed expiry, an expiry inside the
   renewal margin, an address that drifts from what the devices ship, a typo'd
   field name, an `Encryption:` line promising a key nobody holds, and a
   plaintext `http://` URI).

   Two things that guard the long term rather than the deadline. RFC 9116 makes
   `Expires` mandatory and a lapsed file **invalid**, with nothing to announce
   it — so the check fails **60 days early**, while re-issuing is a chore rather
   than an incident. And it fails if the address in `security.txt` ever stops
   matching all six shipped surfaces (both `SECURITY.md`, both manuals, both
   on-device Helps), which is the realistic decay here: a unit in the field
   carries whichever address it was built with, forever.

   **What is left is not ours, and the order matters:** create the
   `security@joralllc.com` Workspace group first (product management + at least
   one engineer; `psirt@` aliased in), *then* publish the two files, *then*
   verify from outside with `--live`. Publishing before the mailbox exists is
   worse than publishing nothing — a researcher who mails a dead address
   concludes we do not answer, and what they do next is publish. The row stays
   **partial** until mail to the address is actually received; a row that read
   "met" on the strength of a written policy would be the same failure this
   programme keeps finding. The docs must not ship to customers before then.

   The two firmware-update decisions (4b) — **signing-key custody** and the
   **declared support period** — are a ready-to-sign memo:
   `firmware-signing-and-support-policy.md` (2026-08-14; offline two-key
   ceremony with a compromise runbook, 5-year support period with a published
   end date). What
   Carl owes is a signature and one hour for the key ceremony — raise it in the
   same conversation as the mailbox. It is one meeting, not three.
2. ~~**Attack surface (4a)**~~ — **done 2026-08-08 and 2026-08-10.** telnetd, adbd
   and Samba are out of the image and root SSH login is key-only (08-08);
   `S40bluetoothd`, `S30dbus`, `S99hciinit`, the `S99python` root-execution boot
   hook and 118 unused packages are out (08-10). *(This sentence read "the root
   password itself is unchanged — still `luckfox`" until 2026-08-18, four
   paragraphs above the text recording that it changed on 08-16. Corrected: the
   value changed, see below.)* **The firewall gap closed 2026-08-12
   and is bench-confirmed on a flashed unit** (default-deny IPv4 + IPv6
   rulesets in the board overlay; rules loaded, blocked-port probe refused,
   services verified through the filter — see the dated entry above), and the
   `wifi_app` binaries are dropped from the build and confirmed absent from
   the flashed image the same day (5e). **The uid-1000 image ownership problem
   is fixed 2026-08-15 and bench-confirmed 2026-08-16** (see the dated entry
   below): every packed ext4 image now carries root-owned inodes, the build
   fails rather than ship one that does not, and `StrictModes no` is out of
   `sshd_config`. **Confirmed on hardware 2026-08-16** — uid 0 / gid 0 on a
   unit, and key auth working with StrictModes at its default. **The root
   password value changed 2026-08-16** (see the dated entry above): off the
   *published* Luckfox default, `$1$` MD5-crypt → `$6$` SHA-512, absent from
   every customer-facing document, and guarded by
   `scripts/compliance/test-root-credential.sh` — which also fixed the
   documents' long-standing mis-citation of the defconfig as the effective
   source (the board overlay's `/etc/shadow` is). What is left on this row:
   **root CGIs**; a **serial-console login on hardware** to prove the `$6$`
   path; and ~~the standing product decision between one shared value, locking
   the account (which costs the documented serial-console recovery) and minting
   a per-unit password the console can surface~~ — **decided 2026-08-19: the
   account is LOCKED and the serial getty is removed.** The cost that had
   blocked locking was the documented serial-console recovery, and the product
   decision withdrew that recovery, so the option became free. What is left on
   this row is **root CGIs** and the bench leg proving key-auth SSH still works
   against a locked account (item 8, new leg).
3. **Secure defaults (row #1)** — **closed on both products** *(text reconciled
   2026-08-12 — this item had gone stale against action-plan items 4g/4h)*:
   SatiSense ships `signencrypt` + `web.tls: true` (2026-08-08), the
   media-gateway console runs HTTPS on 443 with a per-unit certificate
   (2026-08-09, 4h), and the `admin`/`joral` credential buys only a forced
   password change on both products (2026-08-09, 4g). Residual, not blocking:
   first-use trust rests on self-signed fingerprints (documented out-of-band
   check). **Disabling anonymous OPC UA sessions was the one unlocked product
   decision here, and it was taken on 2026-08-19** — see the dated entry
   below; what it still owes is a bench leg, not a decision.
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
      fell to version/build facts; wget CVE-2024-38428 was the one *expiring*
      accepted-risk — **resolved 2026-08-16 by dropping GNU wget from the
      build** (see the dated entry above; both wget triage rows retired);
      dhcpcd was filed `fixed-pending-release` via `ipv4only` and is
      **`not-affected` since 2026-08-19** (the label was wrong, not the
      reasoning). First remaining expiries 2026-11, and they are now the
      five python3 rows alone.
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
7. ~~**Media-gateway loose ends from the matrix work**~~ — **both halves closed.**
   ~~no LICENSE file / SPDX headers~~ — **done 2026-08-16**: **MPL-2.0**, the
   licence Joral already publishes for satisense-edge, with the same `LICENSE`
   text, SPDX + copyright headers on all 42 first-party files, and
   `app-manifest.csv` moving from UNDECLARED to MPL-2.0 — the SBOM no longer
   describes our own components as unlicensed (verified in the 2026-08-16
   regeneration: 52 platform + 8 application components, zero UNDECLARED). The
   same pass found and corrected **87 satisense-edge files tagged `GPL-2.0+`**
   against that tree's own MPL-2.0 LICENSE and SBOM entry. **Carl's
   confirmation came back on 2026-08-19 and reversed the determination** — the
   outbound licence is now **proprietary (`LicenseRef-Joral-Proprietary`)**,
   with `LICENSE` + `EULA.md` in both trees, and the reversal cost the one
   substitution this row predicted. See the dated entry above for the reasoning
   and for what it exposed: **no CRA requirement pointed either way** (the
   Regulation asks for an SBOM in the technical file, never for published
   source), MPL-2.0 would have obliged us to hand each customer the source of
   both daemons and both consoles under §3.2, and open62541 never required it
   because MPL is file-level. Nothing engineering-side is left on this row.
   **What is owed is legal and administrative:** counsel review of `EULA.md`,
   the `[[JURISDICTION]]` placeholder in its §12, and confirmation that
   `support@joralllc.com` — the address its §7 written source offer sends
   people to — actually exists. That last one is item 1's failure mode
   repeating, and it should go in the same conversation as the mailbox. The
   open list, with owners and acceptance criteria, is
   [`outbound-licence-plan.md`](outbound-licence-plan.md).
   ~~and no test coverage of the auth layer, CGIs,
   config writer or listeners~~ — **the coverage half is done 2026-08-15** (see
   the dated entry above): four suites, 200+ checks, mutation-verified, in
   `make test`; one console-denial defect in `config.sh` found and fixed, and
   three stale source citations in the Annex II fact sheet corrected.
   ~~plus the same coverage for satisense-edge's own copy of the auth layer~~ —
   **carried across the same day** (satisense-edge #56, ~140 checks,
   19 mutations): its vendored `webauth.sh` had all the same guards already
   present, so nothing was missing there except the coverage.
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
   secret-free `gateway.json`, sentinel-only over the API).
   **TC-S3 leg c (MQTT TLS) was executed 2026-08-12/13** — see the dated entry
   above: TLS 1.3 confirmed, certificate verification proven enforced on both
   trust paths, and a pre-existing keepalive defect found, fixed, guarded by a
   test that fails against the old code, and bench-confirmed.
   **2026-08-16 closed two more legs** (`bench-backlog-runbook.md` legs 3 and 4,
   and leg 1 in passing): a unit taken to **2026.08.2 through the A/B updater**
   — not a reflash, so the change travelled the way a customer's would —
   reports uid 0 / gid 0 on `/`, `/etc` and `/etc/ssh` and accepts a fresh
   key-authenticated SSH session with `StrictModes` at its **default**. That is
   the whole of `image-ownership-and-ssh-key-plan.md` Part 1.
   **The 2026-08-19/20 session closed four of the seven** — legs a, c, f and
   the substantive half of e; see the dated entry above for the evidence and
   for the four findings and three corrections they produced. **A fifth, leg d,
   turned out to have been closed on 2026-08-14 all along** — this document
   said otherwise for five days (see 5d below). It also created one new leg,
   and closed that too.

   **Two legs remain, and neither blocks anything:**
   - **b — MQTT mutual TLS**, which needs a broker whose authentication we
     control. The only leg still requiring equipment we do not have set up.
   - **g — the encoder-sim replay.** It no longer gates anything: it existed
     because the python3 removal waited on it, and that removal was reversed on
     2026-08-19 in favour of a version bump, so the interpreter stays and
     `encoder-sim.py` runs on the device as before. Worth doing to prove the
     candump-log path works on hardware, but it is a control on a tool rather
     than on the product.

   *(Per-leg detail, kept as written:)*
   - ~~a. the downgrade refusal~~ — **CLOSED 2026-08-19**, both outcomes
     audited with the version transition in each record;
   - ~~c. media-gateway durable audit~~ — **CLOSED 2026-08-19**, the failed
     login and stunnel's peer line joined in the same second, surviving a
     reboot;
   - ~~e. secrets at rest~~ — **CLOSED 2026-08-19** (`mode:encrypted`,
     both binding sources read off real hardware). Its other half, the `$6$`
     serial login, is **withdrawn** rather than outstanding: the product
     decision of the same day removes the getty and locks the account;
   - ~~f. the OPC UA identity change~~ — **CLOSED 2026-08-19**, refused and
     admitted on a board with the channel and identity layers separated;
   - ~~**NEW — key-authenticated SSH against a locked root account and no
     getty**~~ — **CLOSED 2026-08-19/20 on release 2026.08.7**, delivered
     through the A/B updater and preceded by a pre-flight on the outgoing
     release while a getty was still available. See the dated entry.

   *(Superseded leg text, kept for the record:)*
   a. **the downgrade refusal** (runbook §6) — the gate has never run on
      hardware; the 08-15 session staged `same`, which is correctly frictionless
      and proves only the other half. Evidence to cite is the CGI driven with
      `curl`, plus the `fw_apply refused … from=/to=/order=` audit line;
   b. **MQTT mutual TLS and credentials-in-channel** (mqtt-tls-bench-runbook
      §2–§5) — needs a broker whose authentication we control;
   c. **media-gateway durable-audit spot-check** and a failed-login record
      correlated against stunnel's peer line (the peer line itself is confirmed
      present on a running unit);
   d. ~~**SWUpdate negative and fault paths**~~ — **THIS ROW WAS WRONG, and
      corrected 2026-08-19.** It said the tampered-payload, tampered-signature
      and wrong-key packages were "built and *host*-verified only" and that
      power-cut, broken-slot and factory-reset "have not been run at all". All
      six had **passed on hardware on 2026-08-14** and are recorded in
      `swupdate-implementation-plan.md`'s own bench-results table (items 3, 4,
      6, 7, 9), five days before this row was last refreshed. Highlights worth
      keeping visible here rather than only in that document: the power cut at
      ~50% of a write left the target slot **never armed**, because
      `mark-active` only runs on a clean swupdate exit; and the deliberately
      broken slot fell back **in one boot, not seven** — the initramfs failed
      the mount and set `priority=0 bootable=no` rather than burning through
      `tries_remaining`.

      **The correction matters more than the row.** Every other stale-document
      finding in this programme has been an *overclaim* — a control described
      as working that was not. This is the opposite, and it is not harmless: it
      cost a bench session that was about to re-run six passing tests, and it
      was caught by the operator remembering, not by any gate. A roll-up that
      undercounts completed work is still a roll-up that cannot be trusted, and
      the same reading that treats an overclaim as serious has to treat this as
      serious. What is genuinely left of the swupdate verification list is the
      one sub-case named under item 5 below.
   f. **The 2026-08-19 OPC UA identity change, not yet on a unit** (ADR-151):
      a factory-configured unit must refuse every session with
      `BadIdentityTokenInvalid` until a username/password is set; setting one
      must let a *pinned* client in and still refuse anonymous; and blanking
      `trust_path` must refuse anonymous on its own. Diagnostics must report
      `sessions_possible: false` and the reason. The policy is host-tested and
      mutation-checked, but the assertion that matters — an OPC UA client is
      actually turned away — has only ever been made by a test harness.
   g. **The encoder-sim replay path** — one `canplayer -I walk.log` on a unit
      with the console showing `j1939.encoder.*` moving as it does under the
      live simulator. Ten minutes, and it is what the staged python3 removal
      waits on: the host half is proven (see the dated entry above), the
      hardware half is the difference between a control and a claim, same as
      legs e and f.
   e. **The 2026-08-16 product-decision changes, none of them yet on a unit:**
      a serial-console login with the new root password (the `$6$` hash path
      through busybox `login`, never exercised on hardware), and
      `secrets_at_rest.mode = encrypted` in `diagnostics.json` on a flashed
      unit — the binding sources are in the kernel config but have never been
      **read** on a board, and the host suite fakes them. Both are one-line
      checks on the next flash; both are the difference between a control and a
      claim.
9. ~~**Secrets at rest**~~ — **implemented 2026-08-16** (see the dated entry
   above): AES-256-GCM over the 0600 sidecar, keyed by HKDF-SHA256 over this
   board's SoC OTP + eMMC CID, so the stored bytes are inert on any other unit.
   45 checks across two suites, five mutations of the shipped module each
   confirmed to fail it. What the row now says, and must keep saying, is the
   *scope*: it protects the file once it leaves the device, **not** a running
   unit against root — this platform has no secure element and no design here
   can change that. **Owed: a flashed unit reporting `encrypted`** (item 8e).
10. ~~**Recover two orphaned commits from 2026-08-12**~~ — **both recovered
    2026-08-18**, and the gate that would have caught them now exists.
    - **media-gateway** `50ec9b9` (was 1a7bd8e) — UDP peer attribution on the
      CAN path, the last gap on Annex I #6 for that product, with its 17 tests.
      **Row #6 is met on both products on both transports** — this time the
      claim is checkable, which is the whole difference from the 08-12 version
      of this sentence. Cherry-picking it shifted `can_gw.c` by 93 lines and
      `test_listeners.sh` failed on the two compliance citations of `:565`,
      now `:658` — the second time in three days that suite has caught a stale
      citation that review did not.
    - **satisense-edge** `dde13e3` (was d4cfaa2) — the operator documentation
      for the firewall (user manual §12.3 + a §13.1 troubleshooting row),
      regenerated into the on-device Help and the customer PDFs. The manual
      described a network behaviour the product no longer had for six days.
      Resolving it against the current tree kept HEAD's Annex rows, which have
      advanced since 08-12, and took only the §12.3 → §12.4 renumbering the
      commit itself causes.

    **The ancestry check is now a release gate**, not a habit:
    `scripts/compliance/check-cited-commits.sh`, wired as **`./build.sh
    cited`** and first in the release procedure because it needs no build. It
    asks three questions, and the middle one is the one a habit would have
    missed: did the cited commit **land** (ancestor of its repo's default
    branch), does it **ship** (ancestor of the submodule revision this tree
    pins), and is the **pin itself** on a default branch. A commit can be
    merged and still not be in the release because nobody bumped the pointer —
    which is the ordinary last step of every submodule PR, and therefore the
    one most likely to be skipped. Validated by running it against the tree as
    it stood before this item: it reported exactly the two orphans and nothing
    else.

    It also establishes a convention worth keeping: **in a compliance document
    a backticked SHA is a claim that the commit ships.** A SHA mentioned as
    history goes in plain prose — which is why the two orphan SHAs above are
    unbackticked, and why the 2026-08-16 correction entry was rewritten the
    same way. Backticks are the assertion; the gate is what makes the assertion
    cost something.
11. **Update-mechanism residuals (row #7, 4b)** — *narrowed 2026-08-19, see the
    dated entry.* Three were owed, in order. The first is done:
    - ~~**Freeze the partition layout**~~ — **FROZEN 2026-08-19**, one-way door
      #1 closed, deliberately ahead of the key ceremony: a unit shipped on a
      wrong layout cannot be corrected by any update, whereas a DEV-keyed trust
      store fails closed. The table did not change (it has been the `-IPC-AB`
      profile's since 2026-08-14, spike-closed on hardware the same day, and
      two releases were delivered onto it); what was added is what makes it
      hold — `scripts/compliance/check-partition-layout.sh`, wired as
      **`./build.sh partitions`**, asserting all six consumers and the
      structural invariants against its own copy of the string, and verified by
      injecting drift rather than by passing. It also caught the plan document
      specifying four partitions that no unit has ever carried, and a dead
      `emmc_fstab` that three documents listed as a step of the A/B change.
    - **Hold the key ceremony** so builds stop signing with the per-checkout
      DEV key — **no customer shipment on a DEV-keyed trust store**. This is
      one-way door #2 and it is now the only pre-ship engineering blocker in
      this item. Carl's hour; procedure and compromise runbook are drafted and
      ready to sign in `firmware-signing-and-support-policy.md`.
    - **Run the negative/fault legs in item 8d.** A bench session.
12. ~~**Diagnosability defects filed but not fixed**~~ — **both fixed
    2026-08-16** (see the dated entry above): the SatiSense daemon now writes
    `/var/log/intelligence-edge.log` itself (`core/logfile.c`, 1 MB cap + one
    `.old`, `tests/test_logfile.c` in `make test`; media-gateway checked —
    not affected, its daemon syslogs), and the board overlay's `dhcpcd.conf`
    carries `denyinterfaces can*`. **All three bench-confirmed 2026-08-16 on
    release 2026.08.3 delivered through the A/B updater** (see the dated
    entry): the daemon log shows startup lines where 0 bytes used to be, GNU
    wget is gone from the running rootfs, and `/var/log/messages` carries no
    `can0` line while dhcpcd is demonstrably alive on `usb0` and `can0`
    stays `UP mtu 16`. Nothing owed on this item.
13. **Other board configs** — *narrowed 2026-08-19, see the dated entry.* The
    ext4 half is done and **bench-confirmed 2026-08-19 on release 2026.08.4
    delivered through the A/B updater** (see the dated entry): all **26 ext4
    partitions across the 11 boards that use `mkfs_ext4.sh`** pack clean and
    root-owned at their own geometry, a unit reports no non-root inode anywhere
    on `/`, one real `./build.sh firmware` ran end to end on the single-slot
    Ultra layout, and
    the packer's own verification was rebuilt to be independent of the list it
    applies and put behind `test-image-ownership.sh`. Three things are left, in
    order of what would block a shipment:
    - **The other 14 configs are un-hardened stock BSP profiles** — no
      `luckfox-hardening-post.sh`, four with `RK_ENABLE_WIFI=y`, and
      `luckfox_pico_defconfig` still carrying `BR2_PACKAGE_WGET=y`. Any of them
      would have to be brought up to the Ultra profile before an image built
      from it could ship, which is a larger job than a build pass.
    - **ubifs still packs build-user ownership** and cannot be fully fixed with
      the bundled mtd-utils 2.0.1: `--squash-uids` leaves the root inode at uid
      1000 and the device table refuses `/`. Blocks any SPI_NAND profile.
      (erofs was fixed and measured on 08-19; ext4 on 08-15.)
    - **No boot pass**, and none is possible for 15 of the 16 configs without
      the boards. The nine `luckfox_pico_defconfig` boards also have their
      tree-content half unverified, since that defconfig has never been built
      here.
14. **SatiSense: a root daemon's library path lives on the one partition the
    updater cannot write** (found 2026-08-19 on the bench, see the dated entry).
    `intelligence_edge_opcua` needs `librknnmrt.so`, which ships only in `oem`;
    `S60intelligence-edge` therefore exports
    `LD_LIBRARY_PATH=/oem/usr/lib:/oem/lib` to the daemon and to every console
    CGI. `oem` is single-copy and absent from the `.swu` payload, so it still
    carries build-user ownership — measured `drwxrwxr-x 1000 1000` on a unit
    updated to 2026.08.4 — and no update can change that. Three parts, and the
    first is the one that removes the class of problem:
    - ~~**Move the 190 KB library into the rootfs and drop the `/oem` search
      path**~~ — **done and bench-confirmed 2026-08-19 on release 2026.08.5**:
      `ldd` on the unit resolves all thirteen of the daemon's libraries inside
      the rootfs, none under `/oem`.
    - ~~`/etc/profile.d/RkEnv.sh` prepends `/oem/usr/lib:/oem/lib` to
      `LD_LIBRARY_PATH` for **interactive login shells**~~ — **removed in
      `luckfox-hardening-post.sh`, shipped in release 2026.08.6**, verified
      absent from the packed image (`/etc/profile.d` now holds only
      `enable_coredump.sh` and `umask.sh`). Its one consumer, the BSP's
      `S60micinit`, was already a permanent no-op — everything it does is
      guarded by `command -v amixer`, and `amixer` is in neither the rootfs nor
      `oem`. **Bench-confirmed 2026-08-19 on 2026.08.6** delivered through the
      A/B updater (slot b, `last_boot=b`, both slots bootable and successful).
    - ~~**Say it in the Annex II fact sheet.**~~ **Done 2026-08-19** in both
      trees: units flashed before 2026-08-15 keep a build-user-owned `oem`
      permanently and only a reflash clears it, stated next to the existing
      pre-2026-08-12 firewall caveat.
    - **Reconsider `RK_BUILD_APP_TO_OEM_PARTITION=y`**, which is also putting a
      stale divergent copy of the console (different `assets/index-*` bundle,
      differing `cgi-bin/*.sh`) on `oem` where nothing serves it. Dead code on a
      device is evidence that has to be explained.

15. **The four findings from the 2026-08-19/20 bench session** (see the dated
    entry above for how each was found). None was visible in a code read; three
    of the four are upgrade-path defects, which is the class this programme has
    least coverage of because every host test starts from a clean tree.
    - ~~**A — SSH host keys live on the rootfs slot.**~~ **FIXED 2026-08-20,
      awaiting one bench leg.** `S50sshd` ran `ssh-keygen -A` into `/etc/ssh`,
      which Phase 0 never moved, so every update minted a new identity and each
      slot kept its own. The keys now live in `/userdata/platform/ssh` — a
      platform path, not a per-product one, since sshd is shared — and
      `/etc/ssh` holds symlinks to them.

      **Symlinks rather than `sshd_config` `HostKey` lines**, because
      `ssh-keygen -A` decides what to generate by testing the *default* paths:
      a symlink to an existing key reads as present, so `-A` generates only
      genuinely missing types and can never overwrite an identity. The sequence
      is **adopt → link → generate → adopt → link**; the second pass captures
      anything `-A` just created (a newly supported key type after an openssl
      or openssh bump) rather than letting it live on the slot.

      **The degraded case is the one that would have looked like success.** The
      `/userdata` mountpoint *directory* exists on the rootfs whether or not
      `S20linkmount` worked, so a naive existence test would write the keys into
      an unmounted mountpoint — persisting them onto the slot again while
      reporting success. Production gates on `/proc/mounts` and reports the
      degraded case to syslog.

      **Stated limit, because operators will see it:** the update that first
      carries this script cannot recover the identity the unit had before it —
      those keys are in the *other* slot's `/etc/ssh`, on a partition that boot
      has not mounted. So identity changes **one more time, on this update
      only**, and is stable from then on. Reading the standby slot to rescue it
      was considered and rejected: mounting it during early boot adds a failure
      path to every boot forever, to serve a migration that happens once.

      Guarded by `scripts/compliance/test-ssh-host-persistence.sh`, which drives
      the shipped script through a `persist-keys` entry point and an
      `$SSHD_STATE_ROOT` prefix rather than reimplementing it — 11 checks, six
      mutations of the shipped logic each confirmed to fail it (adopt loop
      removed, symlink replaced by a copy, target made relative, mount gate
      weakened to a directory test, restore moved after `-A`, private-key mode
      loosened). **BENCH-CONFIRMED 2026-08-19 on release 2026.08.9**, as a
      two-boot test, because only the second boot proves anything.

      *Boot 1* (08.9 installed to the standby slot): `ssh-keygen -A` generated
      into `/etc/ssh`, the second persist pass moved all six files to
      `/userdata/platform/ssh` and linked them back — private keys 0600, public
      0644, directory 0700 — and the degraded-mode syslog line was absent, so
      `/userdata` was a real mount and nothing persisted onto the slot.

      *Boot 2* (the **same** release installed again, so the other slot comes up
      with a rootfs that has never held a host key — the condition every future
      update creates): `last_boot` flipped b → a, the symlinks were re-created
      on that boot (mtime 18:36 against boot 1's 18:13), the three fingerprints
      were byte-identical to boot 1's, and the client connected **with no
      warning of any kind**. That is the whole claim: a fresh rootfs on a
      different slot carrying the same host identity.

      **The first attempt at boot 2 read as a pass and was not**, which is worth
      recording because the tell was subtle. The dumps were taken without the
      second install having happened, so they described boot 1 three times over
      and the fingerprint comparison compared a boot against itself. Two things
      exposed it: `misc_ab status` was byte-identical (`last_boot=b` both
      times), and so were the symlink mtimes — and `ln -sf` re-runs on every
      boot, so an unchanged mtime means no boot occurred. Both are now part of
      the leg rather than the fingerprints alone: a test whose evidence can be
      produced by doing nothing needs a check that doing nothing fails.
    - ~~**B — an updated unit keeps pre-Phase-0 paths forever.**~~ **FIXED
      2026-08-19** (satisense-edge#65), and the fix is larger than the entry
      predicted. `config_load()` flags the old prefix and the daemon acts on it
      once at startup, in the same shape as the plaintext-secret migration —
      but **the files move, not just the paths**. Rewriting a path alone would
      point the daemon at nothing, `certgen` would mint a fresh server
      certificate, and every client that pinned the old fingerprint would fail:
      a silent data-loss bug turned into a loud outage. Copy-then-unlink,
      because rootfs and `/userdata` are different filesystems and `rename(2)`
      returns `EXDEV`; the config is not rewritten unless the move succeeded,
      so an interruption simply retries next boot. 15 checks, mutation-verified.
      **BENCH-RUN 2026-08-19/20 on release 2026.08.11, and it FAILED the
      assertion it was given — correctly, because the assertion was wrong.**
      The mechanism worked: `moved 3 path(s) off the rootfs`,
      `/etc/intelligence-edge` emptied, config rewritten. The certificate
      fingerprint changed anyway (`32:70:94:9F…` → `BB:87:73:98…`) and UaExpert
      had to re-trust the server, which the operator confirmed.

      **Structural, not a coding defect.** The migration runs on the first boot
      of the NEW slot. The files it was meant to rescue are on the OTHER slot's
      rootfs, which that boot never mounts — so `S60`'s `prepare_opcua_cert`
      found nothing at the configured `/etc` path, minted a fresh certificate,
      and the daemon dutifully migrated *that*. A unit cannot reach back into a
      partition it has already replaced.

      **This is the same limit finding A carries, written out there and not
      applied here.** Finding A's entry says plainly that the delivering update
      cannot recover the prior identity because the keys are on the other slot.
      The identical argument applies to B; instead the commit message and PR
      claimed the fix spares clients from re-pinning. Corrected in `config.h`,
      the test header and here (satisense-edge#66). The lesson is narrow and
      worth keeping: **an argument already written down for one case is not
      automatically carried to the next**, and the bench caught the omission
      that review did not.

      What the fix genuinely buys: **every subsequent update is safe**, since
      the paths then name `/userdata`. Reaching into the standby slot to rescue
      the originals stays rejected for finding A's reason — a failure path on
      every boot forever, to serve a migration that happens once per unit.

      **An ordering defect the run also exposed, now fixed** (satisense-edge#66):
      `S60` generated the certificate before the daemon migrated anything, so
      freshly minted private key material was created ON the rootfs and moved a
      moment later. `S60` now calls `--migrate-paths` before `start_web` and
      `prepare_opcua_cert`. Two ordering checks, mutation-verified.

      **CLOSED 2026-08-20 on release 2026.08.12**, in the form the fix actually
      supports. A unit already migrated (2026.08.11, paths on `/userdata`,
      fingerprint `BB:87:73:98…`) was updated again: the fingerprint was
      **unchanged** and no `moved N path(s)` line appeared, because there was
      nothing left to move. Every update after the delivering one preserves the
      server certificate, which is the whole of what the fix buys and now the
      whole of what it claims.

      *Scope of that evidence, because the first draft of this paragraph
      over-reached and the correction is the useful part.* It asserted that the
      OPC UA client "reconnected without re-trusting". A trust prompt WAS
      raised after the 08.12 update, and the explanation is benign: the
      operator had observed the 08.11 fingerprint change without ever accepting
      the new certificate, so 08.12 was simply the first time that certificate
      was presented to a client. Nothing about the update caused it.

      **What this leaves genuinely undone is the client-side half of the
      claim.** At no point in this programme has a client with an *accepted*
      certificate been carried across an update, so "a pinned client reconnects
      silently" remains reasoning from the device-side fingerprint rather than
      an observation. The device-side evidence is complete and is what row #7
      should cite; the client-side demonstration is cheap to arrange and has
      simply never been set up — accept the current certificate in the client,
      complete a session, then update and reconnect. Worth doing before the
      claim is made to anyone outside engineering.

      **The ordering fix is confirmed too, and the assertion was sharp:** the
      pre-state was reconstructed (files on the rootfs, config naming `/etc`)
      and the release reinstalled. Afterwards `/etc/intelligence-edge` **did not
      exist at all** — where the 2026.08.11 run left it existing but empty,
      because `S60` had created it minting a key there before the daemon moved
      it out. No private key touches the rootfs at any point now, not even for
      one boot. The absent `moved N path(s)` line in the daemon log is itself
      the evidence: the daemon routes its stdout to that file, so its own
      migration branch demonstrably did not run — `--migrate-paths` had already
      done the work from the init script, which is exactly the ordering the fix
      introduces.
    - ~~**C — the TLS readiness probe accepts any listener, on satisense.**~~
      **WITHDRAWN 2026-08-19: there is no such defect, and this entry was
      wrong.** Both halves it said to port were already present. `start_web`
      has used `--cert-check` — validity, not existence — since the console-TLS
      work, and the predicate is the same three-part check media-gateway uses:
      `pid_alive $HTTPD_PID && pid_alive $STUNNEL_PID && web_port_listening`.
      It requires *our own* stunnel to be alive, so it cannot mistake a
      squatter for success.

      What I read as a near-miss —
      `Binding service [web] to 0.0.0.0:8080: Address already in use (98)`
      printed while `S60` reported `(https:8080)` — is stunnel binding the same
      `accept` spec in **both address families**. With `bindv6only=0` (the
      Linux default, confirmed on the unit) the `::` bind is dual-stack and
      already covers IPv4, so the following `0.0.0.0` bind must fail. Disproved
      properly rather than by argument: the service was stopped, `netstat`
      confirmed the port fully released, and a clean start produced the
      identical line while the console came up normally. It also appears for
      media-gateway's `:443` on every boot. Routine, both products, always.

      **What IS true, and is a smaller and different problem:** that benign
      line is *byte-identical* to what a genuine port conflict would print, so
      a real squatter would be invisible in the log — and an error-looking line
      at every start teaches operators to ignore stunnel errors. Same argument
      as finding A, one layer down. Filed as item 16 rather than left inside a
      withdrawn entry, because a correction that quietly becomes a different
      claim is how the original error survives.

      **The lesson is the one this programme keeps paying for, inverted.** The
      finding was written from a log line plus a plausible mechanism, and the
      mechanism was wrong. Reading the two scripts before filing would have
      shown the check was already correct; the two minutes of bench work that
      disproved it would have cost less than the entry did. A defect asserted
      from evidence one has not traced is the same failure as a control claimed
      from a document one has not executed.
    - ~~**D — the `fw_apply success` audit record names no version**~~ —
      **FIXED 2026-08-19** in both trees (satisense-edge#65,
      t1s-media-gateway#41), **and confirmed on hardware 2026-08-20**:
      `fw_apply result=success … from=2026.08.11 to=2026.08.12`. It could not
      be observed before that, and the reason is worth keeping — every earlier
      update was *initiated from* a release predating the fix, so the old CGI
      and worker ran. A fix to the code that performs an update is only visible
      on the update after the one that delivers it, the same shape as finding
      B's limit. The worker now names the transition in the success
      record and in both post-install failures. Passed to it rather than
      re-derived from the staged package, so the `started` and completion
      records cannot disagree about which two releases were involved — a pair
      of audit lines that contradict each other is worse than one that is
      terse.

16. **stunnel logs a benign bind failure that is indistinguishable from a real
    one** (found 2026-08-19 while disproving finding C, see item 15). Both
    products write a bare `accept = <port>`, so stunnel attempts the bind in
    both address families; with `bindv6only=0` the `::` socket already serves
    IPv4 and the `0.0.0.0` attempt necessarily fails with `EADDRINUSE`. The
    console works, and every start logs what reads as an error.

    Two costs, both small and both real. An operator who sees it at every boot
    learns to ignore stunnel errors — the same "cries wolf" problem as the SSH
    host keys, one layer down. And because the benign message is byte-identical
    to a genuine port conflict, the one case where it would matter is the one
    case it cannot be seen in.

    The fix is to attempt one bind rather than two, by naming the address family
    in the `accept` spec — in `S60intelligence-edge`'s generated
    `stunnel-web.conf` and in the equivalent `fprintf` in media-gateway's
    `src/main.c`, which must stay in step. **Verify the syntax against the
    packaged stunnel before changing it**: guessing at it would trade a
    cosmetic log line for a console that does not listen, which is a far worse
    trade than the one it fixes.

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
  they sat in `/usr/bin` unstarted and invisible to the SBOM and the gate.
  **Serial getty and root password, updated 2026-08-19/20** *(this text read
  "the root password remains `luckfox`" until then — stale since 2026-08-16,
  and superseded outright by the change below)*: serial console access is not
  provided on production images, so the getty is **removed from `/etc/inittab`
  by the post-build hook** and the root account ships **locked with `*`**.
  The platform interface list is therefore :22 sshd (key-only) and **no
  interactive console at all** — the serial line still carries kernel output,
  but nothing offers a login on it. Bench-confirmed on 2026.08.7.
  **Firewall (2026-08-12, bench-confirmed on a flashed unit):**
  `/etc/iptables.conf` and `/etc/ip6tables.conf` ship default-deny INPUT
  rulesets (documented service ports only on IPv4; nothing served over IPv6,
  RAs dropped, `dhcpcd` runs `ipv4only`), loaded by an overridden `S35iptables`
  that restores both families and logs a failed restore to syslog. Verified on
  hardware: rules listed, blocked port refused, services reachable, DHCP lease
  acquired. **Units flashed before 2026-08-12 still run unfiltered.**
- Media Gateway, **updated 2026-08-12** *(the ":80 HTTP-only, no TLS option" wording here had gone stale against 4h)*: **:443** web console (HTTPS by default via stunnel since 2026-08-09, per-unit cert, plain-HTTP fallback on the same port; backend on 127.0.0.1:18081 only), **:8001** CAN↔Ethernet UDP-or-TCP (unauthenticated), br0 L2 bridge (T1S↔100BASE-TX) so both are reachable from either medium.
  **Correction (2026-08-06): :8000 is NOT bound.** `can_gw_comm_port` defaults to 8000 but the socket binds `comm_port + 1` only (`src/can_gateway/can_gw.c:565`, `include/media_gateway.h:226-227`). The audit row above and `docs/manual/quick-start.md:83` both overstated the exposure.
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
   b. signed firmware update path — **design decided + Phase 0 implemented
      2026-08-14** (no units in the field yet, so the layout can still be set
      right before first shipment): SWUpdate over an initramfs-driven A/B
      rootfs, no bootloader changes — full plan in
      `swupdate-implementation-plan.md`, status note at its top. Done so far:
      both products' mutable state (config, secrets sidecar, console
      credential, per-unit TLS material, usage state, KB) moved off the
      rootfs to `/userdata/<product>/state/` with first-boot seeding and the
      factory-reset boundary preserving the audit trail (host suites green
      on both, clean cross-build); `media/joral/ab-boot/` staged for the
      bench spike (misc_ab AVB-record tool with 13 contract tests, initramfs
      slot selector, ramdisk FIT, `-AB` board profile). The two gating
      product decisions — **signing-key custody + declared support period**
      — are drafted as a ready-to-sign memo with ceremony procedure and
      compromise runbook (`firmware-signing-and-support-policy.md`,
      2026-08-14): offline two-key ceremony, 5-year support period; the
      direction is adopted, the **physical ceremony/token purchase is
      deferred** (documented in the memo) and builds sign with a
      per-checkout DEV key until it happens — **no customer shipment on a
      DEV-keyed trust store.** **Later the same day the update pipeline
      went software-complete** (see the swupdate plan's status block):
      SWUpdate enabled in buildroot (CMS verification, no webserver, inert
      S80), `S99ab-health`, shared `api-update.sh` + UI panels on both
      consoles (both suites green), and `./build.sh swu` producing a
      signed+verified artifact end-to-end on the DEV key. **The bench spike
      closed on hardware 2026-08-14** (phases a/b/c; the boot-time slot switch
      verified through the real selector) and **the partition layout was
      FROZEN 2026-08-19** — one-way door #1, now gated by `./build.sh
      partitions` (see the dated entry). What is left in this row is door #2:
      the key ceremony, so builds stop signing with the per-checkout DEV key;
   c. ~~factory-reset function (both products)~~ — **done: SatiSense 2026-08-06, media-gateway 2026-08-07**;
   d. ~~security-event logging~~ — **done 2026-08-07, met on both**, with
      CAN-gateway peer identity extended to the **UDP** transport on 2026-08-12
      after review found it covered TCP only while UDP is the shipped default
      (see the correction and its closure above); off-device export deferred,
      see item 5;
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
