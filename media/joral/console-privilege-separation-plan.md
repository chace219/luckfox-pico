# Console privilege separation — plan and record

*Written 2026-08-21. Closes the last engineering residual on Annex I #4
(attack surface) for both products: "httpd + CGIs run as root", accepted in
each tree's `project-context.md` since v1 and carried as an open row in both
`cra-annex1-matrix.md` files since the 2026-07-26 audit.*

## Where we are now

Both consoles are busybox `httpd` serving a static UI plus a dozen shell CGIs.
Everything runs as **root**: httpd, every CGI, stunnel, and the one-shot daemon
invocations the CGIs make. The CGIs are the only code on either product that
parses bytes from an authenticated-but-remote browser (JSON bodies, query
strings, PEM uploads, a 256 MB firmware package), so a defect in any of them is
a root shell on the unit. Every other hardening in this programme — key-only
SSH, the locked root account, the firewall, root-owned inodes — sits behind
that one fact.

The survey that preceded this plan (all CGIs, both trees, 2026-08-21) found the
privileged operations are few and enumerable. Per product:

| Needs root | Why |
|---|---|
| durable audit append | `/userdata/<product>/audit.log` must not be writable by the console |
| service reload / restart | `kill -HUP` a root daemon; `/etc/init.d/S60 restart`; `ip link set can0` |
| factory reset | wipes state, rewrites `/etc`, reboots |
| firmware update | `misc_ab` reads the misc partition, `swupdate` writes a rootfs slot, `reboot` |
| PLCA status (media-gateway) | `SIOCGMIIREG` needs `CAP_NET_ADMIN` (`net/core/dev_ioctl.c:428-432`) |
| config ingest / redact (satisense) | the daemon writes the device-bound secrets sidecar and reads it back |
| certificate mint / install (satisense) | private keys must land root-owned 0600 |
| copilot / KB / LLM one-shots (satisense) | the daemon reads the sidecar (API key) and the root-owned log |

Everything else a CGI does — read sysfs, read the runtime state files the
daemons publish under `/var/run`, read and write the console's own
credential, sessions and (media-gateway) INI config — needs no privilege
once the files are owned correctly.

## Design

**Identity.** httpd and every CGI run as `www-data` (uid/gid 33), which
Buildroot's skeleton already ships in `/etc/passwd` and `/etc/group` — no new
account, no users table. stunnel drops to the same identity after it has
bound the public port and loaded the certificate (`setuid`/`setgid` in the
generated config; stunnel 5.65 calls `drop_privileges()` in `main_init()`
regardless of `foreground`, `stunnel.c:189`).

**Boundary.** One setuid-root dispatcher per product —
`/usr/sbin/media-gateway-privop` and `/usr/sbin/satisense-privop` — whose
only job is to run a **named verb** from a fixed, root-owned directory
(`/usr/lib/<product>/privop/<verb>`) with a scrubbed environment. The verbs
are ordinary shell scripts, so `ls` of that directory *is* the privileged
surface, and each verb owns its own argument validation. The dispatcher:

- accepts a verb matching `^[a-z][a-z0-9-]{0,31}$` and at most 8 arguments of
  at most 8192 bytes, none containing a control character (0x00–0x1f, 0x7f).
  UTF-8 above 0x7f passes — the copilot takes questions in any language;
- refuses a verb file that is not a regular file owned by root, executable,
  and not writable by group or other (exit 127, "unknown verb");
- clears the environment to `PATH`, `PRIVOP_VERB` and `PRIVOP_CALLER_UID`,
  plus a **validated** `REMOTE_ADDR` pass-through (addresses and brackets
  only, ≤ 64 bytes) so an audit record written on the root side names the
  same peer the CGI saw;
- closes every descriptor above 2 **except fd 9**, which `api-update.sh` holds
  as the update-operation flock and hands to the detached install worker —
  documented in the CGI, and the reason the worker needs no lock of its own;
- becomes fully root (`setgroups`, `setgid`, `setuid`), sets umask 022, logs
  `privop: verb=… uid=…` to `LOG_DAEMON`, and `execve`s the verb with its own
  argv. A caller whose real uid is neither root nor `www-data` is refused.

The source is deliberately vendored into both trees, the same way
`webauth.sh` and `swu-install.sh` are: `src/privop.c` differs only in the
two `-D` defines, and the per-tree test builds it for the host.

**Verbs.** Shared, byte-identical across the trees (the update CGI is one
template): `audit`, `misc-status`, `swu-stage`, `swu-apply`, `reboot`.
media-gateway adds `apply-config`, `plca-status`, `factory-reset`.
satisense-edge adds `service-restart`, `config-ingest`, `config-redacted`,
`gencert`, `cert-install`, `copilot`, `kb-search`, `llm-commission`,
`factory-reset`. Bodies (a config JSON, a PEM, a firmware package) travel on
**stdin**, never as a path argument; no verb takes a filesystem path from its
caller.

**Ownership, re-applied on every boot.** `/userdata/<product>/` becomes
`root:www-data 0750` with the audit log and its rotations `root:www-data
0640`: the console can read the trail and cannot truncate it. The verb
`audit` is the only way the CGI layer appends, and it refuses anything that
is not a single `event=… result=… user=… src=…` line. `state/` becomes
`www-data:www-data 0750` with the console-written files inside it
(`webauth.conf`, media-gateway's `gateway.conf`/`t1s.conf`) owned by
`www-data`; private keys and satisense's secrets sidecar stay `root 0600`
inside it, created by root and unreadable by the console. The sessions
directory under `/var/run` is created `www-data 0700` before httpd starts.
The fixup is **idempotent and runs in the init script's `start`**, so a unit
updated from a release that predates this change — everything on `/userdata`
root-owned — is corrected on the first boot that carries it, and a factory
reset (which restores root-owned files and then calls `start`) is covered
by the same code path.

**Low ports.** media-gateway's plaintext fallback binds `:443`. The daemon,
which forks httpd itself, keeps `CAP_NET_BIND_SERVICE` across the identity
change (`PR_SET_KEEPCAPS` → `setuid` → `capset` → `PR_CAP_AMBIENT_RAISE`)
only when the bind port is below 1024; on the TLS path httpd binds
`127.0.0.1:18081` with no capability at all. satisense-edge's plaintext
fallback binds `8080` and needs nothing; an operator who configures a port
below 1024 *and* turns TLS off gets a console that refuses to bind, reported
by the existing CONSOLE DOWN line with the cause named — that configuration
is refused rather than served by a root httpd.

## What it does not claim

- **The CGI layer can still do everything the console can do.** An attacker
  who owns a CGI owns an authenticated console session: config, credential,
  a firmware install of a *signed* package, a factory reset. What they can no
  longer do is read the secrets sidecar or a private key, write the rootfs,
  touch another service, erase the durable audit trail, or escalate past the
  verb list.
- **The verbs are root code fed by an untrusted caller.** That is the whole
  risk budget of this design and why the list is short, the arguments are
  validated in the helper *and* re-validated in each verb, and bodies come on
  stdin rather than by path.
- **A forged audit record is still possible** from a compromised CGI (the
  verb checks shape, not truth). It cannot be made impossible without moving
  authentication itself out of the CGI layer, which is not this change.
- **The two daemons stay root.** They own the network interfaces, the CAN
  bus and the OPC UA endpoint; unprivileging them is a different, larger
  piece of work and this plan neither starts nor forecloses it.

## Acceptance criteria

Testable on the host in each tree's `make test`, then one bench leg:

- `test_privop.sh` (both trees): the host-built dispatcher refuses an unknown
  verb, a traversal verb, an over-long or control-character argument, a
  non-root-owned or group-writable verb file; scrubs the environment (a verb
  that dumps its environment sees only the allowed names); keeps fd 9 and
  closes fd 10; every shipped verb script refuses bad arguments and performs
  its operation against a prefix tree with stubbed root commands.
- Every existing console suite stays green with the CGIs executing as a
  non-root user (they already do — the suites run as the developer).
- Bench, one unit, through the A/B updater: `ps` shows httpd and stunnel as
  `www-data`; a CGI's `id -u` is 33; login, config save, audit view, cert
  generation, firmware status/upload/apply and factory reset all work; the
  audit log is `0640 root:www-data` and `/userdata/<product>/state` is
  `www-data`; the pre-update unit's root-owned files were corrected on the
  first boot (`ls -l` before and after).

## Effort

Two days across both trees, most of it in the tests and in the shape of the
update CGI, which was the one place where "who holds the lock" had to be
thought through again.
