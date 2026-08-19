# Bench runbook — the accumulated backlog (one session)

*Prepared 2026-08-15, updated 2026-08-16. Seven verification legs have
accumulated since 2026-08-12, across three plans; three passed on 2026-08-16. Individually each is short; what has made them slip is that
each needed a bench and none needed it for long. This sequences all of them into
one session, in an order where the legs feed each other.*

This document does **not** restate legs that already have their own runbook. Where
one exists it is named and the section says which part of it to run.

---

## 0. What this session closes

| # | Leg | Status | Recorded in | Owner doc |
|---|-----|--------|-------------|-----------|
| 1 | Upgrade installs with no confirmation | **PASSED 2026-08-16** — a unit went to 2026.08.2 through the updater | `swupdate-implementation-plan.md` item 5 | this doc §3 |
| 2 | ~~**Downgrade is refused** until `DOWNGRADE` is typed~~ | **PASSED 2026-08-19** — refused with no phrase and with the phrase in the wrong case, then installed on `DOWNGRADE`; both audit records name `from=2026.08.6 to=2026.08.5 order=older`. The `order=unknown` half closed the same day with a correctly DEV-signed package declaring `1.0.0`: verified, refused, audited `order=unknown from=2026.08.9 to=1.0.0`. Driven with `curl` against the CGI, not the console | `swupdate-implementation-plan.md` item 5 | this doc §6 |
| 3 | **SSH key auth with `StrictModes` at its default** | **PASSED 2026-08-16** | `image-ownership-and-ssh-key-plan.md` AC 1–2 | this doc §4 |
| 4 | Image inodes are root-owned on a flashed unit | **PASSED 2026-08-16** — uid 0 / gid 0 on `/`, `/etc`, `/etc/ssh` | same, AC 1 | this doc §4 |
| 5 | MQTT **mutual TLS** + credentials-in-channel | **open** — needs a broker we control | `cra-compliance-plan.md` item 8 | `satisense-edge/docs/implementation-artifacts/mqtt-tls-bench-runbook.md` §2–§5 |
| 6 | ~~Media-gateway **durable-audit** spot-check, and a failed login correlated against stunnel's peer line~~ | **PASSED 2026-08-19** — `event=login result=fail user=admin src=unknown-via-tls` and stunnel's `accepted connection from ::ffff:172.32.0.100` in the same second; 2425 → 2426 lines, surviving a reboot | `cra-compliance-plan.md` item 8 | this doc §5 |
| 7 | ~~**SWUpdate negative + fault paths**~~ | **CLOSED 2026-08-14** *(this row read "open — negative artifacts are host-verified only" until 2026-08-19; it was wrong when written and nearly cost a bench session re-running six passing tests)* — all six passed on hardware, recorded in `swupdate-implementation-plan.md`'s bench-results table | `swupdate-implementation-plan.md` verification items 3–4, 6–7, 9 | that doc |
| 8 | ~~The 2026-08-16 product-decision changes~~ | **RESOLVED 2026-08-19, in two different ways.** `secrets_at_rest` **PASSED** — a flashed unit reports `"mode":"encrypted","binding":"soc-otp+emmc-cid"`, both binding sources read off real hardware for the first time. The `$6$` serial-console login is **WITHDRAWN, not passed**: the product decision of the same day removes the getty and locks the root account, so there is no login to exercise. Replaced by a new leg — key-authenticated SSH against a locked account on a console-less image — **PASSED** the same day | `cra-compliance-plan.md` items 9 and 15 | this doc §7a |

Legs 3 and 4 were the ones that carried risk, and §4 says what the recovery is
before it asks you to take it. **They passed on 2026-08-16** — on a unit updated
through the A/B updater rather than reflashed, which is the stronger result: the
change travelled the way a customer's would. Ownership was the only missing
half; the modes on the key path were already `0755`/`0644`.

**What is left is legs 2, 5, 6 and 7.** Leg 2 is the cheapest and the most
overdue — the artifact is already built and the gate has never been exercised on
hardware.

---

## 1. Starting state (confirm before anything else)

*Updated 2026-08-16.* The 08-15 session left a unit on **2026.08.1 / slot b**;
the 08-16 session took it to **2026.08.2** through the updater (§3, leg 1), so a
unit that has been through that session is on **slot a**. That is the state leg
2 wants — the downgrade artifact is the retained 2026.08.1, and the unit must be
running the newer release for it to order `older`. Confirm before anything else:

```sh
# on the unit (serial or SSH)
cat /etc/sw-versions          # -> rootfs 2026.08.2 after the 08-16 session
# misc_ab needs the misc PARTITION, discovered by PARTNAME the same way the
# initramfs, S99ab-health and the update CGI all do it:
MISC=$(for u in /sys/block/mmcblk*/mmcblk*/uevent; do \
         grep -q '^PARTNAME=misc$' "$u" && echo "/dev/$(sed -n 's/^DEVNAME=//p' "$u")"; done)
misc_ab status "$MISC"        # -> last_boot=a, slot_a successful_boot=1
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

## 3. Leg 1 — the upgrade path stays frictionless — **PASSED 2026-08-16**

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
misc_ab status "$MISC"   # -> last_boot=a, slot_a successful_boot=1
```

---

## 4. Legs 3 and 4 — SSH key auth with `StrictModes` on — **PASSED 2026-08-16**

**This is the real acceptance test for the image-ownership change, and it is the
one leg that can cost you access. Read the recovery first.**

> **Result 2026-08-16 — both passed**, on a unit updated to 2026.08.2 through
> the A/B updater rather than reflashed. `ls -ldn / /etc /etc/ssh` reported
> uid 0 / gid 0 on all three, and a fresh key-authenticated session succeeded
> with `StrictModes` at its default. Ownership was the only missing half — the
> modes on the key path were already `0755`/`0644`. Kept below because it is
> the procedure to re-run at every release that repacks the image.

Until 2026-08-15 every inode in the image was owned by the build user (uid 1000),
which is why `sshd` shipped `StrictModes no`. `mkfs_ext4.sh` now gives every
packed ext4 image root-owned inodes and fails the build if it cannot, so the
directive is gone. Verified on the build host 2026-08-15 and **on a unit
2026-08-16**.

**Recovery, if key auth breaks:** the standby slot still holds 2026.08.1, which
still has `StrictModes no`. You are not locked out — the console and the serial
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
curl -sk -X POST https://<unit>/cgi-bin/config.sh -b "$COOKIE=<session>" \
     -d 'can_gw_comm_port=abc&can_gw_proto=udp&can_gw_dest_ip=10.0.0.5'
# -> {"ok":false,"error":"can_gw_comm_port must be a whole number"}
curl -sk https://<unit>/cgi-bin/config.sh -b "$COOKIE=<session>" | head -3
# -> still returns a full JSON body (before the fix this was empty, permanently)
```

---

## 6. Leg 2 — the downgrade refusal

**The refusal has never run on hardware.** The 2026-08-15 session staged
2026.08.1 over a running 2026.08.1, which orders `same` and was correctly
offered without a prompt — that proved the no-friction half only.

**Product-specific, and getting this wrong wastes bench time:** the session
cookie and console port differ between the two products.

| | media-gateway | SatiSense Edge |
|---|---|---|
| cookie | `mg_sid` | `ie_sid` |
| console | `https://<unit>` (443) | `https://<unit>:8080` |
| audit log | `/userdata/media-gateway/audit.log` | `/userdata/satisense/audit.log` |

Both serve the update CGI at `cgi-bin/api-update.sh`. Substitute throughout.

**Two device facts that cost time on 2026-08-16.** The image ships **no
`logread` applet** — read syslog as `/var/log/messages`; a `logread | grep -c`
pipeline reports `0` when the command is simply missing, which reads exactly
like a clean result. And from a Windows bench PC, PowerShell aliases `curl` to
`Invoke-WebRequest`: every command below must be typed as **`curl.exe`**, and
any URL containing `&` must be quoted.

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
     -b "$COOKIE=<session>"
# -> {"ok":false,...} naming the downgrade and the required phrase

# wrong case -> still refused (the check is case-sensitive, deliberately)
curl -sk -X POST 'https://<unit>/cgi-bin/api-update.sh?action=apply&confirm=downgrade' \
     -b "$COOKIE=<session>"

# correct phrase -> proceeds
curl -sk -X POST 'https://<unit>/cgi-bin/api-update.sh?action=apply&confirm=DOWNGRADE' \
     -b "$COOKIE=<session>"
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

## 7a. Leg 7 — the 2026-08-16 product-decision changes

Three changes landed in the tree on 2026-08-16 that no flashed unit has yet
run. All three are one command each, and all three need the release built from
the current tree (`2026.08.3` or later) installed the customer way, through the
updater.

**a. The root password is off the published vendor default.** The value is
Joral-chosen and deliberately not written down in any customer document — take
it from `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-shadow/etc/shadow`
via the build host, or from whoever holds it. What is unproven is not the value
but the **hash format**: the overlay now ships `$6$` (SHA-512) where it shipped
`$1$` (MD5-crypt), and busybox `login` has never been asked to verify a `$6$`
on this image.

```sh
# on the SERIAL console (not SSH — SSH is key-only and will not exercise this)
# log out, then log in as root with the new password
grep -o '^root:\$[0-9]*' /etc/shadow      # -> root:$6
```

If the login fails, the fallback is the key-authenticated SSH session you
already have; do not reboot until you have one open. That is the only lockout
risk in this leg, and it is why it is done with a shell already up.

**b. Stored secrets are encrypted at rest and bound to the board.** The binding
reads the SoC OTP and the eMMC CID. Both are in the kernel config; neither has
ever been *read* on a unit, and the host tests fake them — so this check is the
whole evidence for the row.

```sh
# both binding sources readable?
head -c 32 /sys/bus/nvmem/devices/*otp*/nvmem | xxd | head -2
cat /sys/block/mmcblk0/device/cid

# what the daemon actually achieved (store a secret from the console first,
# e.g. an MQTT password, or this reads none-stored):
grep -o '"secrets_at_rest":{[^}]*}' /var/run/intelligence-edge/diagnostics.json
#   -> "mode":"encrypted","binding":"soc-otp+emmc-cid"

# and the file itself must not contain what you typed:
grep -c '<the password you just stored>' /userdata/satisense/state/gateway.json.secrets   # -> 0
head -c 120 /userdata/satisense/state/gateway.json.secrets                                # -> {"v":1,"cipher":"aes-256-gcm",...
```

`"mode":"plaintext"` is a **failing** result, not a variant: it means the unit
could not read its own hardware identity, and the reason is in the daemon's
startup log (`/var/log/intelligence-edge.log`). Quote it — the fallback path is
the one the design most needs field evidence for.

**c. The cross-board claim, if a second unit is on the bench.** Copy
`gateway.json.secrets` from unit A to unit B, restart B's daemon: B must come up
with **no** stored secrets and report `"mode":"unreadable"`. Copy it back and A
must still read it. That pair is the actual security claim; either half alone
proves nothing (an empty store also reports no secrets).

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
