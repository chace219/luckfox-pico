# Audit log export / forwarding — design plan (deferred)

*Written 2026-08-07, after security-event logging (CRA Annex I Part I §6) landed
on both products. This is the one remaining item on that row and it is
deliberately **not implemented yet** — it needs a product decision on the
delivery model before code. Everything below is engineering input to that
decision.*

Referenced from the Annex I §6 sections of both product matrices
(`docs/compliance/cra-annex1-matrix.md`) and from the action plan in
[`cra-compliance-plan.md`](cra-compliance-plan.md).

## Where we are now

Both products record security events to two destinations:

| Destination | Property |
|---|---|
| syslog via `logger` (`authpriv`) | RAM-only — `/var/log` is a symlink to `/tmp` (tmpfs), so it dies on reboot |
| `/userdata/<product>/audit.log` (0600) | durable: eMMC `/dev/mmcblk0p6`, 256 MB ext4, survives reboot and factory reset. 1 MB × 4 generations ≈ 45k records |

Readable in the console (SatiSense: *Other → Utilities*; media-gateway:
Configuration page) and over serial/SSH. **Nothing leaves the device.**

## Why this is worth doing

Not a nice-to-have; four concrete reasons, strongest first:

1. **The platform can destroy the log without asking.** If `/userdata` fails to
   mount at boot, the vendor's generated `/etc/init.d/S20linkmount` runs
   `mke2fs -F` and **reformats the partition**. That is Rockchip SDK behaviour we
   do not control. An on-device-only trail has a single point of failure that we
   cannot fix in our own code — only a second copy elsewhere fixes it.
2. **History is bounded.** ~45k records is generous for one unit, but a busy site
   or a sustained failed-login campaign will roll generations over. Anything
   older than the window is gone; a collector keeps it.
3. **Incident reporting (from 11 Sep 2026) does not scale by SSH.** Answering
   "which units were touched, when, from where" across a deployed fleet by
   visiting each device is not a process. Annex I Part II §2 (address
   vulnerabilities without delay) has the same problem.
4. **Detection needs aggregation.** One failed login on one unit is noise. The
   same source address failing against twelve units is an incident, and that
   pattern is only visible off-device.

## Requirements (constraints any option must satisfy)

These come from how the products are actually deployed, and from mistakes
already made and corrected in the audit work:

- **R1 — must not touch the data plane.** Same rule the console viewer follows:
  no work in the Modbus poll loop, the OPC UA server, the CAN frame path or the
  bridge. Forwarding runs in a separate process, or not at all.
- **R2 — must never block on the network.** A dead or slow collector must not
  delay a login, wedge a CGI, or stall the daemon. This rules out any design
  where the audit write path performs a synchronous network send.
- **R3 — must not lose records silently.** The existing rule: if the durable
  write fails we emit `audit_persist_failed`. Forwarding needs the equivalent —
  a gap must be visible, and ideally the local copy remains authoritative so a
  network outage is recoverable rather than lossy.
- **R4 — off by default, opt-in.** A device that phones home out of the box
  contradicts Annex I §1 (secure by default) *and* the deployment assumption
  (isolated machine control network). The operator names the collector; nothing
  is sent until they do.
- **R5 — no new secrets on the device.** If the transport needs credentials, they
  go through the existing 0600 secrets sidecar mechanism (SatiSense) — never into
  `gateway.json` / `gateway.conf`. Prefer transports that need no credential.
- **R6 — records stay secret-free.** Already true and test-enforced; forwarding
  must not add anything. Note records *do* contain usernames and client IP
  addresses, so the transport is not "harmless" even though it carries no
  credentials — see the exposure note below.
- **R7 — configured like everything else.** `gateway.json` (SatiSense) /
  `gateway.conf` (media-gateway), editable from the console, validated on save.

## Options

### A. busybox `syslogd -R` remote forwarding — the quick win

**Available today with no build change.** `CONFIG_FEATURE_REMOTE_LOG=y` is
already set in `sysdrv/tools/board/buildroot/busybox.config`, so the running
syslogd can forward. The whole change is a line in `/etc/default/syslogd`:

```sh
SYSLOGD_ARGS="-R 10.0.0.50:514 -L"    # -L keeps the local copy as well
```

| | |
|---|---|
| Effort | ~half a day including console field, validation and docs |
| Satisfies | R1 (separate daemon), R2 (UDP fire-and-forget, never blocks), R4, R7 |
| Fails / weak on | **R3** — UDP with no buffering and no delivery confirmation: records lost during a network outage are simply gone, and nothing notices. No TLS, no authentication, cleartext on the wire (RFC 3164) |
| Side effect | forwards *all* syslog, not just audit records — the daemon's operational logging goes too. Could be a feature (one stream) or noise (collector-side filtering needed) |

Honest summary: cheapest possible, standard, lands in any existing syslog
infrastructure, and materially better than nothing — but it is best-effort
delivery of cleartext over UDP. Good enough for a trusted-network site that just
wants records in its SIEM; not good enough to be the only answer.

### B. `rsyslog` or `syslog-ng` from Buildroot

Both are present as Buildroot packages and **not currently enabled**
(`package/rsyslog`, `package/syslog-ng`). Enabling one buys TLS transport
(TCP/RELP), on-disk queueing across outages, and server-side filtering.

| | |
|---|---|
| Effort | 2–4 days: Buildroot enable, rootfs size review, config templating, console surface, bench validation |
| Satisfies | R1, R2 (queued, asynchronous), R3 (disk queue survives outages), R5 (cert-based auth, no password), R6, R7 |
| Cost | rootfs growth on a 6 GB partition (fine) but also a second log daemon, a much larger configuration surface, and a new third-party component in the SBOM to track for CVEs — which is a real cost given Annex I §2 is still open |

Right answer *if a customer requires authenticated, guaranteed-delivery push.*
Overkill otherwise, and it adds exactly the kind of dependency we just finished
inventorying.

### C. Own forwarder tailing the durable log

A small script or daemon that follows `audit.log` and POSTs batches to an HTTPS
endpoint, keeping a byte-offset cursor.

The appealing property: **the durable log already is the queue.** A cursor file
plus the existing 4 MB of history gives outage tolerance for free, and retry is
just "don't advance the cursor".

| | |
|---|---|
| Effort | 2–3 days including retry/backoff, cursor persistence and tests |
| Satisfies | all of R1–R7 if written carefully |
| Cost | we own and maintain it, including the failure modes (partial batch, cursor vs. rotation interaction, backoff). Rotation makes the cursor fiddly — the offset must be interpreted against a generation, not just the live file |

Only worth it if the destination is an HTTP webhook rather than syslog.

### D. Pull model — let the collector fetch (recommended strategic answer)

Invert it: the device exposes the records; a collector on the plant network polls
and keeps them. **The endpoint already exists** — the console viewer
(`api-auditlog.sh` / `auditlog.sh`) is most of the work. What it needs is a
cursor so a poller can fetch only what is new:

```
GET /cgi-bin/api-auditlog.sh?since=<seq-or-timestamp>&lines=2000
```

| | |
|---|---|
| Effort | ~1–1.5 days: add a monotonic sequence number to each record, a `since=` parameter, and document the polling contract |
| Satisfies | R1 (short-lived CGI, no daemon involvement — proven by the viewer), R2 (**no outbound connection at all**, so there is nothing to block on), R3 (the collector retries; the device is stateless and the local log stays authoritative), R4 (needs an authenticated session, so it is inert until credentials are issued), R5 (**no new secrets** — reuses console auth), R6, R7 (nothing to configure on the device) |
| Cost | the collector must be built or configured site-side, and it needs console credentials. Polling interval bounds staleness |

Why this fits *these* products specifically: the stated deployment assumption is
an **isolated machine control network** with no outbound path. Options A–C all
require the device to open a connection outward, which either contradicts that
assumption or requires firewall holes per device. A pull model needs none, adds
no outbound attack surface, no phone-home behaviour, and no credentials on the
device. It also composes with A: a site can do both.

**A wrinkle to resolve first:** a monotonic per-record sequence number is needed
for a reliable cursor, and the current record format has no counter — a
timestamp alone is ambiguous when several records share a second. Adding `seq=`
is a format change, so it should land before anything depends on it.

## Recommendation

1. **Ship A now** as an opt-in `audit.forward_to = host:port` field — half a day,
   no build change, and it satisfies the common request ("get our records into
   our SIEM"). Document plainly that it is best-effort cleartext UDP.
2. **Then D** as the supported, deployment-assumption-respecting answer: add
   `seq=` to the record format and `since=` to the endpoint, and publish the
   polling contract so a customer's collector (or a small Joral-supplied one) can
   pull. This is where the durability story actually gets fixed.
3. **B only on demand**, when a customer contractually requires authenticated
   guaranteed delivery. Do not enable it speculatively — it is a new SBOM
   component to track while Annex I §2 (CVE screening) is still open.
4. **Skip C** unless a webhook destination is specifically required; D gets the
   same outage tolerance with less code we have to own.

## Exposure note (must be in the technical file if A ships)

Audit records carry no credentials, but they do carry **usernames, client IP
addresses and the times people were active** — that is personal and
operationally sensitive. Consequences to state:

- Option A sends this in **cleartext UDP**. On a trusted, segmented control
  network that is consistent with the rest of the posture (the media-gateway
  console is plain HTTP with no TLS option at all). It is not acceptable across
  an untrusted network.
- Option D inherits the console's transport: HTTPS on SatiSense when `web.tls` is
  on, **plain HTTP on media-gateway always**. Worth resolving alongside
  media-gateway console TLS, which is a separate open item.

## Acceptance criteria for whichever lands

Non-negotiable, and testable in the existing `make test` harness:

- Forwarding disabled by default; a fresh unit sends nothing.
- With an unreachable collector configured: login, config save and factory reset
  all still complete with no added latency (R2).
- A network outage does not lose the local record; the local log remains complete
  and authoritative (R3).
- No credential, key or secret appears in any forwarded record — the same
  assertion `tests/test_audit_log.sh` already makes about the local log, applied
  to the forwarded stream.
- Configuration is validated on save (a malformed host:port is rejected, not
  silently ignored).
- Forwarding config changes are themselves audited — turning off forwarding is
  exactly the action an intruder would take, so it must leave a record.

That last one matters and is easy to forget.

## Not in scope here

Log *retention policy* (how long a site must keep records) and any GDPR
assessment of holding usernames and IP addresses are product/legal decisions,
not engineering ones. Flag to product management alongside the support-period
question.
