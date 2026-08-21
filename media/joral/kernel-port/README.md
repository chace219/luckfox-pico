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
reproduces the current `sysdrv/source/kernel` byte-for-byte. Re-verify after
any edit — a patch kit nobody has applied is a plan, not a kit.

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

## What will need real work, not just `git apply`

- **Step 2's Luckfox-only files.** Unknown until diffed; budget for it.
- **`drivers/rknpu`** — Rockchip's `develop-5.10` has its own copy, likely
  newer than the one in this tree. Take theirs; do not merge.
- **The DTS patches** (`0004`, `0005`) edit the vendor board DTS. If Rockchip
  renamed or restructured nodes between .160 and .252 these will need hand
  fixing — that is the medium-risk row in the table above.

Within a stable series the kernel's internal APIs do not change (that is what
the stable rules guarantee), so the four driver files should compile
untouched. **That guarantee does not hold across a major bump** — a move to
6.1 would need real driver work, which is the argument in the plan document
for not doing it now.
