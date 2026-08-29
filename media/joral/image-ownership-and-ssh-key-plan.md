# Image file ownership and SSH key policy — plan

***Status 2026-08-16 — Part 1 is DONE and CONFIRMED ON HARDWARE. Part 2 still
needs a product decision.** A unit running 2026.08.2, delivered through the A/B
updater, reports `/`, `/etc` and `/etc/ssh` as uid 0 / gid 0 and accepts a
key-authenticated SSH session with `StrictModes` at its default — acceptance
criteria 1 and 2, which are the whole of Part 1. The fix is in
`sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh`, with a staleness guard in
`build_firmware`, and `StrictModes no` is out of `sshd_config`.*

***Two wrong turns are recorded below rather than deleted, because both looked
right:** wrapping `mkfs.ext4` in `fakeroot` does NOTHING on this SDK — silently,
while passing its own `command -v fakeroot` check — and the tracked script is
not the one the build runs, so the first real build produced an image with the
defect intact and exit 0.*

*Written 2026-08-08, after the BSP hardening pass landed (adbd, telnetd and
samba removed; the stray buildroot stunnel dropped; root SSH login made
key-only; OPC UA Sign&Encrypt and console TLS made the shipped defaults). Two
follow-ups were deliberately deferred out of that work and are planned here.
Neither is implemented. Part 2 needs a product decision before code.*

The firewall item (`/etc/iptables.conf` is a 0-byte ruleset, and IPv6 is
uncovered entirely) is **not** in this plan — it is deferred separately and
needs a per-interface trust model first.

---

## Part 1 — Root-owned inodes in the image

### Where we are now

`build.sh` packs every ext4 partition with
[`sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh`](../../sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh):

```sh
mkfs.ext4 -d $src -r 1 -N 0 -m 5 -L "" -O ^64bit,^huge_file $dst "$dst_size"
```

`mkfs.ext4 -d` copies the staging tree **preserving build-host ownership**.
There is no `fakeroot` and no device table, so every inode in the image keeps
the UID of whoever ran the build — 1000 on a normal developer host. Measured on
the current staging tree: **4208 of 4208 files are uid 1000**, including `/`,
`/etc`, `/etc/ssh`, `/etc/shadow` and every init script.

This has always been true. It went unnoticed because processes run as root, and
root bypasses permission checks.

### Why this is worth doing

Two reasons, and the second is much larger than the first.

1. **It forced `StrictModes no`.** `sshd` requires the authorized-keys file *and
   every directory on its path* to be owned by root or the logging-in user.
   Nothing in this image qualifies, so key authentication cannot work with
   `StrictModes` at its default. The workaround is documented in
   `sshd_config`, but it is a weakened setting we would rather not ship or
   explain in the CRA technical file.

2. **It is a latent privilege-escalation path.** A service account added through
   `BR2_ROOTFS_USERS_TABLES` with an automatic UID lands at 1000 or above. The
   moment such an account exists, **it owns the entire root filesystem** —
   `/etc/shadow`, every init script, the SSH key, the OPC UA private key.

   This matters because CRA hardening actively pushes toward running daemons
   unprivileged. The first time anyone unprivileges the web console or the
   gateway daemon, they would hand that daemon ownership of the whole rootfs.
   Today it is inert only because no uid-1000 user exists in `/etc/passwd`.

### Approach — as implemented 2026-08-15

**The original fakeroot proposal does not work on this SDK, and the way it
fails is why this section is rewritten rather than deleted.**

`mkfs_ext4.sh` puts its own directory on `PATH`, and that directory contains a
**statically linked** `mkfs.ext4` (`ELF 64-bit … statically linked`). `fakeroot`
works by `LD_PRELOAD`, which a static binary does not consult. So the proposed
wrapper would have run, passed its own `command -v fakeroot` check, printed no
warning, and produced an image with **the identical defect**. Measured both
ways on the real staging tree:

| Binary | Under `fakeroot` | `/etc/shadow` in the image |
|---|---|---|
| SDK's `mkfs.ext4` (static) | yes | **uid 1000** |
| Host `/sbin/mkfs.ext4` (dynamic) | yes | uid 0 |

Switching to the host's dynamic `mkfs.ext4` was rejected as the fix: this
script pins the SDK's e2fsprogs precisely to control the on-disk feature set
(note the explicit `-O ^64bit,^huge_file`), and a newer host `mke2fs` enables
features the target kernel may refuse to mount. Trading a silent ownership bug
for a possible silent mount bug is not an improvement.

**What was implemented instead:** correct the ownership *in the packed image*
with `debugfs`, which is already a required build tool — `build.sh` reads the
release identity back out of the rootfs the same way. The path list is
generated from `$src`, which is by construction the tree just packed, so it
cannot drift from the image's contents.

Three properties make this safe to rely on:

- **It verifies the image, not the tooling.** After the pass, every inode is
  `stat`ed back out of the image and the build fails if any is non-root. This
  is the whole lesson of the fakeroot discovery: a build that merely *ran* the
  right command proves nothing.
- **It fails loudly, in both directions.** No `debugfs` → hard error naming the
  consequence. Ownership not applied → hard error with the count.
  `MKFS_EXT4_KEEP_BUILD_OWNERSHIP=1` is the documented, deliberate opt-out.
- **It loses no intent.** The staging tree is uniformly `1000:1000` (measured:
  2551/2551 entries), because an unprivileged build cannot express any other
  ownership. There is no deliberate non-root ownership to preserve.

Cost: ~1.1 s added to a rootfs pack (2552 inodes), and the resulting image is
`e2fsck -fn` clean. It runs for **every ext4 partition**, so `oem` (217 inodes)
and `userdata` (1) get the same treatment.

#### The fix was not complete without a second change

The first full build after the edit **silently did not apply it**.
`./build.sh media && ./build.sh firmware && ./build.sh swu` — the exact release
sequence this plan and `swupdate-implementation-plan.md` both document —
finished clean, exit 0, and produced an image whose `/etc` and `/etc/shadow`
were still uid 1000.

The cause is the SDK's tracked-master pattern, the same one that bit the
SWUpdate work twice with defconfigs. `sysdrv/tools/pc/` holds the **tracked**
packing tools; the build executes **copies** under
`output/out/sysdrv_out/pc/`, refreshed only by the `pctools` target — which
`media`, `firmware` and `swu` never trigger. So the build packed with the old
script, which had no ownership pass to run.

That is worse than an ordinary stale-copy bug, because the whole design of this
fix is "fail loudly if the ownership did not land" — and **a pass that never
runs cannot fail**. The verification and the thing being verified were in the
same file, so losing the file lost both.

`build_firmware` therefore now resolves each configured packing tool **through
`PATH`, exactly as the build will invoke it**, compares it to its tracked
master, and warns by name when they differ. Resolving through `PATH` rather
than comparing the two directories by filename matters: the question is not
"do these directories match", it is "is the file that will actually execute the
one in git". Verified in both directions — silent on a fresh tree, and naming
`sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh` when the pre-fix copy is put back.

A warning, not a hard failure: this is shared tooling and a checkout may
legitimately carry local edits mid-work. But it is never silent again.

<details>
<summary>Original proposal (does not work — kept for the record)</summary>

Wrap the `chown` and the `mkfs.ext4` in a **single** `fakeroot` invocation —
fakeroot's faked ownership only exists inside its own session, so they cannot
be separate commands:

```sh
if command -v fakeroot >/dev/null 2>&1; then
    fakeroot -- bash -c "chown -R 0:0 '$src' && \
        mkfs.ext4 -d '$src' -r 1 -N 0 -m 5 -L '' \
        -O ^64bit,^huge_file '$dst' '$dst_size'"
else
    echo "WARNING: fakeroot not found — image inodes will keep build-user ownership"
    mkfs.ext4 -d "$src" -r 1 -N 0 -m 5 -L "" -O ^64bit,^huge_file "$dst" "$dst_size"
fi
```

The fallback must be **loud**. A silent revert to the current behaviour on a CI
host without `fakeroot` would reintroduce the defect invisibly, which is worse
than not fixing it — the SSH key would then be rejected on those images only.

`fakeroot` is already present on the current build host (`/usr/bin/fakeroot`).
Confirm it on CI and any other build machine before merging, or add it to the
documented build prerequisites.

*Note in hindsight: fakeroot being present is exactly what made this proposal
dangerous. The check it suggested — "is fakeroot installed?" — is not the
question that matters. The question is whether the ownership actually landed in
the image, which is what the implemented version asks.*

</details>

### Risks and scope

- **Blast radius is every board.** `mkfs_ext4.sh` builds `rootfs`, `oem` *and*
  `userdata` for all board configs in the SDK, not just Pico Ultra. This is
  shared tooling.
- `chown -R` over the staging tree adds negligible time at this size (~4k
  files) but scales with image content.
- Anything that legitimately expects non-root ownership in the image would
  break. Nothing known does, but that is the thing to watch for in testing.

### Acceptance criteria

1. ~~On a flashed unit, `ls -ln /etc/ssh/authorized_keys` and `ls -ldn / /etc`
   report uid 0 / gid 0.~~ — **PASSED ON HARDWARE 2026-08-16.** Verified on the
   packed image first (`debugfs -R "stat …"` on `/`, `/etc`, `/etc/shadow`,
   `/etc/ssh/authorized_keys`, the init scripts and both product binaries: all
   uid 0 / gid 0, `e2fsck -fn` clean), then on a unit running 2026.08.2
   delivered through the A/B updater:

   ```
   drwxr-xr-x   21 0        0             4096 Aug 15 19:14 /
   drwxr-xr-x   15 0        0             4096 Aug 15 19:15 /etc
   drwxr-xr-x    2 0        0             4096 Aug 15 19:14 /etc/ssh
   ```

2. ~~`StrictModes no` is **removed** from `sshd_config` and key authentication
   still succeeds.~~ — **PASSED ON HARDWARE 2026-08-16, and this was the real
   test.** A fresh SSH session authenticated by key against a unit running with
   `StrictModes` at its default. Ownership was indeed the only missing half —
   the modes on the key path were already `0755`/`0644` with nothing group- or
   world-writable.

   **Part 1 is therefore complete**, six days after it was written and eight
   after the caveat that prompted it. What made it take that long was not the
   change — it is a few lines — but that the first two attempts at it were
   wrong in ways that looked right: `fakeroot` cannot touch a statically linked
   `mkfs.ext4`, and the tracked script is not the one the build runs.
3. Every board config that ships builds and boots — **pending**; the change is
   in shared SDK tooling.
4. ~~A build host without `fakeroot` emits the warning and does not fail
   silently.~~ — superseded, `fakeroot` is not used. The equivalent, and
   stronger, criterion is met: a host without `debugfs` fails the build with a
   named reason, and ownership that does not land fails the build with a count.
   **Both verified 2026-08-15** by stubbing `debugfs` to accept the write and
   silently do nothing — exactly the fakeroot failure mode — and confirming the
   build refuses the image rather than shipping it.

### Effort

Small change, moderate test burden. The edit is a few lines in one tracked
55-line script; the cost is the cross-board build-and-boot pass.

---

## Part 2 — SSH key policy for customers

### Where we are now

The image ships one Joral **public** key at `/etc/ssh/authorized_keys`, and
`PermitRootLogin prohibit-password`. Every unit built from this tree accepts
that one key. Customers have no SSH access; their interface is the web console,
which is now HTTPS with authentication.

### The invariant

**Private key material is never distributed.** Not to customers, not to field
technicians, not in a support bundle.

The public key in the image is not a secret — extracting it from a device gives
an attacker nothing. The exposure is wherever the *private* key lives. A single
fleet-wide key means one leak (laptop, backup, CI log) grants permanent access
to every unit ever shipped, with no revocation short of reflashing the fleet.

This is the same reasoning already encoded in `S60intelligence-edge` for TLS
certificates, which are minted per-unit on the device precisely so that no key
is byte-identical across deployments.

### Options

| Model | Mechanism | Fits when |
|---|---|---|
| **Vendor-only** | Joral key ships in the image; customers get no SSH | Default. SSH is a Joral service interface. |
| **Customer's own key** | Customer sends their public key; it is added to their image build | A customer genuinely needs shell access |
| **Console-provisioned** | Console gains an "add SSH key" field; operator pastes their own public key | Best long-term — no per-customer builds |
| **Shared private key** | — | **Never** |

The middle two preserve the invariant: each party generates its own keypair and
keeps its own private key. We never hold a customer's private key, and they
never hold ours.

### Recommendation

**Vendor-only now.** Treat the baked key as Joral's service credential, hold the
private key in a password manager or HSM, and do not distribute it. Customers
use the console.

Two refinements to plan for:

1. **Constrain the service key.** `authorized_keys` supports per-key
   restrictions, so the key need not be unrestricted root:

   ```
   from="10.0.0.0/8",restrict,pty ssh-ed25519 AAAA... joral-service
   ```

   `restrict` disables port and agent forwarding, removing the pivot capability
   flagged during the adbd analysis. Decide whether a `from=` prefix is
   workable given how units are reached in the field.

2. **Per-batch keys rather than one forever.** A single fleet-wide key means one
   compromise is total. Rotating per production batch or per customer bounds the
   blast radius, at the cost of tracking which key opens which units. Worth
   settling before volume shipping.

### Decision — 2026-08-29

**Vendor-only, confirmed.** No customer today needs SSH; the console is their
only interface and stays that way. Joral engineering uses the one baked-in
service key for diagnostics and audit access. This resolves the first open
question below and means neither of the two customer-facing models
(customer's-own-key, console-provisioned) needs building — the acceptance
criteria that follow are for the vendor-only model as it exists.

**SSH also moved off the default port 22 to 2200 the same day**, across both
products (`overlay-luckfox-buildroot-shadow/etc/ssh/sshd_config`,
`overlay-luckfox-buildroot-init/etc/iptables.conf`, both `cra-annex2-facts.md`
sheets, `bench-backlog-runbook.md`). This is a log-noise reduction, not an
access control — key-only auth with no password fallback
(`PermitRootLogin prohibit-password`) is what actually gates access, and a
targeted scan of this host finds :2200 in seconds. Recorded here rather than
invented a new document because it is the same access surface this plan
already covers. Verified: `debugfs` against the packed `rootfs.img` shows
`Port 2200` and the matching firewall `ACCEPT` rule; all seven release gates
pass (`oem`, `partitions`, `hardening`, `doccmds`, `cited`, `cve`, `sbom`).
IPv6 needed no change — `ip6tables.conf` already offers no service at all,
SSH included.

### Open questions for product

- ~~Do any customers contractually require shell access, or is console-only
  acceptable?~~ **Answered above, 2026-08-29: console-only, vendor-only SSH.**
- If console-provisioned keys are built: where do they persist? `/userdata`
  survives reboot, but confirm behaviour across reflash and factory reset —
  a key that silently disappears on update is worse than no feature.
  *(Moot unless the vendor-only decision above is revisited.)*
- **Who holds the service private key, and what is the rotation and revocation
  procedure?** Still open — this needs an answer for the CRA technical file
  regardless of the access model, and the access-model decision above does not
  answer it.

### Acceptance criteria

1. ~~A written access-model statement suitable for the CRA technical file~~ —
   **written 2026-08-29**: *SSH is a vendor-only diagnostics/audit interface,
   not offered to customers; each unit accepts only Joral's service key on
   port 2200; no private key material is distributed to customers.*
2. **Still open** — documented custody and rotation procedure for the service
   private key. This is the one item left in Part 2.
3. ~~If per-customer or console-provisioned access is adopted~~ — **moot**,
   vendor-only was chosen.

---

## Sequencing

1. **Part 1** — its own PR, cross-board test pass, then remove `StrictModes no`.
   Independent of Part 2 and safe to do first.
2. **Part 2** — product decision, then documentation; code only if
   console-provisioned access is chosen.

Neither blocks the current hardening work, which is verified on hardware.
