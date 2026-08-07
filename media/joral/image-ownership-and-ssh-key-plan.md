# Image file ownership and SSH key policy — plan (deferred)

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

### Approach

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

### Risks and scope

- **Blast radius is every board.** `mkfs_ext4.sh` builds `rootfs`, `oem` *and*
  `userdata` for all board configs in the SDK, not just Pico Ultra. This is
  shared tooling.
- `chown -R` over the staging tree adds negligible time at this size (~4k
  files) but scales with image content.
- Anything that legitimately expects non-root ownership in the image would
  break. Nothing known does, but that is the thing to watch for in testing.

### Acceptance criteria

1. On a flashed unit, `ls -ln /etc/ssh/authorized_keys` and `ls -ldn / /etc`
   report uid 0 / gid 0.
2. `StrictModes no` is **removed** from `sshd_config` and key authentication
   still succeeds. This is the real test — Part 1 is not done until this
   passes.
3. Every board config that ships builds and boots.
4. A build host without `fakeroot` emits the warning and does not fail silently.

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

### Open questions for product

- Do any customers contractually require shell access, or is console-only
  acceptable?
- If console-provisioned keys are built: where do they persist? `/userdata`
  survives reboot, but confirm behaviour across reflash and factory reset —
  a key that silently disappears on update is worse than no feature.
- Who holds the service private key, and what is the rotation and revocation
  procedure? This needs an answer for the CRA technical file regardless of which
  model is chosen.

### Acceptance criteria

1. A written access-model statement suitable for the CRA technical file, along
   the lines of: *SSH is a vendor service interface; each unit accepts only
   Joral's service key; no private key material is distributed to customers.*
2. Documented custody and rotation procedure for the service private key.
3. If per-customer or console-provisioned access is adopted: a documented flow
   in which the customer generates their own keypair and sends only the public
   half.

---

## Sequencing

1. **Part 1** — its own PR, cross-board test pass, then remove `StrictModes no`.
   Independent of Part 2 and safe to do first.
2. **Part 2** — product decision, then documentation; code only if
   console-provisioned access is chosen.

Neither blocks the current hardening work, which is verified on hardware.
