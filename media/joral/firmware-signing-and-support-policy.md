# Firmware Signing & Support-Period Policy — Decision Memo

*Prepared 2026-08-14 for Carl's sign-off. These are the two product decisions
gating the signing half of the update mechanism (CRA plan item 4b;
engineering design and Phase 0 are done — see
[`swupdate-implementation-plan.md`](swupdate-implementation-plan.md)).
Engineering recommendation adopted by engineering 2026-08-14; **pending
product-management approval.** Once approved, the two "on approval" sections
at the end execute the same week.*

*Status 2026-08-14 (later the same day): direction adopted by engineering +
product; **hardware-token purchase and the physical ceremony are DEFERRED —
documented here as the plan for the period.** Until the ceremony happens,
builds sign with a per-checkout **DEVELOPMENT key** (auto-generated, marked
DEV, never committed); the ceremony's `trusted-certs.pem` replaces it with
no code change. **Gate: no customer shipment on a DEV-signed trust store** —
the ceremony is a hard pre-ship item alongside the partition-layout freeze.*

Scope: both products (Media Gateway, SatiSense Edge) — one platform policy,
because both ride the same rootfs image and update mechanism.

---

## Part A — Signing-key custody

### Decision

Firmware update packages (`.swu`) are signed with an **offline private key
that never touches a networked machine**. No signing key on the build
machine or in CI, and no secure-boot fusing (rejected in the update plan —
irreversible, defends a lower-ranked threat than the update channel).

Rationale in one line: whoever holds this key can put software on every unit
we ever ship, so the key must be harder to steal than any single connected
computer at Joral.

### A.1 The keys

| | |
|---|---|
| Keys | **Two RSA-4096 keypairs**: `joral-fw-2026-a` (active) and `joral-fw-2026-b` (rollover spare) |
| Generated | In ONE ceremony (A.2), never on a networked machine |
| Public halves | Committed to the platform repo; **both** baked into every image as trust anchors (`/etc/swupdate/trusted-certs.pem`, a 2-cert PEM bundle) from the very first shipped unit |
| Private halves | Hardware tokens / encrypted media only (A.3); never copied to disk, never emailed, never in a password manager |
| Spare's job | Key-compromise recovery (A.5). It signs nothing until the day it has to — but because its public half is already trusted fleet-wide, rotating to it is a signed update, not a recall |
| Scope | One platform keyset for both products. Two keysets would double every ceremony for zero security gain — the products share the rootfs and the attacker either way |

### A.2 Generation ceremony (~1 hour, once)

Present: **Carl + one named engineer** (the two passphrase holders).

1. Boot a laptop from a **fresh Linux live-USB, network hardware disabled**
   (airplane mode + no cable). Nothing on this OS persists. Bring
   `scripts/compliance/fw-key-ceremony.sh` on the transfer stick.
2. Run the ceremony script — it generates both keypairs and self-signed
   certificates (20-year cert validity — expiry is managed by the support
   period, not the certificate), builds `trusted-certs.pem`, and emits a
   pre-filled ceremony minute. It refuses to run on a machine with a
   default route.
3. Write each private key to **two hardware tokens** (or, failing tokens,
   two LUKS-encrypted USB sticks): SET 1 → office safe, SET 2 → off-site
   (bank box or equivalent). Four physical items total.
4. Copy the two PUBLIC certificates to a normal USB stick; commit to the
   repo.
5. Record a ceremony minute (date, people, serials of the tokens, sha256 of
   both public certs) — goes in the technical file.
6. Power off the laptop. The live session — and any key material in RAM —
   is gone.

Passphrase: known to **Carl and the named engineer, both** (two people so a
departure or accident never strands the fleet; the same two people can
change it at the next signing).

### A.3 Storage & access rules

- Private keys exist ONLY on the four ceremony items. A signing session
  never copies a key anywhere.
- Safe access: Carl or the named engineer. Every removal/return of a token
  is one line in the signing log (A.4).
- If a token is lost or unaccounted for: treat as suspected compromise —
  run A.5. Losing ONE of a duplicated pair with the passphrase intact is
  recoverable, but the event is still logged and the passphrase changed.

### A.4 Per-release signing procedure (~15 min)

1. Build machine: `./build.sh swu` produces the release `image-<ver>.swu`
   and prints its sha256.
2. Move the `.swu` to the offline laptop (live-USB boot, network off) on a
   USB stick. Verify the sha256 matches what the build printed — this is
   what stops a compromised USB stick or build box swapping the payload.
3. Sign `sw-description` with the ACTIVE key via
   `scripts/compliance/fw-sign.sh sign` (CMS/PKCS#7, the format SWUpdate
   verifies; the script prints the hashes for the signing log). Token never
   leaves the operator's sight.
4. Move the signature back; the build packs the final signed `.swu` and
   verifies it against the in-repo public certs as a release gate
   (`fw-sign.sh verify` — the same check the unit performs; the
   sign→verify→tamper-reject→rogue-key-reject chain was proven end-to-end
   with throwaway keys on 2026-08-14).
5. Append one line to `docs/compliance/signing-log.md` (platform repo):
   date, version, .swu sha256, signer, token serial.

Cadence check: at the current release rate this is minutes per release. If
it ever becomes the bottleneck, the upgrade path is a dedicated signing
station with a YubiHSM holding the SAME keys — no fleet change.

### A.5 Key-compromise runbook

Trigger: token lost/stolen, passphrase suspected leaked, a signature exists
that the log cannot account for, or the offline laptop ran anything but a
fresh live image during a session.

1. **Freeze releases.** No further signing with the suspect key.
2. Build an update whose ONLY change is trust-store rotation:
   `trusted-certs.pem` = {spare cert, new-cert-C}. **Sign it with the
   SPARE** (its first and only job).
3. Ship it as a security update through the normal channel; units that
   apply it no longer trust the compromised key.
4. Hold a new ceremony (A.2) to mint the next spare; the old spare becomes
   the active key.
5. Report per Article 14 if any unit may have installed an unauthorized
   update; record the incident in the technical file.

Residual risk (documented, accepted): units that never apply the rotation
update keep trusting the compromised key. Mitigation: the rotation update
is pushed through the disclosure channel (`security@joralllc.com` list) as
a critical advisory.

---

## Part B — Declared support period

### Decision

**5 years of security support from the date each product model is first
placed on the EU market**, with the concrete end date published in the
Annex II fact sheet, the user manual, and on joralllc.com next to the
security policy. Extension beyond 5 years is a commercial option decided
no later than 12 months before the published end date.

### Why 5 and not 10

- 5 years is the CRA Article 13 floor for a product with a multi-year
  expected use time; declaring less is not defensible for industrial gear.
- We cannot honestly promise 10 today: the kernel/U-Boot are **Rockchip's
  vendor base** (their support window, not ours — the 5098 report-only
  findings in the CVE gate), and the crypto foundation (OpenSSL 3.5 LTS)
  ends 2030-04-08, already committing us to one in-window LTS migration.
  A 10-year promise would stack two or three such migrations plus a
  possible vendor-base move — costs we cannot price yet.
- Extending a published period later is good news and always allowed;
  shortening one is a breach. Start at the floor we are sure of.

### What "security support" commits us to (published wording, B.1)

During the support period Joral will: ship security updates for
vulnerabilities affecting the product per our published severity/timeline
policy (SECURITY.md), maintain the disclosure channel, and publish security
advisories for the product. It does NOT commit to feature updates.

### B.1 Fact-sheet text (goes in both `cra-annex2-facts.md` on approval)

> **Support period:** 5 years of security support from first placement on
> the market of this product model. First placement: `<DATE — set at first
> customer shipment>`. End of support: `<DATE + 5 years>`, published here,
> in the user manual §Support, and at joralllc.com/security. Security
> updates are delivered as signed firmware updates (see §5); the update
> trust store carries a standby signing key so key rotation never requires
> physical access. Extension of the support period, if offered, will be
> announced no later than 12 months before the end date.

### Interaction with the update mechanism

The support period is the window the A/B updater must keep working through.
The pre-ship one-way doors in the update plan (two trusted keys, versioned
`.swu` format, frozen partition layout) are exactly what make this promise
cheap to keep — a v1 unit must still accept a year-5 update.

---

## On approval (same week, engineering)

1. Hold the A.2 ceremony (scripted: `scripts/compliance/fw-key-ceremony.sh`,
   ~1 hour including token copies); commit both public certs; start
   `docs/compliance/signing-log.md`.
2. Drop B.1 text into both fact sheets and manuals (dates blank until first
   shipment).
3. Add the release-gate verification of `.swu` signatures against the
   in-repo certs to `build.sh` (with `sbom` / `cve`).

## Sign-off

| Role | Name | Date | Decision |
|---|---|---|---|
| Product management | Carl | | ☐ approve Part A ☐ approve Part B |
| Engineering | | 2026-08-14 | recommended |
