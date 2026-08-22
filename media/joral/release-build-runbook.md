# Release build runbook — image, kernel, and `.swu`

*Written 2026-08-21, after the 5.10.160 → 5.10.252 kernel refresh was built,
packed and confirmed on hardware (T1S link, OPC UA server, CAN gateway), and
updated 2026-08-22 when 5.10.252 was **migrated in-tree as the default
kernel** — so none of what follows needs an environment variable or a staging
directory. This is the procedure for producing a release from this tree: what
to run, in what order, and — the part that actually bites — what each artifact
can and cannot deliver to a unit.*

Background for the pieces: [`kernel-port/README.md`](kernel-port/README.md)
for the kernel refresh, [`swupdate-implementation-plan.md`](swupdate-implementation-plan.md)
for the A/B design, [`firmware-signing-and-support-policy.md`](firmware-signing-and-support-policy.md)
for which key signs.

## The one thing to understand before running anything

**Two artifacts, two different reaches.** They are not interchangeable and the
difference is not cosmetic:

| Artifact | Carries | Reaches a fielded unit? |
|---|---|---|
| `output/image/update.img` | bootloader, `boot` FIT (**kernel** + dtb + initramfs), oem, userdata, both rootfs slots | **No — reflash only** (USB/SD, physical access) |
| `output/image/*.swu` | `rootfs.img` **only**, to the inactive slot | **Yes — this is the field update path** |

The `boot` partition is single-copy and absent from `sw-description.in`, so
**no `.swu` can ever change the kernel**. A kernel change is a reflash, which
is free before shipment and a recall after.

## Prerequisites, once per checkout

**The kernel is vendored in-tree.** Since the 5.10.252 migration
(2026-08-21) `sysdrv/source/kernel` **is** the product kernel — there is no
staging directory, no `KERNEL_DIR` export and no environment setup. A plain
`./build.sh` builds the right kernel:

```sh
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) ' sysdrv/source/kernel/Makefile
#   VERSION = 5 / PATCHLEVEL = 10 / SUBLEVEL = 252
```

If `KERNEL_DIR` is set in your environment, **unset it** — it is a leftover
from the port and `sysdrv/Makefile.param` no longer honours it anyway.

**The initramfs — the fresh-clone trap.** `media/joral/ab-boot/build/` is
**gitignored**, so a fresh clone has no `ramdisk.cpio.gz`. Without it
`build_ab_bootimg` prints a warning, **keeps the existing `boot.img`, and
carries on to a successful build** — producing a unit that boots one slot
directly and ignores every installed update. Check it exists:

```sh
ls media/joral/ab-boot/build/ramdisk.cpio.gz
# absent -> cd media/joral/ab-boot && make \
#           && scripts/mkinitramfs.sh build/busybox-static build/ramdisk.cpio.gz
```

The initramfs is static userspace with no kernel dependency, so a kernel
refresh does **not** require rebuilding it. It is re-packed into the new FIT
automatically.

## Step 1 — bump the release identity, before building the rootfs

```sh
$EDITOR media/joral/RELEASE_VERSION        # one line, YYYY.MM.PATCH
```

Do this **first**. ab-boot's `make install` stamps it into `/etc/sw-versions`
inside the rootfs during the media/app stage, and `./build.sh swu` reads the
version back **out of the packed rootfs** — never out of this file — so a
manifest cannot claim a version the image does not carry. Bump it after the
rootfs is built and the `.swu` will declare the old version.

`PATCH` is numeric per field and not zero-padded: `2026.08.10` is newer than
`2026.08.9`, which every string sort gets backwards.

## Step 2 — build the image

```sh
cd /home/embedded/luckfox-pico
./build.sh kernel
./build.sh rootfs                       # also rebuilds every module (drv)
./build.sh media && ./build.sh app      # only if userspace changed
./build.sh firmware                     # applies overlays, strips oem, packs
```

Or the whole thing — `./build.sh allsave` runs sysdrv → media → app →
firmware, including U-Boot.

Two rules, each of which produced a wrong image that exited 0 during the
5.10.252 port. They are recorded because they are properties of the build
system, not of that one port:

- **Never run `./build.sh kernel` alone and call it done.** `rootfs` depends on
  `drv` ([`sysdrv/Makefile`](../../sysdrv/Makefile), `ROOTFS_BUILD_ENV`), and
  `drv` is what rebuilds the modules. Build the kernel without it and you pair a
  new `vmlinux` with the previous kernel's `.ko` files — a vermagic mismatch
  that no build stage reports.
- **Never set `SYSDRV_KERNEL_OBJS_OUTPUT_DIR`.** `build_ab_bootimg` reads the
  kernel/fdt/resource blobs from the *default* `sysdrv/source/objs_kernel/out`
  (hardcoded as `KOUT` in [`project/build.sh`](../../project/build.sh)). Redirect
  the objects and the A/B FIT is silently built from whatever the last build
  left in the default location.

**When the kernel tree itself changes** — a re-base, a branch switch — also
`rm -rf sysdrv/source/objs_kernel` first. Stale objects from the previous tree
are what make that fail quietly.

## Step 3 — verify the **image**, not the build log

Every failure mode in this document exits 0. Check the artifact:

```sh
strings sysdrv/source/objs_kernel/vmlinux | grep -m1 'Linux version'
#   -> Linux version 5.10.252 ...

md5sum output/image/boot.img sysdrv/source/objs_kernel/out/boot-ab.img
#   -> identical.  Differing means the A/B FIT was not rebuilt and the image
#      is a stock single-slot boot that ignores updates.

ls output/out/rootfs_uclibc_rv1106/lib/modules/
#   -> 5.10.252, and nothing else

grep 'rescued' <the firmware build output>
#   -> rescued rknpu.ko -> /lib/modules/5.10.252/rknpu.ko
```

The module path is derived from each module's own vermagic, so it tracks the
kernel automatically — that line is the cheapest proof the two halves agree.

## Step 4 — the `.swu`

```sh
./build.sh swu
```

Requires `output/image/rootfs.img` from step 2. Signing depends on what
exists, and the target decides for itself:

- **DEV** (no ceremony output yet) — signs with the per-checkout key in
  `media/joral/ab-boot/keys-dev/`, created by `./build.sh media`. The image's
  own trust store carries the matching cert so bench units accept it.
  **Never ship a DEV-keyed `.swu`;** a customer unit will refuse it.
- **PRODUCTION** (`scripts/compliance/keys/trusted-certs.pem` committed) — the
  target writes the unsigned `sw-description` and stops with offline-signing
  instructions. Resume with:

  ```sh
  ./build.sh swu --sig <sw-description.sig>
  ```

Either way the result is verified against the trust store **staged for the
image** before it is called a release artifact.

## Step 5 — gates

```sh
./build.sh oem && ./build.sh partitions && ./build.sh hardening \
  && ./build.sh doccmds && ./build.sh cited && ./build.sh cve
```

All six must pass. `cve` is the one to record per release — the 5.10.252
refresh moved the kernel from 5155 matched records to 2867.

## The kernel/module cross-version hazard — read before shipping a `.swu`

Because a `.swu` replaces the rootfs but **cannot** replace the kernel, a
`.swu` built on a new kernel and installed on a unit still running the old one
delivers modules that unit cannot use. The rootfs carries
`/lib/modules/5.10.252/`, `S52npu` looks up `/lib/modules/$(uname -r)/`, and on
a 5.10.160 unit that path does not exist:

```
S52npu: no rknpu.ko for kernel 5.10.160 - NPU acceleration unavailable
```

**It is logged at info level and boot continues** — by design, chosen over an
insmod failing with a version-magic error deep in the boot. The same applies to
`pwm_bl.ko` and the RGB backlight. Nothing else in the rootfs is kernel-version
coupled, so the products themselves keep working; what silently goes away is
NPU acceleration and the backlight.

So, for the release that first carries 5.10.252:

- units are **reflashed** with `update.img` — kernel and rootfs move together,
  everything works;
- shipping that `.swu` to a not-yet-reflashed 5.10.160 unit is a **partial
  downgrade of function**, not a failed install. Do not do it without deciding
  that consciously;
- there are no units in the field yet, so today this costs a rebuild. The
  window closes at first shipment.

## Going back to 5.10.160

The old kernel is not kept in the working tree — it lives in git history, which
is the right place for it. Recover it the normal way:

```sh
git log --oneline -- sysdrv/source/kernel        # find the pre-migration commit
git checkout <rev> -- sysdrv/source/kernel
rm -rf sysdrv/source/objs_kernel
./build.sh kernel && ./build.sh rootfs && ./build.sh firmware
```

There is no scaffolding to undo: the migration replaced the tree in place and
`sysdrv/Makefile.param` is unmodified vendor code.

## Bench checks that are not optional after a kernel change

Confirmed on hardware for 5.10.252: **T1S link, OPC UA server, CAN gateway**
(2026-08-21) and the **OTP binding** (2026-08-22 —
`mode=encrypted`, `binding=soc-otp+emmc-cid`, `rockchip-otp0` present, no OTP
errors in `dmesg`). Run the checks below after any future kernel change; they
are written as a procedure precisely because the answer is not inferable from
the build host.

What is left is the OTP binding, and it needs three checks rather than the one
this document first claimed. **`mode = encrypted` on its own does not prove
it.**

**1. The kernel found the OTP at all** — the most direct question, and the one
the clock-list change could break:

```sh
ls /sys/bus/nvmem/devices/          # expect an entry matching *otp* (rockchip-otp0)
dmesg | grep -i otp                 # expect no probe/clk_bulk_get failure
```

**2. The sidecar is bound to it.** `secretbox.c` discovers the OTP through
`/sys/bus/nvmem/devices/*otp*/nvmem` and derives its key by HKDF over every
provider that works — `soc-otp` and `emmc-cid`:

```sh
cat /var/run/intelligence-edge/diagnostics.json | grep -o '"secrets_at_rest":{[^}]*}'
```

Both fields matter, for different failure shapes:

| Field | Required | Catches |
|---|---|---|
| `mode` | `encrypted` | a unit **provisioned before** the port: its envelope names `soc-otp+emmc-cid`, and `build_ikm` refuses to derive from a subset, so a vanished OTP fails the unseal outright and the mode becomes `unreadable` |
| `binding` | must contain **`soc-otp`** | a unit **provisioned after** the port: sealing uses whatever works, so a dead OTP silently binds to `emmc-cid` alone and `mode` still reads `encrypted` |

A `binding` of `emmc-cid` alone with `mode = encrypted` is the silent
regression this whole finding is about. It is a weaker key bound only to the
storage device, and nothing else reports it.

**3. `mode = none-stored` is not a pass.** It means no secrets are stored, so
nothing was exercised. Configure a secret first, then re-read.

Why this cannot be inferred from the host suite: it fakes the binding
providers, so it passes either way.

