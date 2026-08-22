# Kernel port kit — 5.10.160 → 5.10.252

*Created 2026-08-21. This directory holds the local kernel delta as a portable
patch series plus the procedure for moving the vendored kernel to a newer
Rockchip base. The rationale for the target lives in
[`kernel-currency-plan.md`](../kernel-currency-plan.md).*

## What is here

Six patches, in apply order, against the LuckfoxTECH base this fork forked
from (`824b817f8`, kernel 5.10.160):

| Patch | Contents | Conflict risk on a 5.10.y bump |
|---|---|---|
| `0001-net-phy-microchip-10base-t1s.patch` | `microchip_t1s.c` (251 lines) + `drivers/net/phy/{Kconfig,Makefile}` hooks | **low** — one new file, two one-line hooks |
| `0002-net-ethernet-oa-tc6.patch` | `oa_tc6.c` (1403) + `include/linux/oa_tc6.h` + `drivers/net/ethernet/{Kconfig,Makefile}` hooks | **low** — new files, two one-line hooks |
| `0003-net-ethernet-lan865x.patch` | `lan865x/` (640) + `microchip/{Kconfig,Makefile}` hooks | **low** — same shape |
| `0004-dts-rv1106g-luckfox-pico-ultra.patch` | LAN8651 on SPI, MCP251XFD CAN (40 MHz osc, GPIO CS), NPU node enabled | **medium** — edits the vendor board DTS |
| `0005-dts-rv1103g-luckfox-pico-plus.patch` | dev-board equivalent | **medium** — same |
| `0006-defconfig-t1s-can-bridge.patch` | 21 symbols: T1S, CAN + J1939 + VCAN + MCP251XFD, bridge/VLAN, IP multicast | **low** — regenerate with `olddefconfig` |

**The series is verified**: applied to a clean checkout of `824b817f8` it
reproduced the 5.10.160 `sysdrv/source/kernel` byte-for-byte, and it then
applied cleanly onto Rockchip's 5.10.252 to produce the kernel now in the tree.
Note the tense — since the 2026-08-22 migration `sysdrv/source/kernel` **is
5.10.252**, so the series no longer reproduces it; it reproduces the *local
delta* on top of whichever base it is applied to, which is the thing worth
carrying forward. Re-verify after any edit — a patch kit nobody has applied is
a plan, not a kit.

## Why a curated series rather than the 20 original commits

The local history contains contradictory tuning iterations — the LAN8651 SPI
clock is set to 25 MHz, then 15, then 10, then back to 15 across four
commits, and the MCP251XFD clock likewise. Replaying that onto a new base
means resolving conflicts against intermediate values that were themselves
superseded. These six patches carry the *end state* only, which is what the
running product actually is.

The original commits stay in the history; nothing is lost. `git log
824b817f8..main -- sysdrv/source/kernel` is the record.

## Procedure

**1. Get the target tree.** Rockchip's `develop-5.10` is the base — it
carries RV1106 (`arch/arm/boot/dts/rv1106.dtsi`, `drivers/rknpu`) and is at
5.10.252 as of 2026-08-21. It is a large fetch; a single-branch shallow clone
is enough:

```sh
git clone --depth 1 --branch develop-5.10 \
    https://github.com/rockchip-linux/kernel.git /path/to/rk-5.10.252
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) ' /path/to/rk-5.10.252/Makefile   # confirm 5.10.252
```

**2. Confirm the Luckfox delta first.** This fork's kernel is Luckfox's, not
Rockchip's bare tree, and the difference is not empty — Luckfox carries board
DTS files and defconfigs Rockchip does not. Diff before replacing anything:

```sh
diff -rq /path/to/rk-5.10.252 sysdrv/source/kernel | grep -v '^Only in sysdrv' | head -50
```

Anything Luckfox-only under `arch/arm/boot/dts/` and `arch/arm/configs/`
must be carried across by hand. **This step is the real work**; the six
patches are the easy part.

**3. Swap the tree, then re-apply.**

```sh
rm -rf sysdrv/source/kernel && cp -a /path/to/rk-5.10.252 sysdrv/source/kernel
rm -rf sysdrv/source/kernel/.git
# carry across the Luckfox-only files identified in step 2, then:
for p in media/joral/kernel-port/patches/*.patch; do git apply "$p" || echo "CONFLICT: $p"; done
```

**4. Regenerate the defconfig** rather than trusting the patch:

```sh
make -C sysdrv/source/kernel ARCH=arm luckfox_rv1106_linux_defconfig
make -C sysdrv/source/kernel ARCH=arm olddefconfig
```

Then confirm the 21 symbols from `0006` survived — a silently dropped
`CONFIG_CAN_J1939` is a product that builds and does not work.

**5. Build and check the module set.** The out-of-tree modules that must
still build are `rknpu` (the product uses it) and `pwm_bl`. `rockit` and
`mpp_vcodec` ship as pre-generated assembly against the 5.10.160 kABI — they
are **no longer in the image** (the `oem` payload was emptied 2026-08-21), so
they are not blockers. Wi-Fi drivers are out (`RK_ENABLE_WIFI=n`).

**6. Gates, then hardware.** `./build.sh cve` will move — record the before
and after. Then a bench pass: the T1S link and PLCA, CAN at both bitrates,
the NPU node, eMMC, GMAC, and an A/B update. **A kernel change cannot be
delivered by the updater** (the `.swu` carries only `rootfs.img`; the kernel
lives in the single-copy `boot` FIT), so this must be a reflash and must
happen before first shipment.

## Measured against the real target, 2026-08-21

Step 2 has now been run. The trees differ in **10,391 files**, with 230
Luckfox-only and 880 Rockchip-only — but almost all of that is 92 stable
releases touching the rest of the kernel, which is the point of the exercise.
On this board's critical path the divergence is almost nil:

- `rv1106-pinctrl.dtsi` — **byte-identical**
- `rv1106.dtsi` — **one node**, 7 diff lines out of 1558
- every node the Ultra DTS references (`spi0`, `npu`, `i2c3`, `gmac`) exists
  in both

**The hand-carry set is 17 Luckfox DTS/DTSI files and 9 config files**
(`luckfox_rv1106_linux_defconfig`, the `rv1106-bt.config` fragment the board
profile uses, and seven others). Neither tree lists the Luckfox dtbs in
`arch/arm/boot/dts/Makefile` — the build makes the dtb from the `.dts` name
by pattern rule — so no Makefile wiring travels with them.

Most of the 230 Luckfox-only files are **not** part of the carry set: the bulk
are `drivers/net/wireless/rockchip_wlan/cywdhd` Wi-Fi sources, which this
product does not build (`RK_ENABLE_WIFI=n`) and does not ship.

The merged tree can be **built without modifying `sysdrv/source/kernel` at
all**, which is a better shape than the in-place swap step 3 describes: the
product tree stays pristine until the build is proven. It needs one change to
`sysdrv/Makefile.param` and it does **not** extend to redirecting the objects
directory — see *Building an image* below before trying it, because the
obvious version of this trick produces an image containing the old kernel and
exits 0.

## THE OTP NODE — read this before carrying board files across

The one divergent node in `rv1106.dtsi` is the **OTP controller's clock
list**, and the SoC OTP is one of the two sources the secrets sidecar is keyed
on (`core/secretbox.c`, HKDF over OTP + eMMC CID). Each tree is internally
consistent and they disagree:

| Tree | `drivers/nvmem/rockchip-otp.c` expects | `rv1106.dtsi` provides |
|---|---|---|
| Luckfox 5.10.160 | 6 — `usr, sbpi, apb, phy, arb, pmc` | 6 |
| Rockchip 5.10.252 | 4 — `usr, sbpi, apb, phy` | 4 |

**Take Rockchip's driver and its dtsi node together; do not carry Luckfox's
OTP node across.** The tempting move — preserving "our" board files wholesale
— mismatches them, `clk_bulk_get` asks for clocks the node does not name, the
OTP probe fails, and `secrets_at_rest.mode` degrades **with no error anyone
would see**. It would also survive every host test, because the host suite
fakes the binding sources.

`secrets_at_rest.mode = encrypted` in `diagnostics.json` is therefore a
**required bench assertion after this port**, not an assumption.

## Executed, confirmed on hardware, and migrated in-tree

The procedure above has been run end to end, **confirmed on hardware**, and
the result is now the product kernel.

- **2026-08-21** — built out of tree (staging tree + redirected objects), with
  `sysdrv/source/kernel` untouched, so the port could be abandoned by deleting
  two directories.
- **2026-08-21, on the board** — flashed; **T1S, the OPC UA server and the CAN
  gateway confirmed working.**
- **2026-08-22** — **migrated in-tree.** `sysdrv/source/kernel` *is* the merged
  tree, `sysdrv/Makefile.param` is back to unmodified vendor code, and a plain
  `./build.sh` builds 5.10.252 with no environment variable and no staging
  directory. 10,217 files changed: 9,915 modified, 302 deleted, 1,044 added.
  Rebuilt and re-verified from the migrated tree, all gates green.

The staging directories are no longer referenced by anything and can be
deleted. **The out-of-tree shape below is kept because it is the right way to
run the NEXT re-base** — it lets a candidate kernel be built and proven before
the tree is replaced — not because anything still depends on it.

| Step | Result |
|---|---|
| `0001` microchip_t1s, `0002` oa_tc6, `0003` lan865x | applied clean |
| `0004`/`0005` DTS, `0006` defconfig | already present — the carry set was taken from the current tree, so the end state was already in it. No `.rej` files; content verified by grep, not assumed |
| `make kernel` | **exit 0**, `Linux version 5.10.252` |
| `make drv` | **exit 0**, 24 in-tree modules |
| `rv1106g-luckfox-pico-ultra.dtb` | built, 77937 bytes |

All four carried driver objects compiled into vmlinux — `microchip_t1s.o`,
`oa_tc6.o`, `lan865x.o`, and the `mcp251xfd` trio. The stable-series API
guarantee held: **no driver source needed editing.**

**Defconfig, diffed against the .160 build rather than against the patch.**
1232 symbols enabled before, 1290 after, and exactly **three** lost — all of
them Luckfox-local drivers with no Kconfig entry in Rockchip's tree, so
`olddefconfig` dropped them because the code is absent, not because a
dependency moved:

| Symbol | What it is | Shipped? |
|---|---|---|
| `CONFIG_OF_DTBO` | Luckfox's DT-overlay configfs (`drivers/of/dtbocfg.c`), for `luckfox-config` | no — nothing in this product's boot path loads a `.dtbo` |
| `CONFIG_USB_SERIAL_CH343` | CH343 USB-serial adapter | no — unreferenced |
| `CONFIG_ROCKCHIP_DVBM_PROC_FS` | procfs debug for the video buffer manager | no — video stack is not in the image |

Carrying these forward means carrying three Luckfox driver files across as
well. None is on this product's critical path, so the recommendation is to
**let them go and record it** rather than grow the carry set — but that is a
decision, not a non-event, and this table is where it is written down.

### The OTP node came out right — verified against the built dtb

The failure this document was written to prevent did not happen, and it is now
checkable rather than argued:

- the dtb's `otp@ff3d0000` names **four** clocks — `usr, sbpi, apb, phy`
- `rv1106_otp_clocks[]` in Rockchip's `rockchip-otp.c` is the **same four**
- `rockchip-otp.o` is built into the image

The node still lists six `reset-names`, which looks like a mismatch and is
not: the driver takes its resets through
`devm_reset_control_array_get_optional_exclusive()`, which is unnamed and
takes whatever the node lists. **Clocks are the only named lookup**, and they
match.

This makes the OTP probe correct *by construction* on the build host. It does
not discharge the bench assertion — `secrets_at_rest.mode = encrypted` still
has to be read off real hardware, because the host suite fakes the binding
sources and would pass either way.

### Modules: `make kernel` does not build them, and that bites

`kernel` and `drv` are separate sysdrv targets. Building only `kernel` leaves
`sysdrv/out/kernel_drv_ko` holding the **previous kernel's** modules — a
5.10.252 vmlinux beside 5.10.160 `.ko` files, which is a vermagic mismatch and
a module that will not load. **`drv` must be rebuilt whenever `kernel` is**, and
`rknpu` is the module that makes it matter.

Five modules stay at `vermagic=5.10.160` even after `drv`, because
`sysdrv/drv_ko/{rockit,kmpp,wifi}` ship pre-built binaries rather than
compiling: `rockit.ko`, `mpp_vcodec.ko` and the three `aic8800_*.ko`. **None
reaches the image** — `luckfox-joral-oem-pre.sh` empties the oem payload, and
Wi-Fi is off (`RK_ENABLE_WIFI=n`).

The two rescued modules both rebuilt correctly at `vermagic=5.10.252`, and the
rescue survives a kernel bump without being edited: the hook reads the version
directory out of each module's own vermagic, so they land in
`/lib/modules/5.10.252/` and `$(uname -r)` finds them. That design choice —
made for a different reason — is what makes this port a no-op for the module
loader.

## Building an image out of tree: the trick does NOT reach the firmware

*Applies to a future re-base, not to routine builds — the kernel is in-tree now
and `./build.sh` needs no help. Read this before staging a candidate kernel.*

Building with `KERNEL_DIR=<staging>` and `SYSDRV_KERNEL_OBJS_OUTPUT_DIR=<elsewhere>`
produces a correct kernel and **an image that does not contain it.**
This was measured, not predicted: the first firmware pack of the port shipped
a 5.10.160 kernel and modules in `/lib/modules/5.10.160/`, and exited 0 while
doing it. Two hardcoded paths cause it:

| Where | What it does |
|---|---|
| `sysdrv/Makefile:131` — `ROOTFS_BUILD_ENV := ... drv` | `./build.sh rootfs` **depends on `drv`**, so it silently rebuilds every module against the default kernel tree, overwriting a correct module set with a stale one |
| `project/build.sh:983` — `KOUT=$SDK_SYSDRV_DIR/source/objs_kernel/out` | `build_ab_bootimg` reads the kernel/fdt/resource blobs from the **default** objs directory, so the A/B FIT is built from whatever the last in-tree build left there |

`KERNEL_DIR` could not simply be exported either: `sysdrv/Makefile.param:59` set
it with `:=`, which beats the environment (the `?=` at `sysdrv/Makefile:242`
never gets a say). A command-line override works for one `make`, but
`./build.sh` does not forward one.

**The fix is one character class** — `Makefile.param:59` becomes `?=`, so the
environment can route the whole pipeline while the default is unchanged:

```sh
export KERNEL_DIR=/path/to/rk-5.10.252
rm -rf sysdrv/source/objs_kernel          # holds the previous kernel's objects
./build.sh kernel && ./build.sh rootfs && ./build.sh firmware
```

Leave `SYSDRV_KERNEL_OBJS_OUTPUT_DIR` alone. Objects **must** land in the
default `sysdrv/source/objs_kernel` or `KOUT` reads the wrong blobs. This still
never modifies `sysdrv/source/kernel`.

**Verify the image, not the build log** — the failed attempt exited 0 at every
stage:

| Check | Expected |
|---|---|
| `strings sysdrv/source/objs_kernel/vmlinux \| grep -m1 'Linux version'` | `5.10.252` |
| oem hook line in the firmware log | `rescued rknpu.ko -> /lib/modules/5.10.252/rknpu.ko` |
| `md5sum output/image/boot.img sysdrv/source/objs_kernel/out/boot-ab.img` | identical — else the A/B FIT was not rebuilt |
| `ls output/out/rootfs_uclibc_rv1106/lib/modules` | `5.10.252`, and nothing else |

## Still needing real work, not just `patch`

- **`drivers/rknpu`** — Rockchip's `develop-5.10` has its own copy, newer than
  this tree's. Take theirs; do not merge.
- **The DTS patches** (`0004`, `0005`) edit the Luckfox board DTS, which is
  carried across unchanged, so they apply — but the *result* is a board DTS
  written against .160's vendor dtsi now including .252's. The OTP node above
  is the known instance; a boot pass is what would surface any other.

Within a stable series the kernel's internal APIs do not change (that is what
the stable rules guarantee), so the four driver files should compile
untouched. **That guarantee does not hold across a major bump** — a move to
6.1 would need real driver work, which is the argument in the plan document
for not doing it now.
