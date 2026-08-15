# ab-boot — A/B slot machinery for the in-product update mechanism

Part of the SWUpdate design in
[`../swupdate-implementation-plan.md`](../swupdate-implementation-plan.md)
("Chosen design — initramfs-driven A/B"). Status 2026-08-14: **spike artifacts
built and flash-ready, nothing flashed yet.** Phase 0 (state → `/userdata`)
is done in both product trees and host-tested. `build/` now holds the
static busybox, `ramdisk.cpio.gz`, `boot-ab.img` (ramdisk FIT),
`boot-stock.img` (restore path) and `spike-a-flash-notes.txt` (U-Boot flash
commands for spike (a) on the single-slot layout); the tree is lunched on
the `-AB` profile and `output/image/` carries the complete A/B image set
(`boot.img` = the ramdisk FIT, flash via the generated
`tftp_update.txt`/`sd_update.txt`).

## What is here

| Path | What |
|---|---|
| `src/misc_ab.c` | Userspace tool for the AVB A/B record in `misc`. Byte-exact mirror of `common/spl/spl_ab.c` (verified by test with an independent CRC32). Static, no deps. |
| `tests/test_misc_ab.sh` | Host contract test (`make test`): init-record bytes, selection semantics, try burning, rollback, corrupt-record recovery. |
| `initramfs/init` | The slot selector: finds `misc` + `rootfs_a/_b` by PARTNAME from sysfs, `misc_ab select`, mount, `switch_root`. Falls to the other slot immediately when a mount fails. |
| `scripts/mkinitramfs.sh` | Packs a static busybox + static `misc_ab` + `init` into `ramdisk.cpio.gz`. Refuses dynamic binaries. |
| `boot-ab.its` | FIT source = stock `boot.its` + the ramdisk node (modeled on the vendor's `rv1106-boot-tb-ramdisk.its`). |
| `scripts/init.d/S99ab-health` | First-good-boot health check: daemons alive → `misc_ab mark-successful`. Deliberately NOT a port check — operator config choices must never trigger rollback. |
| `swupdate/swupdate.cfg` | Runtime config shipped to `/etc/swupdate.cfg` — pins the trust store; SWUpdate is invoked per-update by the console CGI, never a daemon (stock S80swupdate is overridden inert in the board overlay). |
| `swupdate/sw-description.in` | Template for `./build.sh swu` — one payload, `stable,a`/`stable,b` modes; the CGI targets the inactive slot. |
| `web/api-update.sh.in` | Console CGI template (status/upload/apply/progress/reboot), instantiated into BOTH product trees — edit here, regenerate there (`tests/test_update_gate.sh` fails when a copy goes stale). Paths root under `SWU_PREFIX` so the shipped script is the tested one. |
| `web/swu-version.sh` | Release-identity rules: validate `YYYY.MM.PATCH`, order two releases, read the running version from `/etc/sw-versions`, read a `.swu`'s version, stamp an image. Sourced by `./build.sh swu`, by `api-update.sh` and by `make install` — one comparator, so the build and the device can never disagree about which release is newer. |
| `tests/test_swu_version.sh` | Contract test for the above (`make test`), including the double-digit-patch case every string sort gets backwards. |
| `tests/test_update_gate.sh` | Drives the real CGI through the downgrade gate against a scratch tree (`make test`): refusal without the typed phrase, upgrades unimpeded, `unknown` refused by default, audit records on both paths, and product copies in sync. |
| `../RELEASE_VERSION` | The platform release identity, one line. Stamped into `/etc/sw-versions` by `make install`; a malformed value fails the build. |
| `keys-dev/` (generated) | Per-checkout DEV signing keypair, auto-created by `make install` while `scripts/compliance/keys/` (ceremony output) does not exist. Gitignored. NOT FOR SHIPMENT. |
| `../../project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk` | A/B partition layout board profile (p4 `misc`, p9/p10 `rootfs_a/_b`, `boot_b` reserved). |

## Slot lifecycle

```
 flash/manufacture      misc_ab init            A={15,7,0} B={14,7,0}
 every boot             initramfs: select       burn a try if unproven, mount, switch_root
 services up            S99ab-health:           mark-successful <slot>
 update installed       console CGI:            mark-active <other-slot>
 slot won't mount       initramfs:              mark-unbootable, try the other
 7 failed boots         (tries exhausted)       selection falls back by itself
```

## Bench spike runbook (plan: "Verification spike", 2–3 days)

Prereqs: a unit you can reflash freely; serial console; a **static** busybox
(see mkinitramfs.sh header).

1. **(a) Ramdisk FIT boots.**
   - `make` (cross) here, then `scripts/mkinitramfs.sh <static-busybox> ramdisk.cpio.gz`
   - Copy `ramdisk.cpio.gz` into the kernel objs dir next to `kernel`/`fdt`/`resource`
     (`sysdrv/source/objs_kernel/out/` after a kernel build), rebuild the boot
     image with `BOOT_ITS=$(pwd)/media/joral/ab-boot/boot-ab.its`
     (see `sysdrv/Makefile:504`), flash `boot` only, keep the CURRENT
     single-slot layout.
   - Expect on serial: `ab-boot: FATAL: no 'misc' partition` then a shell.
     That failure IS the pass for (a): FIT+ramdisk loaded, kernel entered
     /init. (`root=` is untouched, so reflashing `boot` with the stock FIT
     restores normal boot.)
2. **(b)+(c) Full A/B layout.**
   - `./build.sh lunch` → the `-AB` board profile; update
     `sysdrv/tools/board/emmc/emmc_fstab` (`/userdata` = p8) and SocToolKit
     `ipc.json` (rootfs.img → rootfs_a, add misc) per the notes in the
     profile; full build; flash everything; `misc` may stay blank
     (self-init) or be `misc_ab init`-ed from the recovery shell.
   - Expect: `ab-boot: slot a -> /dev/mmcblk0p9`, normal system up.
   - `misc_ab status /dev/mmcblk0p4` → slot_a tries burned per boot until
     `mark-successful`; `dd` rootfs_a's first MB, reboot → lands on slot b
     (after `mark-unbootable` path) — the rollback story on real hardware.
   - **(b) specifically:** with a valid record in `misc`, confirm U-Boot
     proper still resolves `boot`/`env` fine (it has no CONFIG_ANDROID_AB, so
     nothing should change — this is the "SPL_AB tolerates our misc" check;
     watch the SPL banner for `A/B-slot:` lines and any partition-lookup
     noise).
3. Record results in the swupdate plan; that closes the spike and freezes the
   layout (one-way door #1).

## Full .swu update test (after the spike phases above)

Prep once: static busybox — the 1.36.1 tarball is already in the buildroot
dl cache (`sysdrv/source/buildroot/.../dl/busybox/`); `make defconfig`, set
`CONFIG_STATIC=y`, cross-make, `file` must say "statically linked". Then
`make` here + `scripts/mkinitramfs.sh <busybox> ramdisk.cpio.gz`.

1. **Flash the A/B image** (spike phase 2): lunch the `-AB` profile, set
   `sysdrv/tools/board/emmc/emmc_fstab` to `/dev/mmcblk0p8`, full build,
   boot.img rebuilt with the ramdisk (`BOOT_ITS=.../boot-ab.its`). Flash via
   the GENERATED `output/image/tftp_update.txt` / `sd_update.txt` — they are
   derived from the new partition table, so offsets are right by
   construction. SocToolKit's `ipc.json` carries old-layout byte addresses:
   do not use it for the AB image until updated. Blank `misc` self-inits.
2. **Baseline:** first sign-in done, some config saved, TLS fingerprint
   noted, `misc_ab status /dev/mmcblk0p4` shows slot a successful (via
   S99ab-health, ~30 s after boot).
3. **Update:** change something visible, `./build.sh firmware && ./build.sh
   swu` **in the same checkout that built the flashed image** (the DEV key
   is per-checkout — a .swu from another checkout is the wrong-key test,
   not the happy path). Console → Utilities → Firmware update: upload
   (expect "verified and staged" — the UNIT checked the signature), install
   (expect "installed to slot b"), reboot (serial:
   `ab-boot: slot b -> /dev/mmcblk0p10`).
4. **Verify the promises:** password/config/fingerprint unchanged; audit log
   carries fw_upload / fw_apply / ab_slot_marked_successful.
5. **Negative set (the compliance evidence):** tampered .swu rejected at
   upload + deleted; wrong-key .swu (other checkout) rejected; corrupt the
   inactive slot after installing to it → initramfs marks it unbootable and
   stays on the good slot; power cut mid-install → old slot boots clean and
   the install re-runs; factory reset works from BOTH slots with the audit
   trail surviving.
6. Record everything in `swupdate-implementation-plan.md` ("Verification
   plan" section, items 1–10); a full pass closes the spike AND the bench
   half of Annex I #7.

## Update flow (implemented 2026-08-14, software-complete, bench-pending)

```
./build.sh firmware                    rootfs.img
./build.sh swu                         sw-description (@VERSION@/@SHA256@) +
                                       CMS signature (DEV key until the
                                       ceremony; offline flow after) +
                                       verify-against-image-trust-store gate
                                       -> joral-platform-<ver>.swu
console: Utilities -> Firmware update  upload    -> swupdate -c (signature +
                                                    hash check, reject+delete
                                                    on failure)
                                       install   -> swupdate -e stable,<inactive>
                                                    then misc_ab mark-active
reboot (console "Reboot now to switch" — explicit, never automatic:
        the operator owns the maintenance window on a machine-control
        gateway; the button appears when misc says the next boot switches,
        and the CGI refuses while an install is still writing)
                                       initramfs boots the new slot
S99ab-health                           daemons up -> mark-successful
                                       (else 7 boots -> automatic rollback)
```

## Deliberately NOT here yet

Any `boot_b` use (kernel stays single-copy in v1), delta updates, and the
production keys (ceremony deferred by decision 2026-08-14 — see
`firmware-signing-and-support-policy.md`; the DEV-key gate stands: no
customer shipment on a DEV-keyed trust store).
