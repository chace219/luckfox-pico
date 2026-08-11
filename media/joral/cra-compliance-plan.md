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
   no longer reachable over the network. **What is left on this row: the empty
   `/etc/iptables.conf`** (the firewall restores a 0-byte ruleset, and IPv6 is
   uncovered entirely) — now the largest single item — plus the uid-1000 image
   ownership problem, root CGIs, and the `wifi_app` binaries in 5e.
3. **Secure defaults (row #1)** — **closed for SatiSense Edge 2026-08-08**:
   `opcua.security` ships as `signencrypt` and `web.tls` as `true`, both with
   per-unit certificates minted on first boot. Still open: the default
   `admin`/`joral` console credential on both products, and the media-gateway
   console, which has no TLS option at all and is deliberately unchanged pending
   a comparison against MACH production.
4. **OpenSSL 1.1.1 migration plan (4f)** — none yet. The SBOM now auto-flags the
   EOL component, so closure will be self-verifying.
5. ~~**CVE check as a release gate (row #2)**~~ — **process done 2026-08-09**,
   `./build.sh cve` (see the dated entry above). What the first run leaves open, in
   priority order:
   a. ~~**Trim the BSP defconfig**~~ — **done 2026-08-10**, see the dated entry
      above. 118 packages removed, image rebuilt clean, **100 blocking → 19**,
      zero CISA-KEV. avahi kept as intended (expat only, not glib or python).
      **Still needs the bench pass** (item 8) — the image is verified but not yet
      run on hardware.
   b. **Triage what remains** — the 19 are libopenssl (13, folded into the EOL
      migration in item 4 below), wget (2), busybox, libzlib, libcurl and dhcpcd.
      All are components the products use, so none can be removed; each needs a
      reachability decision or a package bump. Decisions go in
      `scripts/compliance/cve-triage.csv` with a `REVIEW_BY` date. **13 rows
      already recorded 2026-08-10**: expat ×8 (`not-affected`, evidence in the
      avahi source) and python3 ×5 (`accepted-risk`, bench tooling only).
   c. **Close the coverage gap** — 28 components (was 56) have no CPE from any
      source and are reported as NOT CHECKED; resolve with
      `cve-check.py --suggest-cpe`.
   e. **Declare or drop the prebuilt `wifi_app` binaries** — `hostapd`, `dnsmasq`,
      three `wpa_supplicant` variants, `wpa_cli` ×2, `iperf`, `rkwifi_server` and
      3 libraries ship into `/usr/bin` from `project/app/wifi_app/` via
      `build.sh:1424`, outside Buildroot — so the SBOM and the gate are both blind
      to them, and no init script starts them. Either add them to
      `app-manifest.csv` with CPEs so the gate covers them, or stop copying them
      into the rootfs. Found 2026-08-10.
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
8. **Hardware bench session** — *now the highest-value item.* TC-S3 leg c (MQTT
   TLS) has still never run (unblocked 2026-08-05); the secrets-CGI path, factory
   reset and audit-log viewer are validated off-device only. **And as of
   2026-08-10 the image itself is 118 packages lighter**, so this pass must also
   confirm nothing depended on what was removed — boot, console over HTTPS, OPC UA
   Sign&Encrypt, mDNS (`satisense.local` — avahi lost dbus in the trim), CAN, and
   the bench scripts themselves, which are why python3 was kept. A firmware image
   is built and ready to flash (`output/image/update.img`, 2026-08-10).
9. **Secrets at rest** — restricted (0600 sidecar) but not encrypted; accepted for
   now, revisit with the OpenSSL 3 migration.

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
  **Present but not started:** the prebuilt `wifi_app` binaries — `hostapd`,
  `dnsmasq`, `wpa_supplicant` ×3, `wpa_cli` ×2, `iperf`, `rkwifi_server` — sit in
  `/usr/bin` with no init script launching them. No listener, but they are in the
  image and outside the SBOM (item 5e). The root password remains `luckfox`
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
   d. ~~security-event logging~~ — **done 2026-08-07, met on both** (incl. CAN-gateway peer
      identity and a console viewer); off-device export deferred, see item 5;
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
