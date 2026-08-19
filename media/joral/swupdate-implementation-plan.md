# In-Product Update Mechanism (SWUpdate) — Implementation Plan

*Drafted 2026-08-13 from a survey of the U-Boot, kernel, buildroot and board
configuration in this tree, and revised the same day against the fact that
**no units are deployed at customer sites yet.***

***Status 2026-08-14 — implementation started:** Phase 0 (persistent state →
`/userdata/<product>/state/`) is **done in both product trees** — defines,
init-script seeding, factory-reset boundary, docs — with both host test
suites green (including new audit-survives-reset checks) and a clean
`./build.sh media` cross-build (staged tree carries factory copies only, no
config under `/etc`, binaries verified to reference the new paths). The
bench spike is **staged, not run**: `media/joral/ab-boot/` holds `misc_ab`
(byte-exact AVB record tool, 13 contract tests green against an independent
CRC32), the initramfs slot-selector, `mkinitramfs.sh`, `boot-ab.its`, the
`-AB` board profile, and the spike runbook (`ab-boot/README.md`).*

***Status 2026-08-14 (second pass) — the update pipeline itself is
SOFTWARE-COMPLETE, bench-pending:** SWUpdate is enabled in the buildroot
defconfig with a `swupdate-joral.config` (CMS signature verification via
OpenSSL, webserver OFF, stock S80swupdate daemon overridden inert in the
board overlay); `ab-boot` ships `/etc/swupdate.cfg` pinning the
`/etc/swupdate/trusted-certs.pem` trust store, the `sw-description.in`
two-slot template, `S99ab-health` (daemon-liveness → `mark-successful` —
deliberately not a port check, so operator config choices can never trigger
rollback) and the shared `api-update.sh` console CGI (status / upload with
on-device `swupdate -c` verification / apply-to-inactive-slot +
`mark-active`), instantiated into both product trees with UI panels on both
consoles (SatiSense SPA rebuilt; both product test suites green).
`./build.sh swu` packs and signs the release artifact and refuses one the
image's own trust store would reject. **Key ceremony deferred by decision
(see `firmware-signing-and-support-policy.md`): builds sign with a
per-checkout DEV key; no customer shipment on a DEV-keyed trust store.**
What remains is hardware: the 2–3 day bench spike, layout freeze, then the
full verification plan below.*

***Status 2026-08-14 (third pass) — spike artifacts BUILT AND FLASH-READY,
bench execution pending:** Phase 0 re-verified (both product suites + the 13
`misc_ab` contract tests green). Built: a static busybox 1.36.1 (cross,
from the buildroot dl cache), `ramdisk.cpio.gz` (736 K, all-static:
busybox + `misc_ab` + `init`), and `boot-ab.img` (4.7 M FIT =
kernel+fdt+resource+initramfs, via the vendor `mkimg` recipe). The tree is
lunched on the `-AB` profile (and `emmc_fstab` edited to `/dev/mmcblk0p8` —
which, as the 2026-08-19 freeze established, was a no-op: nothing installs
that file);
`./build.sh firmware` produced the full A/B image set — `.env.txt` carries
the A/B `blkdevparts`, `boot.img` in `output/image/` IS the ramdisk FIT,
`tftp_update.txt`/`sd_update.txt` offsets are derived from the A/B table
(`misc` deliberately absent → blank, self-init), `update.img` packed, and
`./build.sh swu` re-signed a `.swu` matching the packed rootfs. Spike (a)
flash commands (single-slot layout, boot at LBA 0x640) and the stock-FIT
restore path are in `ab-boot/build/spike-a-flash-notes.txt`; the stock boot
FIT is preserved as `ab-boot/build/boot-stock.img`. No bench hardware is
reachable from the build host — flashing and the serial-console checks are
the remaining manual steps (runbook: `ab-boot/README.md`).*

***Status 2026-08-14 (fourth pass) — bench: A/B image FLASHED AND BOOTING
(SocToolKit/MaskROM; HTTPS, OPC UA confirmed up), first .swu upload attempts
surfaced two defects, both fixed:** (1) the flashed rootfs had NO `swupdate`
binary — the enable lines had been added to the throwaway live buildroot
tree only, and to `luckfox_pico_defconfig` instead of the
`luckfox_pico_w_defconfig` the board builds (the tracked-masters gotcha,
twice). Fixed in the master defconfig; `swupdate-joral.config` now has a
tracked home (`sysdrv/tools/board/buildroot/swupdate/`) with copy lines in
`sysdrv/Makefile`; rootfs rebuilt and the binary verified inside the packed
image; the upload CGI now reports a missing binary as itself instead of
"wrong signature". (2) `swupdate -c` died with "Connection reset by peer":
without `installed-directly = true;` SWUpdate extracts the 119 MB payload
into TMPDIR — a RAM-backed tmpfs on a 256 MB device — before checking.
Both image entries in `sw-description.in` now stream directly. Consoles
additionally gained a real upload progress bar (XHR `upload.onprogress`;
fetch cannot report request-body progress). Both defects were invisible in
a code read — the TC-S3 lesson holding for the updater too.*

***Status 2026-08-14 (fifth pass) — FULL UPDATE VERIFIED ON HARDWARE (items
1,2,8):** a genuine `.swu` uploaded, verified on-device, installed to slot B
and `mark-active`'d; the audit log carries `fw_upload`/`fw_apply
started`/`fw_apply success target=b`; after reboot the operator confirmed the
admin password, the JSON config and (item 8) survived the slot switch, and
ENIP came up from slot B without the manual firewall commands. Also this
pass: three more field bugs found and fixed — (3) the CGI verified with
`swupdate -c` but WITHOUT `-e stable,<slot>`, so the two-mode sw-description
selected no image set and 2022.12 aborted with a bare "Image invalid or
corrupted" on EVERY upload regardless of the file (now selects the inactive
slot for the check, matching install); (4) the ENIP scanner was silently
broken by the 2026-08-12 firewall — implicit I/O UDP 2222 was closed and
broadcast ListIdentity replies (source port 44818) couldn't match conntrack
(both rules added); (5) the media-gateway console served plain HTTP on 443
because the factory `gateway.conf` still pointed the cert at the removed
`/etc/media-gateway/` — keygen failed and it fell back (paths moved to the
Phase 0 state dir, tests tightened to require it). Install is now
non-blocking with a real write-percentage progress bar on both consoles
(detached `swu-install.sh` worker streaming SWUpdate's progress IPC; CGI
`progress` action polled by the UI). Negative-test artifacts built and
host-verified for items 3-4: `output/image/negative-tests/`
{tampered-payload, tampered-signature, wrong-key}.swu + README.*

***Status 2026-08-14 (sixth pass) — THE BOOT-TIME SLOT SWITCH WORKS; SPIKE
(a)/(b)/(c) CLOSED ON HARDWARE:** the first reboot after a successful install
still came up on slot A with `slot_b tries_remaining=7` — i.e. the selector
never ran. Two causes, both now fixed. **(1)** The flashed `boot` held the
STOCK kernel FIT: every `./build.sh kernel|media|firmware` regenerates a
ramdisk-less `boot.img`, and one of those silently replaced the selector FIT
before flashing. **(2)** Even with the right FIT in `boot`, the kernel still
booted straight to `root=` with no initrd — our ramdisk node lacked a `load`
address, so U-Boot proper's `boot_fit` (`cmd/bootfit.c`) loaded the kernel
but never placed or passed the ramdisk. Adding `load = <0x00e00000>`
(`ramdisk_addr_r`, `rv1106_common.h:82`) plus `uboot-ignore` on the hash, per
the vendor's `rv1106-boot-tb-ramdisk.its`, fixed it. Bench proof:
`Trying to unpack rootfs image as initramfs... / Freeing initrd memory: 736K`
(the exact ramdisk size), `last_boot=b`, `slot_b successful_boot=1` — the
unit booted the UPDATED slot through the real selector, so verification
items 1, 2 and 8 are now genuinely passed. Cause (1) is closed permanently:
`build_ab_bootimg()` in `build.sh` rebuilds the selector FIT (and mints
`misc.img`) inside `build_firmware` whenever the partition table is an A/B
one, so no build order can ship a ramdisk-less boot image again.*

***2026-08-14 (sixth pass) — switch-now UX:** decided and implemented: NO
automatic reboot after install — the operator owns the maintenance window on
a machine-control gateway, and deferred switching is what A/B buys. Instead,
`status` now reports `pending` (selector's next choice ≠ running slot) and a
`reboot` action + "Reboot now to switch" button (both consoles, audit-logged
as `fw_reboot`, refused while an install is writing the standby slot) give
the explicit switch. Both suites + SPA rebuilt green.*

*This work closes CRA plan item 4b / Annex I row #7
(`cra-compliance-plan.md:28`), the last ❌ that no network architecture can
substitute for. The signing-key custody and support-period decisions are
recorded in `firmware-signing-and-support-policy.md`.*

## The greenfield position changes the problem

Nothing is in the field. There is no fleet to migrate, no compatibility path to
maintain, no truck roll to schedule. The entire question becomes:

> **Which decisions become one-way doors the moment the first customer unit
> ships — and which can be shipped later, through the update mechanism itself?**

Get the one-way doors right before first shipment and everything else is
deliverable as an update. That is the organising principle of this plan, and it
makes the pre-ship scope much smaller than it would otherwise be.

**One-way doors — must be right before the first customer unit ships:**

1. **Partition layout** — reserved for the full design even if v1 uses less of it.
2. **Where persistent state lives** — it defines what survives an update.
3. **Trusted public keys baked into the image** — bake two (active + unused
   rollover spare). Retrofitting a second key later means recalling units.
4. **The `.swu` manifest format and its version field** — a v1 unit must still
   be able to install a 2030 image.
5. **The provisioning process at manufacture** — `misc` initialisation and unit
   identity.

**Everything else ships later, through the updater:** the console UI, delta
updates, a read-only rootfs, kernel-slot protection, dm-verity, secure-boot
fuses. None of these need to gate the first shipment, *because* you will have an
update mechanism.

## Summary of the position

The tree is in a **better** state than the "no updater at all" row implies, and
in one respect a **worse** one:

- **Better:** Rockchip's A/B slot machinery is already compiled into the
  bootloader this board builds. `CONFIG_SPL_AB=y` is set in the very defconfig
  the Pico Ultra uses, and the full AVB A/B flow — slot priority, tries
  counting, automatic fallback — is present in `common/spl/spl_ab.c`. We are not
  writing a bootloader; we are wiring one up.
- **Worse:** **both products keep their persistent state inside the rootfs.**
  Any rootfs replacement — A/B swap or recovery-style overwrite — destroys the
  unit's configuration, its per-unit TLS keypair and its changed admin password.
  This is a hard prerequisite and it is larger than the updater itself. With
  nothing deployed it is at least *cheap* — a straight move, no compatibility
  shim.

**Recommendation: SWUpdate driving an A/B rootfs, with slot selection and
rollback handled by a small initramfs reading the same `misc` metadata the
bootloader already understands, and signatures verified before any write.** See
"Chosen design" below — this needs **no bootloader changes at all**, while
reserving the layout so the fuller bootloader-level design stays available
later.

## Survey results (verified 2026-08-13)

### What exists in the bootloader

The Pico Ultra board builds `luckfox_rv1106_uboot_defconfig`
(`BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk:81`), which sets:

- `CONFIG_SPL_AB=y` (`luckfox_rv1106_uboot_defconfig:43`) — Rockchip's SPL A/B.
- `CONFIG_ENVF=y` + `CONFIG_ENVF_LIST` (`:80-81`), the list including
  `sys_bootargs`.
- `CONFIG_SPL_RSA=y`, `CONFIG_SPL_FIT_HW_CRYPTO=y`, `CONFIG_FIT_HW_CRYPTO=y`
  (`:136`, `:28`, `:25`) — hardware-accelerated RSA verification of FIT images
  in SPL. The secure-boot primitives are present but unused.

`common/spl/spl_ab.c` implements the standard AVB A/B flow against a **`misc`**
partition: `AvbABData` (magic `"\0AB0"`, two slots × {priority,
tries_remaining, successful_boot}, CRC32 — `include/android_avb/avb_ab_flow.h:84-104`),
`spl_get_current_slot()`, `spl_ab_decrease_tries()`, `spl_ab_decrease_reset()`.
Max tries is 7 (`avb_ab_flow.h:54`). A slot is bootable when
`priority > 0 && (successful_boot || tries_remaining > 0)`; when neither slot is
bootable it falls back to `last_boot`.

`disk/part.c:702-717` is the integration point, and it carries **the one
important limitation**:

```c
#if defined(CONFIG_ANDROID_AB) && !defined(CONFIG_SPL_BUILD)
	if (rk_avb_append_part_slot(name, name_slot))    /* U-Boot proper */
#elif defined(CONFIG_SPL_AB) && defined(CONFIG_SPL_BUILD)
	if (spl_ab_append_part_slot(dev_desc, name, name_slot))   /* SPL only */
#endif
```

So **in SPL**, every partition looked up by name transparently gains an `_a` /
`_b` suffix. **In U-Boot proper**, that requires `CONFIG_ANDROID_AB`, which is
**not set on any Luckfox or RV1106 board config in this tree**. Since this board
boots SPL → U-Boot proper → kernel (`CONFIG_SPL_KERNEL_BOOT` appears only in the
`..._tb_defconfig` variants, not the one we build), the slot chosen by SPL is
**not currently inherited** by the stage that loads the kernel and sets `root=`.
That gap is the spike.

### The environment partition

`CONFIG_ENV_IS_NOWHERE=1` with ENVF as an overlay; `CONFIG_ENV_SIZE=0x8000`,
`CONFIG_ENV_OFFSET=0x0`, and **`CONFIG_ENV_OFFSET_REDUND=0x0` — there is no
redundant environment copy.** `build_env()` (`build.sh:754-776`) generates it
with stock `mkenvimage -s 0x8000 -p 0x0`, so the on-disk format is standard
U-Boot env and `libubootenv` / `fw_setenv` can write it.

**But without a redundant copy, a power cut during an env write leaves an
invalid CRC and an unbootable unit.** This is why the design below routes slot
selection through `misc` (a 32-byte CRC'd record with a defined invalid-state
recovery path in `spl_ab_data_read()`) rather than through `sys_bootargs`. If
any design ends up needing env writes at runtime, enabling
`CONFIG_ENV_OFFSET_REDUND` becomes mandatory, not optional.

### The kernel side

`CONFIG_CMDLINE_PARTITION=y` and `CONFIG_PARTITION_ADVANCED=y` — partitions come
from the `blkdevparts=` string, not GPT. `block/partitions/cmdline.c` assigns
**no PARTUUID or PARTLABEL**, so `root=PARTLABEL=rootfs_a` is not available; the
root device must be named by index (`root=/dev/mmcblk0p7` today,
`output/image/.env.txt`). `CONFIG_BLK_DEV_INITRD=y` is already set, which makes
the initramfs option below viable.

### Rockchip's own OTA path is a stub here

`build_recovery()` (`build.sh:977`) and `build_ota()` (`build.sh:1180`) exist,
gated on `RK_ENABLE_RECOVERY` / `RK_ENABLE_OTA`. Neither flag is set on **any**
board config in `project/cfg/BoardConfig_IPC/`, and the scripts both functions
depend on — `RK_OTA_update.sh`, `RK_OTA_erase_misc.sh`,
`scripts/RkLunch-recovery.sh` — are **absent from this tree** (Luckfox removed
them; only `project/scripts/boot4recovery.its` survives). `build_ota()` as it
stands would emit a tar of raw images with no installer and no verification.
Treat this path as scaffolding, not a working feature.

### Space

Current layout
(`BoardConfig-...Pico_Ultra-IPC.mk:38`), against a build from 2026-08-13:

| Partition | Allocated | Used |
|---|---|---|
| env | 32 K | 32 K |
| idblock | 512 K | 184 K |
| uboot | 256 K | 256 K |
| boot | 32 M | 3.8 M |
| oem | 512 M | 38 M |
| userdata | 256 M | 9.5 M |
| rootfs | 6 G | **151 M** |

A 151 MB rootfs in a 6 G partition. Space is not a constraint — A/B costs
nothing we don't already have.

### The three frameworks, as packaged in `buildroot-2023.02.6`

| | Unconditional dependencies | Verdict |
|---|---|---|
| **swupdate** | one config parser (libconfig / json-c / lua) | **Chosen.** OpenSSL, zlib, `libubootenv` are opt-in `select`s |
| **rauc** | libglib2, squashfs, uboot-tools + fwprintenv, OpenSSL | Rejected — glib2 permanently in the SBOM and CVE gate. (dbus is optional, contrary to an earlier claim of mine) |
| **mender** | Go toolchain, and forces `LIBOPENSSL_ENABLE_MD4` + `ENABLE_RMD160` | Rejected — reinstates legacy digests in the OpenSSL 3.5.7 we migrated to on 2026-08-12, plus needs a backend server |

`libubootenv` is packaged and selects only zlib.

## Chosen design — initramfs-driven A/B, no bootloader changes

The obstacle identified in the survey is that SPL picks a slot but U-Boot proper
doesn't inherit it. The three ways round that all involve bootloader work. There
is a fourth that doesn't, and it is better suited to a greenfield product:

**Move the slot decision into a small initramfs.**

```text
BootROM → SPL → U-Boot proper → kernel + initramfs (from `boot`)
                                        │
                                        ├─ read AvbABData from `misc`
                                        ├─ pick slot; decrement tries_remaining
                                        ├─ write metadata back
                                        └─ mount rootfs_a|_b → switch_root
                                                 │
                                          userspace health check
                                                 └─ mark slot successful
```

The initramfs implements exactly the AVB semantics already in
`common/spl/spl_ab.c` — same 32-byte record, same magic, same CRC32, same
`priority`/`tries_remaining`/`successful_boot` rules — but in userspace, where
it is testable on a build host rather than only on a serial console.

Why this is the right trade here:

- **Zero bootloader changes.** SPL and U-Boot proper are untouched. No
  `CONFIG_ANDROID_AB`, no AVB machinery, no switch to the tiny-boot
  architecture, no fighting the vendor BSP.
- **It solves the missing-PARTUUID problem** (`CONFIG_CMDLINE_PARTITION`
  assigns no labels) without needing one — the initramfs names the device
  directly.
- **It covers what actually needs updating.** Effectively every security fix
  we have shipped or will ship — OpenSSL, stunnel, busybox, open62541, both
  daemons, the CGIs, the firewall rules — lives in the rootfs.
- **The build already supports it.** `CONFIG_BLK_DEV_INITRD=y` is set, and
  ramdisk FIT templates exist (`project/sfc_scripts/rv1106-boot-tb-ramdisk.its`,
  `boot4recovery.its`), so adding a ramdisk to `boot.its` follows an existing
  pattern. `boot` is 32 M holding a 3.8 M image.

**What it does not cover:** the kernel, the initramfs itself, and U-Boot are
single-copy. A bad kernel image means the initramfs never runs, nothing
decrements, and recovery is via MaskROM. Mitigations:

- The updater **refuses to write `boot`, `uboot` or `idblock`** unless the
  `.swu` explicitly declares a platform update and the operator confirms.
- Kernel updates are rare and can be scheduled as attended maintenance.
- **Reserve `boot_a`/`boot_b` in the layout anyway** (below). If kernel-slot
  protection is wanted later, the fuller bootloader design — `CONFIG_ANDROID_AB`
  in U-Boot proper, or the `CONFIG_SPL_KERNEL_BOOT` architecture — can be
  adopted without repartitioning. That is the whole point of reserving the
  layout: implement the cheap design, keep the expensive one available.

This turns the blocking one-week spike into a verification task.

## Decisions

1. **SWUpdate**, on the dependency grounds above. Built with OpenSSL signature
   verification (`libubootenv` is not needed — the initramfs design writes no
   env), and **`BR2_PACKAGE_SWUPDATE_WEBSERVER=n`
   and `BR2_PACKAGE_SWUPDATE_INSTALL_WEBSITE=n`** — both default to `y` and
   would add a second HTTP listener plus a website in `/var/www/swupdate`,
   against the default-deny ruleset and the loopback-only backend binds we
   established 2026-08-12. Drive it from the existing console instead.
   (`BR2_PACKAGE_SWUPDATE_USB` depends on systemd and is unavailable on busybox
   init; a manual USB path is still possible via the console.)
2. **A/B, not recovery-mode.** The inactive slot is written while the product
   keeps running; a failed or interrupted write simply never gets switched to.
   Recovery-mode would mean downtime plus a non-atomic overwrite of the running
   rootfs. Rockchip's recovery path is a stub here in any case.
3. **Slot selection in an initramfs, slot state in `misc`** (see "Chosen
   design"). `misc` rather than the U-Boot environment because the env
   partition has no redundant copy (above), and because keeping the AVB record
   format preserves the option of handing slot selection back to the
   bootloader later without a fleet migration.
4. **`idblock` (SPL) is never written by an update.** It is single-copy; a
   failed write bricks to MaskROM. Reserve it for full reflash. This is the
   irreducible residual risk and belongs in the Annex I risk assessment.
5. **Application-layer signature verification; do not burn secure-boot fuses.**
   Fusing is irreversible and destroys the recovery path. It defends against
   physical access, a lower-ranked risk for a cabinet-mounted gateway than the
   update channel itself. Document as an Article 13 risk decision; revisit
   later if the threat model changes. (`CONFIG_SPL_RSA` stays available if so.)
6. **Operator-initiated, not automatic.** No phone-home. It contradicts the
   default-deny firewall and the "isolated machine control network" deployment
   assumption in the Annex II fact sheets. CRA permits this where automatic
   updates are inappropriate — record it as a documented decision, and satisfy
   the "notification of available updates" expectation via a console banner
   plus the `security@joralllc.com` announcement list.
7. **One shared platform component.** Both products ride the same rootfs; the
   updater, the `.swu` format and the signing key are platform-level, built
   once.

## Prerequisite — persistent state must leave the rootfs

**This is the blocking prerequisite and it is not optional.**

Verified today:

- SatiSense config: `/etc/intelligence-edge/gateway.json` (`core/main.c:44`)
- Media-gateway config: `/etc/media-gateway/gateway.conf`, `t1s.conf`
  (`include/media_gateway.h:133-134`)
- Media-gateway per-unit TLS: `/etc/media-gateway/web-cert.pem`, `web-key.pem`
- The 0600 secrets sidecar sits alongside `gateway.json`

All of that is **inside the rootfs**. An A/B swap today would give the operator
a unit that has lost its configuration, its MQTT/OPC UA/LLM credentials, its
admin password change (reverting to the forced-change state), and its TLS
identity — every client that pinned the old fingerprint would break. That is a
factory reset dressed up as an update.

By contrast the **audit log is already correct**: it lives on `/userdata`
(`web/cgi-lib/webauth.sh:55`, `AUDIT_DIR=/userdata/satisense`) and deliberately
survives factory reset (`scripts/factory-reset.sh:46-48`). That is the pattern
to extend.

**Phase 0 work:** move config, secrets sidecar and per-unit certificates to
`/userdata/<product>/`, leave a compatibility read path for units flashed
before the change, and confirm the factory-reset semantics still hold (reset
must wipe config but preserve the audit trail — the two now live on the same
partition, so the boundary has to be explicit). Update
`docs/compliance/cra-annex2-facts.md` in both trees.

This phase stands on its own merits regardless of the updater, and with no
units deployed it needs **no compatibility read path** — just move the paths
and re-run the bench acceptance checks (config survives reboot, factory reset
wipes config but preserves the audit trail, fingerprints stable across reboot).

## Verification spike (no longer blocking the design, ~2-3 days)

The initramfs design removes the bootloader question that previously gated the
layout. What remains to verify on the bench, and can run in parallel with
Phase 0:

- **(a) FIT-with-ramdisk boots on this board** — extend `boot.its` following
  the `rv1106-boot-tb-ramdisk.its` pattern, confirm U-Boot proper loads it and
  the initramfs gets control. (`CONFIG_BLK_DEV_INITRD=y` already set.)
- **(b) An SPL_AB build tolerates our `misc`** — SPL was built with
  `CONFIG_SPL_AB=y`, so confirm that a valid AvbABData record in `misc` (and
  an absent/invalid one — `spl_ab_data_read()` self-initialises) does not
  disturb the boot path while U-Boot proper, which lacks `CONFIG_ANDROID_AB`,
  continues to resolve unsuffixed partition names.
- **(c) `switch_root` onto either rootfs slot by device index** works with the
  new `blkdevparts` string.

Fallback if (a) fails (unlikely — the templates are vendor-provided): the
`CONFIG_ANDROID_AB` or `CONFIG_SPL_KERNEL_BOOT` bootloader routes surveyed
earlier remain available; the partition layout below already reserves for them.

## Partition layout — **FROZEN 2026-08-19** (one-way door #1)

**This is the shipped table.** It is the value of `RK_PARTITION_CMD_IN_ENV` in
`project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk`,
and it is the layout every release since 2026.08.2 has been delivered onto:

```
32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),512M(oem),512M(userdata),1536M(rootfs_a),1536M(rootfs_b)
```

| # | Partition | Offset | Size | Written by an update? |
|---|---|---|---|---|
| p1 | `env` | `0x00000000` | 32 K | no |
| p2 | `idblock` | `0x00008000` | 512 K | no |
| p3 | `uboot` | `0x00088000` | 256 K | no |
| p4 | `misc` | `0x000C8000` | 4 M | slot record only (`misc_ab`) |
| p5 | `boot` | `0x004C8000` | 32 M | no — kernel + selector initramfs, single copy in v1 |
| p6 | `boot_b` | `0x024C8000` | 32 M | no — **reserved, empty in v1** |
| p7 | `oem` | `0x044C8000` | 512 M | **no — reflash only** |
| p8 | `userdata` | `0x244C8000` | 512 M | no — survives updates *and* factory reset |
| p9 | `rootfs_a` | `0x444C8000` | 1536 M | yes — slot A |
| p10 | `rootfs_b` | `0xA44C8000` | 1536 M | yes — slot B |

4165 MiB of the nominal 8 G eMMC. Notes:

- **The draft in this section until 2026-08-19 was wrong** and had been for the
  whole implementation: it wrote `uboot_a`/`uboot_b` and `boot_a`, which the
  board profile never carried and no unit was ever flashed with. Nothing was
  built from it — the board config was always the real source — but it is the
  reason the freeze now has a gate rather than a paragraph.
- `misc` must **not** carry a slot suffix — `spl_ab_append_part_slot()`
  special-cases the name.
- `uboot` and `boot` are **single-copy**. The A/B design puts slot selection in
  an initramfs inside `boot`, so the kernel does not need a slot; `boot_b` is
  reserved, and empty, purely so kernel-slot protection can ship later **through
  the updater** without repartitioning. It is the escape hatch for the one
  thing this layout does not protect.
- 1536 M per rootfs slot against a **117 MiB** packed image (2026.08.5) — 13×
  headroom. The slot is oversized on purpose: it is the one dimension that
  cannot be widened after shipment.
- `userdata` doubled to 512 M (from the stock 256 M) because Phase 0 moves
  config, secrets and certificates onto it alongside the audit log. Measured
  use is 18 MiB — 3%. Growing it further to 1024 M was considered and declined
  on 2026-08-19: the audit log is bounded by rotation at 4 MiB per product
  (`AUDIT_MAX_BYTES` × `AUDIT_KEEP`, rootfs variables that ship through the
  updater), so on-device retention is not limited by the partition, and no
  other claim on the space could be priced. Revisit only against a real
  requirement, and before first shipment.
- `oem` and `userdata` stay single-copy: they must **survive** a slot switch,
  which is the entire point of Phase 0. For `oem` that is also a liability, not
  only a feature — see item 14 in the CRA plan.
- ~3 G is left **unallocated at the tail**, and that is deliberate. Appending a
  partition there shifts no existing index, so it is the only layout change a
  fielded unit could survive. Nothing may be inserted before p10. It is also
  where a later `userdata` increase would come from, if one is ever justified:
  growing p8 moves the `rootfs_a`/`rootfs_b` byte offsets but **no index**, so
  `sw-description.in` and the `PARTNAME`-based initramfs are unaffected.

### What the freeze actually consists of

The table is written once and consumed in five places. Two are generated from
it and can never disagree; three are hand-maintained and can:

| Consumer | Derived? | What a drift costs |
|---|---|---|
| `-IPC-AB.mk` `RK_PARTITION_CMD_IN_ENV` | source of truth | — |
| `output/image/.env.txt` (kernel `blkdevparts`) | generated | — |
| shipped `S20linkmount` (`/dev/block/by-name`) | generated | — |
| `tools/{linux,windows}/SocToolKit/ipc.json` | **hand-maintained byte offsets** | the factory station flashes an image over the wrong partition |
| `ab-boot/swupdate/sw-description.in` (`/dev/mmcblk0p9`, `p10`) | **hand-written indices** | an update installs onto something that is not a rootfs slot |
| this document | **hand-written** | the technical file describes a product we do not ship — which is what happened above |

Neither hand-maintained failure shows up in a build. Both are silent until
hardware. So the freeze is enforced by
**`scripts/compliance/check-partition-layout.sh`**, wired as **`./build.sh
partitions`**: it holds the frozen string as its own constant — not read from
the board config, or it could not fail — and asserts every consumer against it,
plus the structural invariants (`misc` unsuffixed, slots equal, `oem`/`userdata`
single-copy, contiguous from 0, fits the part) and image occupancy against each
frozen size. It needs no build; with one present it also checks the generated
artifacts and the packed images.

### Known asymmetry, deliberately not fixed before the freeze

`RK_PARTITION_FS_TYPE_CFG` lists `rootfs_a@IGNORE@ext4`, so the generated
`S20linkmount` calls `mount_part rootfs_a`, and its `resize2fs` runs only when
the running root *is* `rootfs_a`. **Slot A therefore grows its filesystem to
1536 M on first boot and slot B never does** — a unit running on B has the
117 MiB filesystem the image was packed at, with ~2.5 MB free.

It is benign today: `/var/log`, `/var/tmp` and `/var/spool` are symlinks to the
`/tmp` tmpfs, all mutable state lives on `/userdata` (Phase 0), and the rootfs
is not written at runtime. It is recorded here rather than fixed because it is
**not a one-way door** — `S20linkmount` is generated into the rootfs, which an
update replaces wholesale, so adding `rootfs_b` to the FS-type list ships as an
ordinary release. Changing resize behaviour on both slots days before freezing
the layout would want its own bench pass to buy nothing.

### Timing: freeze before first shipment, not before the updater is finished

With no units in the field there is no retrofit problem — but the moment the
first customer unit ships, the layout above is frozen for that unit's lifetime.
So the sequencing is:

1. **Before first customer shipment (hard):** partition layout, Phase 0 state
   migration, `misc` provisioning, both trusted public keys in the image, the
   `.swu` format versioned. A unit shipped with these can receive everything
   else as an update.
2. **Any time after (soft):** the SWUpdate daemon itself, the console UI, the
   health-check service, delta updates, read-only rootfs. If shipment pressure
   demands it, a unit can ship with the layout + keys but before the updater
   daemon is polished — its first update is then delivered as a signed `.swu`
   applied from the console once the feature lands.

Do not ship a single revenue unit on the old single-slot layout. That would
recreate, at fleet size one and growing, exactly the truck-roll problem this
plan exists to avoid.

## Work breakdown

Split by the shipment gate. **Pre-ship** items are the one-way doors; **post-ship**
items can land in any release delivered through the updater.

**Pre-ship (must precede the first customer unit):**

| # | Item | Depends on | Rough size |
|---|---|---|---|
| 0 | **Persistent state → `/userdata`** on both products (no compat shim needed — nothing deployed) + factory-reset boundary | — | ~1 week |
| 1 | **Verification spike** (a/b/c above): ramdisk FIT boots, SPL_AB tolerates `misc`, switch_root by index | — | 2–3 days |
| 2 | Partition layout frozen; `blkdevparts` + `sys_bootargs` updated; board config + `.env.txt` + docs | 1 | days |
| 3 | **Initramfs slot-selector**: read/decrement/write `AvbABData` (32 bytes, network byte order, CRC32), mount slot, switch_root; shared `misc` I/O library also used by item 4 | 1, 2 | ~1 week |
| 4 | `misc` tools for Linux: mark-active / mark-successful / status (used by SWUpdate hook, health check, console) | 3 | days |
| 5 | Key generation + **two trusted public keys baked into rootfs** (active + rollover spare); signing step in release process; custody per product decision | product decision | days + policy |
| 6 | ~~`.swu` format + `./build.sh swu`~~ — **done 2026-08-14** (`sw-description.in` with version + per-image sha256, two-slot `stable` modes; the target signs with the DEV key until the ceremony, supports the offline `--sig` flow after, and refuses any artifact the image's staged trust store rejects) | 2 | done |
| 7 | ~~`misc` provisioning at manufacture~~ — **done 2026-08-14**: the image set ships a pre-initialized `misc.img` (4 M, `misc_ab init` factory record A={15,7,0}/B={14,7,0}), flashed by update.img / tftp / SocToolKit alongside everything else; initramfs self-init remains the fallback for a blank or corrupted `misc` | 3 | done |

**Post-ship (deliverable through the updater itself):**

| # | Item | Depends on | Rough size |
|---|---|---|---|
| 8 | ~~Buildroot: `swupdate` enabled, webserver/website **off**, OpenSSL selected~~ — **done 2026-08-14** (`swupdate-joral.config`: CMS via OpenSSL, no webserver; stock S80swupdate daemon overridden inert in the board overlay) | — | done |
| 9 | ~~Console UI on both products~~ — **done 2026-08-14** (shared `api-update.sh` CGI from `ab-boot/web/`, panels on both consoles; upload is verified ON-DEVICE via `swupdate -c` before it is accepted, apply targets the inactive slot and `mark-active`s it) | 8 | done |
| 10 | ~~Health-check + `mark_successful` on first good boot~~ — **done 2026-08-14** (`S99ab-health`: daemon liveness only, NOT ports — operator config choices must never trigger rollback) | 4 | done |
| 11 | Bench validation (below) | all | 1 week |
| 12 | Manuals, `cra-annex1-matrix.md` row #7, `cra-annex2-facts.md`, release process | all | days |
| 13 | Later, as needed: read-only/squashfs rootfs, kernel A/B via reserved `boot_b`, delta updates, encrypted `.swu` | 11 | unscoped |

Items 8–12 should still land well before 11 December 2027, and realistically
before any significant fleet exists — "post-ship" means they don't gate the
*first* unit, not that they are optional. Item 10 is the one most often skipped
and it is load-bearing: `tries_remaining` counts down on every boot until
something in userspace declares the slot good.

## Signing and key custody — product decision required

Two things Carl must decide before item 7, and they gate the security value of
the whole feature:

1. **Where the signing key lives.** Offline / HSM with a documented release
   ceremony, versus a key on the build machine. A key on CI means the update
   path is exactly as trustworthy as the CI box. Recommend offline, with the
   ceremony written down and a named second holder.
2. **Key rollover.** Bake a *second* trusted public key into the rootfs from
   day one, unused, so a key can be rotated without a truck roll. Retrofitting
   this later is a fleet-wide reflash.

Adjacent, same conversation: the **declared support period**, which sets how
long updates are promised and therefore how much this is worth.

### Bench results 2026-08-14 (items 1-4, 7, 8 PASSED on hardware)

| # | Item | Result |
|---|---|---|
| 1 | Slot boots, `misc` reports correct state | **pass** |
| 2 | Signed `.swu` applies to the standby slot; reboot lands on it | **pass** — `last_boot=b`, `slot_b successful_boot=1` via S99ab-health |
| 3 | Tampered `.swu` rejected before any write | **pass, both halves** — payload byte flip → sha256 mismatch; signature byte flip at DER offset 1400 → `ossl_rsa_verify: bad signature`. Both `fw_upload result=fail reason=verify_failed`, file deleted, never staged |
| 4 | Wrong-key `.swu` rejected | **pass** — signer does not chain to the image trust store |
| 7 | Broken slot → automatic rollback | **pass** — installed to slot a, zeroed its first 4 MB, rebooted: initramfs failed the mount, set `slot_a priority=0 bootable=no`, fell back to b and booted clean **in ONE boot, not seven** |
| 6 | Power cut mid-write | **pass** — power pulled at ~50% of an install to slot a: the unit booted the old slot (b) clean, slot a was NEVER armed (`mark-active` only runs on a clean swupdate exit), and re-running the same install afterwards succeeded |
| 8 | Config, credentials, certificates, audit log survive the switch | **pass** — password, `gateway.json` and ENIP config all intact after the A→B switch |

| 9 | Factory reset works from both slots | **pass** (operator-confirmed) |
| 10 | Firewall, console HTTPS, OPC UA Sign&Encrypt, CAN, MQTT TLS after an update | **pass** (operator-confirmed) |
| 5 | Downgrade attempt behaves as specified | **now testable, bench-pending** — the version field became orderable 2026-08-15 (below); host-verified by 47 checks driving the real CGI. The bench leg is: upload an older `.swu`, expect the console to refuse it until `DOWNGRADE` is typed, and both audit records to name the two releases |

Round trip closed: updates verified in BOTH directions (a→b and b→a), both
slots healthy and `successful_boot=1` at the end. **9 of 10 items pass on
hardware; item 5 is blocked by a design gap, not by a test.**

### Item 5 / one-way door #4 — CLOSED 2026-08-15

*The section below is the 2026-08-14 finding, kept as written. What changed:*

**The release identity is now `YYYY.MM.PATCH` and the console gates
downgrades.** `media/joral/RELEASE_VERSION` (currently `2026.08.1`) is the one
tracked source; ab-boot's `make install` stamps it into the image as
`/etc/sw-versions` in SWUpdate's own format, per slot, and **fails the build**
if the value is not a well-formed identity. Ordering, validation and the
confirmation phrase live in one place, `ab-boot/web/swu-version.sh`, sourced by
all three callers — `./build.sh swu`, the console CGI and `make install` — so
the build and the device cannot disagree about which of two releases is newer.

Three design points worth keeping:

- **The manifest version is read back OUT of the packed rootfs** (`debugfs -R
  "cat /etc/sw-versions"`), never from `RELEASE_VERSION` a second time. A unit
  believes the rootfs it boots, so a version asserted beside the payload rather
  than derived from it can disagree with it — and the failure is invisible
  until an operator installs. There is deliberately **no fallback**: an early
  revision of `build_swu()` fell back to the staging tree "helpfully" and
  packed `2026.08.1` over a rootfs carrying no version at all, which is exactly
  the defect the door exists to close. `./build.sh swu` now refuses to pack an
  image with no identity, refuses one whose identity is unorderable, and
  refuses when the staging tree names a *different* release than the packed
  image (that means the image predates the last media build).
- **The gate is warn-and-confirm, not `install-if-higher`.** SWUpdate's own
  version gate would make a rollback impossible, and rolling back to a
  known-good release is a legitimate recovery action — one an operator may need
  precisely when the automatic A/B rollback has already been consumed. So the
  gate lives in the console, where the operator and the audit log are: anything
  not ordered `newer` or `same` needs the typed phrase `DOWNGRADE`, re-checked
  server-side, and the attempt is audited either way with `from=`/`to=`.
  Be honest about what this buys: it does **not** stop an attacker who already
  holds console credentials — they can type the phrase. It converts a *silent*
  signed rollback into a warned, explicitly confirmed and recorded one.
- **`unknown` is refused by default.** A unit whose own version cannot be read
  — every image built before this scheme — must ask rather than assume. A gate
  that defaults open in that state is a gate that does nothing on exactly the
  units that have it.

Comparison is field-by-field **numeric**, never a string compare: `2026.08.10`
is newer than `2026.08.9`, and every lexicographic shortcut inverts that. The
tenth patch of a month is not an exotic case — it is where a release has seen
the most fixes, so an inverted gate would nag on routine upgrades and stay
quiet on the rollback that mattered.

Tests: `ab-boot/tests/test_swu_version.sh` (68 checks) pins the comparator and
the stamp; `ab-boot/tests/test_update_gate.sh` (47) drives the **real CGI**
through the gate against a scratch tree via a new `SWU_PREFIX` path root — the
same idiom as the factory reset's `MG_RESET_PREFIX`, so the shipped script is
the tested script — and also fails if either product's instantiated copy of the
CGI has gone stale against the template. Both suites were confirmed to FAIL
against the code mutated back to a lexicographic compare, to a permissive
`unknown`, to a case-insensitive phrase check, to a gate applied to upgrades,
and to an audit line without the version transition.

**Bench 2026-08-15 — the identity half is CONFIRMED on hardware, the gate half
is not.** A unit flashed with the new image reports `release 2026.08.1` in the
SatiSense topbar and in the Firmware update panel, read from `/etc/sw-versions`
on the slot it booted (`last_boot=b`), so the chain `RELEASE_VERSION` → stamp →
packed rootfs → console holds end to end on a device.

What that run did **not** prove, and the reason is worth stating: the staged
package was `2026.08.1` against a running `2026.08.1`, which orders `same`, so
Install was correctly offered with no confirmation. That is the
*no-friction-on-the-normal-path* half. **The refusal has still never run on
hardware** — it needs a `.swu` built from an older `RELEASE_VERSION` (see the
bench leg in the verification table), and the check that actually matters is
the CGI driven directly with `curl`, not the disabled button: a control, not a
screen.

*A caution learned the same day, from an hour spent chasing a phantom:* a
console upload that fails verification is not evidence about the package until
the bytes on the device are hashed. `swupdate`'s "Image invalid or corrupted"
was traced through signature, trust store, manifest limits and slot selection —
all sound — before `ls -l` showed a **614 KB fragment** of a 114.5 MB package
left on `/userdata` by an incomplete transfer. Hash the staged file first; every
other hypothesis is downstream of that.

### The original finding (2026-08-14)

`build_swu()` sets the release identity from
`git describe --always --dirty`, which on this untagged tree yields a bare
commit hash (`314eec228-dirty`). A hash has **no order**, so:

- nothing can decide whether a `.swu` is newer or older than what is running;
- the console's advertised downgrade policy ("the CGI warns and requires
  explicit confirmation", `sw-description.in`) is **not implemented** — the
  version is displayed but never compared. That claim was aspirational and
  is corrected here;
- SWUpdate's own version gate is unused (`CONFIG_SW_VERSIONS_FILE` points at
  `/etc/sw-versions`, but no per-image `version` + install-if-higher rules
  are emitted).

This matters beyond the test: the version field is **one-way door #4** — a v1
unit must still be able to reason about a 2030 image. It needs a monotonic
scheme decided BEFORE first shipment. Recommended: a date-ordered release
identity (`YYYY.MM.PATCH`, e.g. `2026.08.1`) carried in the manifest as the
sortable `version`, with the git hash kept alongside as build provenance.
Then item 5 becomes: install an older `.swu`, expect a console warning plus
an explicit confirm, with the attempt audit-logged either way.
Until it is decided, an attacker (or an operator) can roll a unit back to a
known-vulnerable release without any warning — the rollback is *signed*, so
signature verification cannot catch it. Rated in the Annex I risk assessment.

**Console-vs-updater defect found by testing item 6's recovery.** The shell
path (`swupdate -i … -e stable,a` + `misc_ab mark-active`) installed in
seconds, while the console Install on the same slot did nothing. Cause: the
CGI stored `$!` — the pid of `setsid`, which can exit the moment it forks —
so `?action=progress` saw "nothing running" and the UI called a live install
a failure. Fixed: the worker writes its own pid file, the CGI verifies the
worker exists before claiming it started, and both consoles tolerate an
initial `idle` (worker not yet scheduled) instead of reporting failure.

**Caveat found while testing — `/proc/cmdline` is NOT evidence of the running
slot.** `sys_bootargs` is static (`root=/dev/mmcblk0p9`) and the initramfs
ignores it, mounting the selected slot itself before `switch_root`. Only
`misc_ab status`' `last_boot=` names the running slot. The same staticness is
a latent trap: if the initramfs ever fails to run (e.g. a stock `boot.img` is
flashed), the kernel boots rootfs_a DIRECTLY and silently ignores A/B — which
is exactly the 2026-08-14 failure. `build_ab_bootimg()` prevents the build
side of that; a runtime "the selector did not run" warning is still worth
adding (the health check could assert a marker the initramfs leaves behind).

## Verification plan (bench, RV1106 hardware)

Nothing here is provable by code review — the two defects found in TC-S3 were
both invisible in a read and only surfaced on hardware. Minimum set:

1. Slot A boots; `misc` reports A active, successful, correct tries.
2. Signed `.swu` applies to slot B while the product keeps serving; reboot
   lands on B.
3. **Tampered `.swu` is rejected before any write** — flip a byte in the
   payload and in `sw-description.sig` separately.
4. **Wrong-key `.swu` is rejected.**
5. **Downgrade attempt** behaves as specified: an older `.swu` is refused with
   the two releases named until `DOWNGRADE` is typed, then installs; the
   refusal and the confirmed install both appear in the security event log with
   `from=`/`to=`. Repeat with a package the unit cannot order (built before
   release numbering) — it must ask, not assume.
6. **Power cut mid-write** to the inactive slot → unit still boots the old
   slot, cleanly.
7. **Deliberately broken slot B** (rootfs that mounts but whose services never
   come up, and one that doesn't mount at all) → the initramfs exhausts tries
   and falls back to A. Confirm the console reports the rollback rather than
   silently presenting the old version as current.
8. **Configuration, certificates, admin password and audit log all survive**
   the switch — the Phase 0 acceptance test, and the one most likely to be
   assumed rather than checked.
9. Factory reset still works from both slots.
10. Firewall, console HTTPS, OPC UA Sign&Encrypt, CAN, MQTT TLS all still pass
    after an update — the standing bench pass, re-run.

## CRA mapping

- **Annex I #7 (update mechanism)** — the row this closes. Signed, verifiable,
  remotely applicable without physical access, with automatic rollback.
- **Annex I #1 (secure by default)** — verification is not operator-defeatable.
- **Annex I #6 (logging)** — every update attempt, signature failure and
  rollback becomes an audit record on `/userdata`.
- **Annex I Part II (vulnerability handling)** — this is what makes the CVE
  gate actionable on *shipped* units rather than only at manufacture, and it is
  what makes the declared support period affordable to honour.
- **Annex II** — the fact sheets' "update procedure" section is currently
  "host reflash only"; it changes, and the manuals change with it. SatiSense's
  reflash procedure is *undocumented today* (`cra-compliance-plan.md:28`) —
  documenting the existing procedure honestly is a free accuracy fix that
  should not wait for any of the above.

## Open questions

- Is `misc` initialised at manufacture (flash tooling) or lazily on first
  boot? `spl_ab_data_read()` self-initialises an invalid record, and the
  initramfs can do the same — decide which owns it and document it (work item 7).
- Does `oem` need to be A/B? Depends on what it holds — 38 M of 512 M is in
  use and its contents were not surveyed here. If product code lives there, it
  must be A/B or must move to the rootfs.
- Delta updates (`librsync` / rdiff handler) — worth it at 151 M per image, or
  is a full image fine? Recommend full images first; simpler to verify.
- Does the media-gateway need the same `/userdata` migration semantics as
  SatiSense, or does its config legitimately differ?
- Where does the initramfs live in the build: a buildroot
  `BR2_TARGET_ROOTFS_CPIO` second config, or a hand-rolled busybox cpio in
  `build.sh` following the `build_recovery()` pattern? (Small either way; the
  hand-rolled route avoids a second buildroot pass.)
