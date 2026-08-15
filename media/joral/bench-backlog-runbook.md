# Bench runbook — the accumulated backlog (one session)

*Prepared 2026-08-15. Six verification legs have accumulated since 2026-08-12,
across three plans. Individually each is short; what has made them slip is that
each needed a bench and none needed it for long. This sequences all of them into
one session, in an order where the legs feed each other.*

This document does **not** restate legs that already have their own runbook. Where
one exists it is named and the section says which part of it to run.

---

## 0. What this session closes

| # | Leg | Recorded in | Owner doc |
|---|-----|-------------|-----------|
| 1 | Upgrade installs with no confirmation | `swupdate-implementation-plan.md` item 5 | this doc §3 |
| 2 | **Downgrade is refused** until `DOWNGRADE` is typed | `swupdate-implementation-plan.md` item 5 | this doc §6 |
| 3 | **SSH key auth with `StrictModes` at its default** | `image-ownership-and-ssh-key-plan.md` AC 1–2 | this doc §4 |
| 4 | Image inodes are root-owned on a flashed unit | same, AC 1 | this doc §4 |
| 5 | MQTT **mutual TLS** + credentials-in-channel | `cra-compliance-plan.md` item 8 | `satisense-edge/docs/implementation-artifacts/mqtt-tls-bench-runbook.md` §2–§5 |
| 6 | Media-gateway **durable-audit** spot-check, and a failed login correlated against stunnel's peer line | `cra-compliance-plan.md` item 8 | this doc §5 |

Legs 3 and 4 are the ones that carry risk, and §4 says what the recovery is
before it asks you to take it.

---

## 1. Starting state (confirm before anything else)

The 2026-08-15 session left a unit running **release 2026.08.1** on **slot b**.
Confirm, because everything below assumes it:

```sh
# on the unit (serial or SSH)
cat /etc/sw-versions          # -> rootfs 2026.08.1
misc_ab status                # -> last_boot=b, slot_b successful_boot=1
```

If the unit is on some other release, §3 and §6 still work — substitute the two
package names for "the newer one" and "the older one". What the legs need is an
ordering relationship, not those exact numbers.

---

## 2. Artifacts

Both are built and signed by the DEV key, which the image's own trust store
carries. **Neither is shippable** — see `firmware-signing-and-support-policy.md`.

```
output/image/joral-platform-2026.08.2.swu                    <- NEWER, install in §3
output/image/downgrade-test/joral-platform-2026.08.1.swu     <- OLDER, offer in §6
```

The older package is the genuine, correctly-signed 2026.08.1 artifact retained
from the previous build — not a fabricated one. That is the point of the test:
**a valid signature cannot tell you an image is old.** CMS attests who built it,
never when.

`2026.08.2` carries everything merged since: the console auth suites, the
`config.sh` numeric fix, and — the reason legs 3 and 4 exist — root-owned image
inodes with `StrictModes` back at its default.

---

## 3. Leg 1 — the upgrade path stays frictionless

Console → **Firmware update** → upload `joral-platform-2026.08.2.swu`.

Expected: verification passes, Install is offered **with no confirmation
prompt** (2026.08.2 over 2026.08.1 orders `newer`), install writes the inactive
slot, then "Reboot now to switch".

```sh
# evidence, on the unit
grep fw_ /userdata/media-gateway/audit.log | tail -5
#   fw_upload  result=success
#   fw_apply   started ... from=2026.08.1 to=2026.08.2 order=newer
#   fw_apply   success target=a
```

A confirmation prompt appearing **here** is a failure — a gate that nags on the
normal path trains operators to type the phrase without reading it.

Reboot to switch. Then:

```sh
cat /etc/sw-versions     # -> rootfs 2026.08.2
misc_ab status           # -> last_boot=a, slot_a successful_boot=1
```

---

## 4. Legs 3 and 4 — SSH key auth with `StrictModes` on

**This is the real acceptance test for the image-ownership change, and it is the
one leg that can cost you access. Read the recovery first.**

Until 2026-08-15 every inode in the image was owned by the build user (uid 1000),
which is why `sshd` shipped `StrictModes no`. `mkfs_ext4.sh` now gives every
packed ext4 image root-owned inodes and fails the build if it cannot, so the
directive is gone. Verified on the build host; never yet on a unit.

**Recovery, if key auth breaks:** slot **b** still holds 2026.08.1, which still
has `StrictModes no`. You are not locked out — the console and the serial
console are both unaffected, and §6 is itself the documented way back. Do not
reflash; roll back.

First, the ownership itself:

```sh
ls -ldn / /etc /etc/ssh
ls -ln  /etc/ssh/authorized_keys
# every line must report uid 0 gid 0
```

Then the thing that ownership was blocking:

```sh
# from the bench PC — a FRESH connection, not an existing session
ssh -i <joral-service-key> -o StrictHostKeyChecking=accept-new root@<unit>
```

Expected: it succeeds. If it fails with *"Server refused our key"*, that is a
`StrictModes` rejection and it means the packing regressed — check the image,
do not re-disable the directive:

```sh
# on the build host, against the image that was installed
debugfs -R "stat /etc/ssh/authorized_keys" output/image/rootfs.img | grep User
```

Also confirm sshd's own view, which names the offending path directly:

```sh
# on the unit
grep -i "bad ownership\|StrictModes" /tmp/messages
```

---

## 5. Leg 6 — media-gateway durable audit, and source attribution

Two short checks on the media-gateway console, both outstanding since
2026-08-12. The SatiSense equivalents passed then; this is the other product.

**(a) The durable trail survives a reboot.** `/var/log` is a tmpfs symlink, so
syslog alone loses everything on power-cycle; the `/userdata` copy is the one an
incident review can still read.

```sh
wc -l /userdata/media-gateway/audit.log      # note the count
reboot
wc -l /userdata/media-gateway/audit.log      # must be >= the previous count
```

**(b) A failed login, correlated against stunnel's peer line.** The console
records `src=unknown-via-tls` deliberately — behind the TLS terminator every
request arrives from 127.0.0.1, and recording that loopback address would name
the wrong principal. The true peer is in stunnel's log, and this proves the two
can be joined.

```sh
# from the bench PC, deliberately wrong password
curl -sk -X POST https://<unit>/cgi-bin/auth-login.sh \
     -d '{"user":"admin","pass":"definitely-wrong"}'
```

```sh
# on the unit — the two halves that must line up in time
grep 'event=login result=fail' /userdata/media-gateway/audit.log | tail -1
grep 'Service \[web\] accepted connection' /tmp/messages | tail -1
```

Expected: the audit record carries `user=admin src=unknown-via-tls` and **no
password**; the stunnel line carries the bench PC's real address. Those two
together are the attribution chain.

While signed in, the `config.sh` fix is worth one direct call — the console
never sends such a value, so only a direct call reaches it:

```sh
curl -sk -X POST https://<unit>/cgi-bin/config.sh -b "mg_sid=<session>" \
     -d 'can_gw_comm_port=abc&can_gw_proto=udp&can_gw_dest_ip=10.0.0.5'
# -> {"ok":false,"error":"can_gw_comm_port must be a whole number"}
curl -sk https://<unit>/cgi-bin/config.sh -b "mg_sid=<session>" | head -3
# -> still returns a full JSON body (before the fix this was empty, permanently)
```

---

## 6. Leg 2 — the downgrade refusal

**The refusal has never run on hardware.** The 2026-08-15 session staged
2026.08.1 over a running 2026.08.1, which orders `same` and was correctly
offered without a prompt — that proved the no-friction half only.

Upload `output/image/downgrade-test/joral-platform-2026.08.1.swu` to a unit now
running 2026.08.2.

Expected in the console: verification passes — **the signature is valid, and
that is the point** — and Install is refused pending the typed phrase
`DOWNGRADE`.

Then the check that actually matters. A disabled button demonstrates a screen;
the control is server-side, and the evidence is the CGI driven directly:

```sh
# no phrase -> refused
curl -sk -X POST 'https://<unit>/cgi-bin/api-update.sh?action=apply' \
     -b "mg_sid=<session>"
# -> {"ok":false,...} naming the downgrade and the required phrase

# wrong case -> still refused (the check is case-sensitive, deliberately)
curl -sk -X POST 'https://<unit>/cgi-bin/api-update.sh?action=apply&confirm=downgrade' \
     -b "mg_sid=<session>"

# correct phrase -> proceeds
curl -sk -X POST 'https://<unit>/cgi-bin/api-update.sh?action=apply&confirm=DOWNGRADE' \
     -b "mg_sid=<session>"
```

Both outcomes must be audited, and both records must name **the two releases** —
`target=b` alone cannot answer "was this unit ever running an affected build",
which is the question an advisory forces:

```sh
grep fw_apply /userdata/media-gateway/audit.log | tail -3
#   fw_apply refused ... from=2026.08.2 to=2026.08.1 order=older
#   fw_apply started ... from=2026.08.2 to=2026.08.1 order=older confirmed=yes
```

Be honest in the write-up about what this buys: it does **not** stop an attacker
who already holds console credentials — they can type the phrase. It converts a
*silent* signed rollback into a warned, explicitly confirmed and recorded one.

If §4 failed, this leg is also your way back: completing it returns the unit to
2026.08.1 and to `StrictModes no`.

---

## 7. Leg 5 — MQTT mutual TLS and credentials-in-channel

Run `satisense-edge/docs/implementation-artifacts/mqtt-tls-bench-runbook.md`,
**§2 through §5 only**. Legs (a) and (b) of TC-S3 and the server-verification
half of leg (c) closed on 2026-08-12/13; what is left is claims 4 and 5 of that
document's table — mutual TLS with a client cert/key, and confirming credentials
ride inside the encrypted channel.

It needs a broker on the bench, which is the reason this one kept slipping. That
runbook stands one up; nothing here replaces it.

---

## 8. Not a bench leg, but owed by the same change

`mkfs_ext4.sh` is **shared SDK tooling** — it packs `rootfs`, `oem` and
`userdata` for every board config in the tree, not just Pico Ultra. A
build-and-boot pass on the other shipped board configs is owed before that
change can be called finished, and it needs no bench beyond a build host for the
build half.

---

## 9. What to write down

For each leg: pass/fail, the command output quoted rather than summarised, and —
for anything that failed — what the unit did instead. The dated-entry convention
in `cra-compliance-plan.md` is the destination; the entries that have aged best
are the ones that recorded the surprise, not just the result.

Two specific things are worth capturing even on a clean run:

- the **exact** `fw_apply` audit lines from §3 and §6, since the version
  transition in them is the evidence an incident review would actually use;
- whether `StrictModes` needed anything beyond ownership. The modes on the key
  path are already `0755`/`0644`, so ownership *should* have been the only
  missing half — if it was not, that belongs in the plan.
