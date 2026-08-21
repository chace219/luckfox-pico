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

**What is left of this table is leg 5** (MQTT mutual TLS, which needs a broker
whose authentication we control). Legs 2, 6 and 7 closed on 2026-08-19, leg 8 on
the same day. *(This paragraph read "legs 2, 5, 6 and 7" until 2026-08-21 —
correct when written on 08-16, stale for two days afterwards.)*

**A second session's worth of legs was opened on 2026-08-21** by the oem /
board-hardening work: see **§10**, which is self-contained and ordered, because
its legs destroy each other's pre-state if run out of sequence.

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

---

## 10. Session 2026-08-21 — the oem / NPU / stunnel legs (h–k)

*Four legs opened by the 2026-08-21 work (compliance plan items 13, 14, 16).
None blocks a shipment. Together they are about one hour, and the order below
is not a suggestion: **§10.2 destroys the pre-state §10.3 needs, and §10.5 destroys
the pre-state both need.** Run them in sequence or you will have to rebuild a
unit to re-run one.*

| Leg | Claim | Needs |
|---|---|---|
| j | stunnel's benign `Address already in use` line is gone from both products | nothing — a grep on the unit as it stands |
| h | `/oem` is emptied and re-owned, **through an update**, on a unit that was flashed with the payload | the 2026.08.13 `.swu` |
| k | nothing the strip removed was actually in use | the same updated unit |
| i | `/dev/rknpu` exists — and, on an *updated* unit, the log says why it does not | a **reflash** for the positive half |

### 10.0 Reading logs on this image — **there is no `logread`**

*Corrected 2026-08-21, after the command failed on the bench for at least the
second time. It was never going to work, and this section exists so nobody
tries it a third time.*

BusyBox here is built with `CONFIG_LOGREAD` **not set** and
`CONFIG_FEATURE_IPC_SYSLOG` **not set** — the applet is absent from the image
and the circular buffer it reads does not exist. `syslogd` runs with no
arguments, so it writes the default **file**:

| What you want | Command on the unit |
|---|---|
| System log — init scripts, `logger`, stunnel, sshd, dhcpcd | `cat /var/log/messages`, `grep X /var/log/messages` |
| Kernel — driver probes, module loads, CAN controller | `dmesg` |
| SATISense daemon | `cat /var/log/intelligence-edge.log` (1 MB cap + `.old`) |
| Security audit trail — **the only durable one** | `/userdata/satisense/audit.log`, `/userdata/media-gateway/audit.log` |
| Either console | Diagnostics / audit-log page |

**`/var/log` is a symlink to `/tmp`, which is tmpfs.** Everything in the first
three rows is **lost on the next reboot** — which is why the audit trail was
given a file on `/userdata` in the first place (2026-08-07). For the legs below
this is not a footnote: `S22oemclean` and `S52npu` log **on the boot that
follows the update**, so read `/var/log/messages` *before* rebooting again, or
the evidence is gone and the leg has to be re-run on a fresh unit.

Every leg below therefore has **state evidence** as its primary claim —
ownership, an empty directory, a device node, a listening socket — and treats
the log line as corroboration. State survives; the log does not.

**Starting state.** A unit on **2026.08.12**, updated (not reflashed) through
the A/B updater on 2026-08-20 — the unit the finding-B legs left behind. That is
exactly the right pre-state: it was flashed long before 2026-08-21, so it still
carries the full BSP `oem` payload and the build-user ownership on the
mountpoint.

```sh
# on the unit
cat /etc/sw-versions                     # -> rootfs 2026.08.12
MISC=$(for u in /sys/block/mmcblk*/mmcblk*/uevent; do \
         grep -q '^PARTNAME=misc$' "$u" && echo "/dev/$(sed -n 's/^DEVNAME=//p' "$u")"; done)
misc_ab status "$MISC"                   # note last_boot — it must FLIP in §10.3
```

### 10.1 Capture the pre-state — **do this first, it is not recoverable**

```sh
# on the unit
ls -ldn /oem                             # EXPECT 0 0 — mke2fs always makes the fs root
                                         #   root-owned; the defect is one level down
ls -ldn /oem/usr                         # EXPECT 1000 1000   <- THE DEFECT
find /oem ! -user 0 | head -5            # EXPECT non-empty — the build-user tree
ls -la /oem                              # EXPECT usr/ and the BSP payload
find /oem -type f | wc -l                # EXPECT ~198 (the number is the finding)
du -sh /oem                              # EXPECT ~21M
ls /oem/usr/share/intelligence-edge/www/assets/   # the divergent console bundle
ls /oem/usr/ko/rknpu.ko /oem/usr/bin/rkipc        # what was stranded there
```

Paste that output into the results block. **The `find /oem ! -user 0` output is
the whole point** — it is the ownership defect the compliance plan said only a
reflash could clear, and §10.3 is the claim that an update clears it.

### 10.2 Leg j — the stunnel line is gone

Costs nothing and must happen before the update, because a *pass* here on
2026.08.12 is what proves the fix travelled in the release that carries it
(satisense `a3ee855`, media-gateway `1d57b1b`, both merged 2026-08-19 and both
inside the pin 2026.08.12 was built from).

```sh
# 1. POSITIVE CONTROL FIRST — does stunnel reach this log at all?
grep -ic stunnel /var/log/messages            # EXPECT > 0
grep -i stunnel /var/log/messages | tail -20  # EXPECT startup lines, no errors

# 2. only then is the absence meaningful
grep -c 'Address already in use' /var/log/messages   # EXPECT 0

# 3. the state evidence, which needs no log at all
netstat -ltn | grep -E ':(443|8080) '         # EXPECT 0.0.0.0, NOT ::
```

**Step 1 is not optional.** "Zero hits" from a log that stunnel never writes to
is a pass produced by doing nothing — the same failure shape as the finding-A
boot-2 dumps that described the same boot three times. If step 1 comes back
empty, this unit cannot answer leg j from its log and step 3 is the whole
result.

Step 3 is the stronger evidence in any case: a **single** listener, bound to
`0.0.0.0` rather than `::`, is the fix itself. The old code produced a
dual-stack `::` bind plus a failed `0.0.0.0` one; the new code attempts exactly
one. `netstat -p` is not available here (BusyBox is built without
`FEATURE_NETSTAT_PRG`) — use `ss -ltnp` if you want the owning process.

Then confirm the console still answers over HTTPS from the bench PC. A green
grep with a dead console is not a pass.

### 10.3 Leg h — the update cleans `/oem`

Install `output/image/joral-platform-2026.08.13.swu` from the console
(**Firmware update**), exactly as in §3. It orders `newer` over 2026.08.12, so
no confirmation phrase is asked for.

**This leg is different from findings A and B, and that difference is the
result.** Both of those could only be proved on the update *after* the
delivering one, because the state they fix lives on the rootfs slot the update
replaces. `/oem` is a separate partition that every boot mounts, so
`S22oemclean` — shipped in the new rootfs — fixes it on the **first boot of the
delivering update**. If it needed a second update, the fix would be wrong.

After the reboot:

```sh
misc_ab status "$MISC"          # last_boot MUST have flipped — evidence a boot happened
cat /etc/sw-versions            # -> rootfs 2026.08.13

grep S22oemclean /var/log/messages   # EXPECT: removed N inherited entries from /oem
                                    # READ THIS BEFORE ANY FURTHER REBOOT — tmpfs
ls -ldn /oem                    # EXPECT drwxr-xr-x ... 0 0     <-- the claim
ls -la /oem                     # EXPECT empty (lost+found only)
find /oem -type f | wc -l       # EXPECT 0

# and the modules that were rescued out of it, now in the rootfs:
ls -l /lib/modules/$(uname -r)/
```

Three ways this can read as a pass while being one:

- **an empty `/oem` with no log line** — then it was never mounted and the
  script skipped; check for `not mounted` in `/var/log/messages` and fix
  S20linkmount before believing anything here. (If you have already rebooted
  since the update, the log is gone — tmpfs — and the ownership line below is
  the only evidence left, which is why it is the primary claim);
- **`last_boot` unchanged** — you are reading the same boot twice, which is
  exactly how the first attempt at finding A's boot 2 read as a pass on
  2026-08-19. If it did not flip, the install did not happen;
- **`find /oem ! -user 0` still returns anything** — the purge did not reach the
  build-user tree, and a fielded unit would still need a reflash. That is a FAIL
  even if `/oem` looks empty, because the ownership is the half no update could
  fix before. (The mountpoint's own `0 0` proves nothing either way: `mke2fs`
  writes the filesystem root root-owned on every unit.)

Also capture, here and not later, the paired negative for leg i:

```sh
grep S52npu /var/log/messages
# EXPECT on an UPDATED unit:
#   loaded rknpu (5.10.160) but /dev/rknpu is absent - the npu device-tree node
#   is disabled on this unit; a reflash is required, an update cannot change the dtb
ls -l /dev/rknpu                # EXPECT: No such file or directory
```

That message is a control in its own right: it is what stops the next person
debugging the driver when the answer is the device tree.

### 10.4 Leg k — nothing that was removed was in use

On the same updated unit, in this order, because each is cheap and the first
failure tells you where to look:

```sh
netstat -ltn                       # console + OPC UA, loopback backends on 127.0.0.1
```

- console over HTTPS from the bench PC: sign in, load Diagnostics;
- OPC UA from UaExpert: connect Sign&Encrypt with the pinned certificate, read a
  tag — **expect no trust prompt**, since 2026.08.12 already migrated the
  certificate to `/userdata` (that is finding B's closed claim, and this is a
  free re-confirmation of it on a third update);
- CAN: `candump can0` shows traffic, or `can-diag.sh` reports the interface up;
- SSH: a fresh key-authenticated session (host key must be unchanged — leg A's
  claim, also free here);
- media-gateway console on :443 and its CAN listener on :8001.

21 MB of binaries left a device. The tree said nothing referenced them; this is
the only thing that says so about a unit.

### 10.5 Leg i — `/dev/rknpu`, which needs a reflash

**Last, because it wipes the unit.** The device-tree node lives in the FIT in
the single-copy `boot` partition, which no `.swu` writes — so this half cannot
be reached through the updater by construction, and running it earlier would
throw away the pre-state §10.1 and §10.3 depend on.

Flash `output/image/` with SocToolKit / `upgrade_tool` as usual, then:

```sh
cat /etc/sw-versions            # -> rootfs 2026.08.13
ls -l /dev/rknpu                # EXPECT the character device   <- the claim
lsmod | grep rknpu              # EXPECT the module loaded
dmesg | grep -i rknpu           # EXPECT the driver's own probe lines (kernel side)
grep S52npu /var/log/messages   # EXPECT: loaded rknpu (5.10.160), /dev/rknpu present
ls -ldn /oem; find /oem -type f | wc -l   # EXPECT 0 0 and 0 — the FLASH half of leg h
```

Note what this does and does not claim. It says the driver probes and the device
node exists — the platform can now run the MVAD INT8 path. It does **not** say
inference works: no `.rknn` model ships, and `core/ai/aiworker.c` only reaches
`rknn_init()` when one is present. Proving the model path is a separate
exercise and is not part of this leg.


### 10.6 Results — 2026-08-21 session

*Unit 172.32.0.93, flashed in MASKROM with the complete 2026.08.13 image set.
Output quoted, not summarised.*

**Before the flash, on 2026.08.12 (the pre-state, §10.1):**

```
drwxr-xr-x    4 0        0             4096 Aug 15 04:26 /oem
200                     <- find /oem -type f | wc -l
20.6M                   <- du -sh /oem
/oem/usr /oem/usr/etc /oem/usr/share /oem/usr/share/iqfiles ...   <- find /oem ! -user 0
/oem/usr/share/intelligence-edge/www/assets/index-CPPdWU3u.js    <- the divergent console
```

**Correction to §10.1, made by this run.** The step said to expect `1000 1000`
on `/oem` itself. It came back `0 0`: `mke2fs` always creates the filesystem
root owned by root, so the defect never lived there — it lived one level down,
in `/oem/usr` and everything below it, which `find /oem ! -user 0` showed. The
pass criterion is that find returning **nothing**, not the mountpoint's own
ownership. Corrected in §10.1 and §10.3, and in the compliance plan.

**Leg j — PASSED**, twice: on 2026.08.12 before the flash and again on
2026.08.13 after it.

```
18                      <- grep -ic stunnel /var/log/messages  (positive control)
0                       <- grep -c 'Address already in use'
tcp  0  0 0.0.0.0:8080  0.0.0.0:*  LISTEN     users:(("stunnel",pid=761,fd=7))
tcp  0  0 0.0.0.0:443   0.0.0.0:*  LISTEN     users:(("stunnel",pid=472,fd=10))
```

Both consoles bind IPv4 once. `sshd` (`:::22`) and the OPC UA server
(`:::4840`) are **still dual-stack** on 2026.08.13 — which is what both Annex II
fact sheets already say, and this run is the first evidence for it on a current
release rather than on 2026.08.10.

**Leg h, flash half — PASSED.**

```
/dev/block/by-name/oem on /oem type ext4 (rw,relatime)
drwxr-xr-x    3 root     root          4096 Aug 21 04:53 .
drwx------    2 root     root         16384 Aug 21 04:53 lost+found
0                       <- find /oem -type f | wc -l     (was 200)
0                       <- find /oem ! -user 0 | wc -l   (was ~150)
```

**Leg i — PASSED.** The NPU has never had a device node on any unit this
product ever shipped; it does now.

```
crw-------    1 root     root       10, 123 /dev/rknpu
rknpu                  27019  0
[    3.429675] RKNPU ff660000.npu: RKNPU: rknpu iommu device-tree entry not found!, using non-iommu mode
[    3.430100] RKNPU ff660000.npu: RKNPU: Initialized RKNPU driver: v0.9.2 for 20230825
[    3.430184] RKNPU ff660000.npu: dev_pm_opp_set_regulators: no regulator (rknpu) found: -19
```

Two driver notes, neither fatal and both worth keeping: it runs in **non-IOMMU
mode** (no `iommus` property on the node) and finds **no `rknpu` regulator**
(`-ENODEV`), so there is no DVFS on that rail. Both are properties of the
vendor dtsi, not of the change that enabled the node, and both would matter to
anyone measuring inference throughput later.

**The rescued modules landed, and both are in use:**

```
-rw-r--r--    1 root     root         10056 /lib/modules/5.10.160/pwm_bl.ko
-rw-r--r--    1 root     root         41728 /lib/modules/5.10.160/rknpu.ko
pwm_bl                  4629  0
rknpu                  27019  0
```

`pwm_bl` loading proves S25backlight now resolves it from the rootfs — the
`/oem` fallback is dead code on this profile, as intended.

**Today's hardening, on the running unit:**

```
0                       <- grep -c getty /etc/inittab
root:*:20681::::::      <- locked
enable_coredump.sh umask.sh    <- /etc/profile.d, no RkEnv.sh
```

**OPEN — `S52npu` reported `rknpu already loaded`.** Something loaded the module
at kernel time **3.43 s**, before S52npu ran, and the script correctly did
nothing. That is the whole reason S52npu was moved behind `S50sshd`: if the real
loader is udev's `80-drivers.rules` (`RUN{builtin}+="kmod load $env{MODALIAS}"`,
fired by coldplug once the device-tree node became visible), then the driver is
being brought up **before networking anyway** and the reorder bought nothing.
The image ships no `modules.dep`/`modules.alias`, which is what libkmod normally
needs to resolve an alias, so the mechanism is not obvious and must be
established rather than assumed. Diagnostics: see the open item in §10.7.

**Leg h, update half — the mechanism is proven on hardware; one run short of
closed.**

*First attempt, and why it proved nothing.* The fielded-unit condition was
reconstructed (`/oem/usr` created and `chown`ed 1000:1000, confirmed
`drwxr-xr-x 4 1000 1000`) and the unit rebooted. Afterwards `/oem` was clean and
`find /oem ! -user 0` returned 0 — and `grep S22oemclean /var/log/messages`
returned **nothing**. Two histories produce that: the script ran on the first
boot and a second boot then cleared the tmpfs log; or the files never survived
the reboot at all, having been written seconds before it with no `sync`. `/oem`'s
mtime read `05:33`, the time of the `mkdir`, where a purge would have stamped it
later — so it did not decide either.

*What settled the behaviour.* The shipped script driven by hand on the unit,
after a `sync`, with its output going straight to the terminal:

```
# mkdir -p /oem/usr/bin && echo stale > /oem/usr/bin/rkipc && chown -R 1000:1000 /oem/usr
# sync
# /etc/init.d/S22oemclean start
S22oemclean: removed 1 inherited entry from /oem
# find /oem ! -user 0 | wc -l
0
```

*What settled the boot invocation.* On the first boot of **2026.08.15**
(`uptime`: up 0 min), which carries the always-log change:

```
Aug 21 05:58:37 satisense daemon.info S22oemclean: /oem carries no inherited payload - nothing to purge
Aug 21 05:59:05 satisense daemon.info S22oemclean: removed 1 inherited entry from /oem
```

The 05:58:37 line is the boot invocation — and it also proves the mount gate
passed, since the script logs that message only after `/proc/mounts` shows
`/oem`. The 05:59:05 line is the hand-driven run above. **Note what the first
attempt would have looked like on this release: a line, either way.** The
logging change was made because of that attempt and immediately paid for itself.

*CLOSED 2026-08-21, in one run.* Reconstruct, `sync`, reboot — and the removal
and the boot are the same event:

```
 06:01:32 up 0 min,  1 user,  load average: 0.00, 0.00, 0.00
Aug 21 06:01:08 satisense daemon.info S22oemclean: removed 1 inherited entry from /oem
0                       <- find /oem ! -user 0 | wc -l
```

`up 0 min` with the log line stamped 24 seconds before it is what makes this a
single observation rather than two joined by an argument: the removal happened
during **this** boot, not a previous one whose log a reboot could have carried
away. That is the claim the compliance plan needed — a unit that was flashed
with the BSP payload reaches the current state **through an update**, not only
through a reflash.

The payload was reconstructed rather than original, and that is stated
deliberately: the real 200-file payload had already been cleared by the flash
half of this leg. The script cannot tell the difference — it purges what is
there — but the record should say which one it saw.

*Also confirmed by the same session:* the unit reached **2026.08.15** and
reports it in `/etc/sw-versions`, so the update path carried today's changes.
`misc_ab status "$MISC"` returned `open : No such file or directory` — `$MISC`
was simply unset in the new shell, not a defect; re-run the discovery line from
the starting-state block before reading slot state.

**Leg k — CLOSED 2026-08-21, operator-confirmed.** Both consoles over HTTPS,
UaExpert Sign&Encrypt, CAN and SSH on the unit flashed from the stripped image.
Recorded as an operator confirmation, not as captured output: the console and
UaExpert halves are interactive and produce nothing quotable, and a transcript
invented for them would be worse than naming the evidence for what it is.

**All four legs opened on 2026-08-21 (h, i, j, k) are closed.** What remains of
this document is leg 5 / item 8b — MQTT mutual TLS, which needs a broker whose
authentication we control — and item 8g, the encoder-sim replay, which gates
nothing.

### 10.7 Reading the standby slot

Which release is on the *other* slot answers a question `misc_ab` cannot: did a
release arrive **through the updater** or through a MASKROM flash? The updater
writes the standby slot; a flash writes slot A and, if the flashing map includes
`misc.img`, resets the A/B record to the factory one.

```sh
mkdir -p /mnt/slot
mount -o ro /dev/block/by-name/rootfs_b /mnt/slot
cat /mnt/slot/etc/sw-versions
umount /mnt/slot
```

Read-only, so it cannot disturb the standby copy. If slot B carries the same
release as the running slot, the updater delivered it; if it carries an older
one, the running release was flashed and the updater has not been exercised
since.

*Left open after the 2026-08-21 session:* the unit ran **2026.08.15 from slot
A** with `last_boot=a`, `slot_a priority=15`, and `slot_b successful_boot=1`.
That fits a MASKROM flash whose map did not rewrite `misc` — leaving slot B's
history from an earlier update — and does not fit "08.15 arrived through the
console", which would have written B and left `last_boot=b`.

### 10.8 Recording

Per leg: pass/fail, the command output **quoted rather than summarised**, and
for anything surprising the command you ran to disprove it. Then:

- update the table in §0 and the leg list in `cra-compliance-plan.md` item 8;
- if leg h passes, the fact sheets' "closed 2026-08-21" paragraphs stop being a
  claim about the tree and become a claim about a unit — say so in both;
- if leg i's positive half passes, the same for the NPU row.

