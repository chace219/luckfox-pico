# Kernel and U-Boot currency — decision

*Written 2026-08-21, closing compliance-plan item 5d ("Kernel/U-Boot
currency — report-only today; the remediation is a vendor-base move, so it
needs scoping against Rockchip's releases rather than triage").*

## Recommendation

**Refresh 5.10.160 → 5.10.252 on Rockchip's `develop-5.10`, before first
shipment. Do not move to 6.1. Leave U-Boot alone.** Re-evaluate the next base
on a trigger, not a date.

## Where we are

| | Version | Local delta | NVD matches |
|---|---|---|---|
| Kernel | **5.10.252** in-tree since 2026-08-22 (was 5.10.160) | carried as the six-patch series in `kernel-port/` | **2867**, `report-only` (was **5155**) |
| U-Boot | 2017.09 Rockchip fork | **none** — all 7 commits are Luckfox's | 41, `report-only` |

Both are `MODE=report-only` in `cpe-extra.csv` on the stated grounds that a
vendor kernel is remediated by moving its base, not by dispositioning five
thousand records. That reasoning is sound and unchanged — and the refresh
below is it being acted on rather than merely asserted. What forced the timing
is that 5.10.160 was about to stop receiving fixes at all.

## The date that forces it

**5.10 upstream stable EOL is Dec 2026** — about four months out. The
declared support period is five years from shipment
(`firmware-signing-and-support-policy.md`), so a unit shipped in early 2027
is covered until roughly 2032 on a base that dies within the year.

That is the driver. It is not the CVE count, which is dominated by
subsystems and drivers this SoC configuration does not build.

## Why not 6.1 — verified, and it reverses the obvious answer

Rockchip's `develop-6.1` (6.1.141) does carry RV1106, so it looks like the
natural move. It was checked for the three things that would justify the
cost:

| | `develop-6.1` |
|---|---|
| `oa_tc6` / `lan865x` (the T1S MAC-PHY stack) | **absent** |
| `microchip_t1s` PHY driver | **absent** — it has `microchip_t1`, a different 100BASE-T1 part |
| ethtool PLCA netlink API | **absent** |

So a 6.1 move re-ports all four driver files anyway, across 5.10→6.1 netdev
API churn, and `plca_ctrl.c` keeps its raw `SIOCGMIIREG` path (and with it
the `CAP_NET_ADMIN` requirement that the console's `plca-status` privop verb
exists to satisfy). **It retires none of the local delta.**

And it expires **Dec 2027** — the CRA full-compliance date. The move would
land on a base that dies immediately after.

The only base that *would* retire the T1S backport is **6.13+**, where
`oa_tc6`/`lan865x` landed upstream. Mainline has no RV1106 SoC support at all
— the pending series (Simon Glass, 2026-07-29) adds UART, SD/eMMC, SPI
flash, SARADC, watchdog and GPIO only: no GMAC, USB, CAN, NPU or ISP, and it
is not merged. That convergence is not purchasable today at any price.

## Why the timing is forced

The `.swu` writes only `rootfs.img` to the two rootfs slots
(`ab-boot/swupdate/sw-description.in`). The kernel travels in the `boot` FIT
at p5, and `boot_b` is reserved but unused. **A kernel change cannot be
delivered by the A/B updater — it needs a reflash.**

Before first shipment that costs a rebuild. After it, a field recall. The key
ceremony is already the shipping blocker, so the window is open now and
closes when the first unit leaves.

## Why the port is tractable

The local delta is small and mostly **additive**: four new driver files
(`oa_tc6.c` 1403, `oa_tc6.h`, `lan865x.c` 640, `microchip_t1s.c` 251), three
one-line Kconfig/Makefile hooks, two board DTS files and 21 defconfig
symbols. New files do not conflict on a rebase; they only have to still
compile — and **within a stable series the kernel's internal APIs do not
change**, which is exactly what makes 5.10.252 cheap and 6.1 expensive.

Extracted, curated and **verified** as a six-patch series in
[`kernel-port/`](kernel-port/): applied to a clean checkout of the fork point
it reproduces the current kernel tree byte-for-byte. The procedure, and an
honest account of which steps are real work, are in that directory's README.

**Measured against the real target 2026-08-21**, which is better news than
the headline numbers suggest. Rockchip's `develop-5.10` at 5.10.252 differs
from this tree in **10,391 files** — but that is 92 stable releases touching
the rest of the kernel, which is the security content we are going for. On
the path this board actually depends on the divergence is almost nil:

| | Divergence |
|---|---|
| `rv1106-pinctrl.dtsi` | **byte-identical** |
| `rv1106.dtsi` | **one node**, 7 diff lines of 1558 |

Every node the Ultra board DTS references (`spi0`, `npu`, `i2c3`, `gmac`)
exists in both. The hand-carry set is **17 Luckfox DTS/DTSI files and 9
config files**, and the dtb builds by pattern rule so no Makefile wiring
moves with them.

### The OTP node, which is the one dangerous difference

That single divergent node in `rv1106.dtsi` is the **OTP controller's clock
list** — and the SoC OTP is one of the two sources the secrets sidecar is
keyed on (`core/secretbox.c`, HKDF over OTP + eMMC CID). The two trees are
each internally consistent and disagree with each other:

| Tree | `rockchip-otp.c` expects | `rv1106.dtsi` provides |
|---|---|---|
| Luckfox 5.10.160 | 6 — `usr, sbpi, apb, phy, arb, pmc` | 6 |
| Rockchip 5.10.252 | 4 — `usr, sbpi, apb, phy` | 4 |

**Take Rockchip's driver and its dtsi node together. Do not carry Luckfox's
OTP node across.** The tempting move — preserving "our" board files wholesale
— puts a 6-clock dtsi node under a 4-clock driver, or worse the reverse:
`clk_bulk_get` then asks for clocks the node does not name, the OTP probe
fails, and `secrets_at_rest.mode` degrades **with no error anyone would
see**. A security control regressing silently is the exact failure shape this
programme keeps recording, and this one would survive every host test,
because the host suite fakes the binding sources.

So `secrets_at_rest.mode = encrypted` is a **required bench assertion after
the port**, not an assumption. It is cheap — one field in
`diagnostics.json` — and it is the only way the claim is checkable.

**Correction, 2026-08-22: `mode = encrypted` is not sufficient on its own.**
`secretbox_seal` derives from every provider that works, so if the OTP probe
fails on a unit provisioned *after* the port, it binds to `emmc-cid` alone and
still reports `mode = encrypted`. The field that exposes it is **`binding`,
which must contain `soc-otp`**. (`mode` does catch the other shape: a unit
provisioned *before* the port stores `binding=soc-otp+emmc-cid` in its
envelope, and `build_ikm` refuses to derive from a subset, so the unseal fails
outright and the mode becomes `unreadable`.) Check `binding` and `mode`
together, plus `ls /sys/bus/nvmem/devices/` for the OTP device itself. Full
procedure in [`release-build-runbook.md`](release-build-runbook.md).



### Bench result, 2026-08-22: PASS

Read off a flashed 5.10.252 unit:

```
# uname -r
5.10.252
# ls /sys/bus/nvmem/devices/
rockchip-otp0
# dmesg | grep -i otp
                                  (no output — no probe or clk_bulk_get failure)
# hexdump -C /sys/bus/nvmem/devices/rockchip-otp0/nvmem | head -1
00000000  52 56 11 06 02 00 fe 67  08 00 4d 41 52 38 31 36  |RV.....g..MAR816|
# grep -o '"secrets_at_rest":{[^}]*}' /var/run/intelligence-edge/diagnostics.json
"secrets_at_rest":{"mode":"encrypted","binding":"soc-otp+emmc-cid"}
```

`binding` contains `soc-otp`, so the OTP is live and keying the sidecar. The
OTP content is device-unique — `52 56 11 06` is the RV1106 part ID, followed
by a lot marking and serial — so it passes `bytes_are_unique()` rather than
being an unprogrammed all-`00`/all-`ff` part.

**And it proves more than presence.** The sidecar
(`/userdata/satisense/state/gateway.json.secrets`, 283 bytes, mtime 2026-08-21
15:49) was sealed under **5.10.160** and survived the reflash on `/userdata`.
Unsealing it names `soc-otp+emmc-cid`, and `build_ikm` refuses to derive from
a subset, so the key comes from the actual OTP bytes; `SECRETBOX_ENCRYPTED` is
set only after `EVP_DecryptFinal_ex` verifies the GCM tag over an AAD that
includes the binding string. A tag that verifies means the 5.10.252 driver
returned **byte-identical OTP content** to the 5.10.160 one. Had the new
driver read a different offset or length, the derived key would differ and the
mode would have come back `unreadable`.

That is the whole OTP risk closed, on hardware, by the strongest of the three
shapes this check can take.

## U-Boot: leave it

Zero local changes, so there is nothing to port and no drift to lose. It is
2017.09, and its 41 findings stay `report-only` on grounds already recorded:
not network-facing in this product, no netboot, no USB mass-storage boot path
enabled. Against that, the A/B design depends on the vendor's `cmd/bootfit.c`
FIT loader and the `misc` AVB slot convention, and the partition layout was
frozen 2026-08-19 as one-way door #1. Touching U-Boot risks both for no
security gain. Mainline has no RV1106 support either (open MR since
2026-07-06), so there is no upgrade path even if one were wanted.

## The part that belongs in the technical file

**No available base covers a five-year support window.** 6.12 and 6.18 run to
Dec 2028 and have no RV1106; 6.1 and 6.6 die Dec 2027; 5.10 dies Dec 2026.
Under *any* choice this product will be re-based at least once inside its
support period.

So the defensible position is not "we picked the right LTS" — it is **a
documented re-base plan and demonstrated ability to execute one**, which is
what Annex I Part II §2 asks for (a process, not a version). The 5.10.252
refresh is the first exercise of that capability, which is a second reason to
do it now rather than to discover the cost later under advisory pressure.

**Trigger for the next move, not a calendar date:** Rockchip publishing an
RV1106 base on ≥ 6.6, or mainline RV1106 gaining GMAC and NPU. Fall back to
6.1 by roughly mid-2027 if neither has appeared.

**What would flip this:** shipping after Dec 2027, or a customer
contractually requiring a non-EOL kernel. Either makes 6.1 necessary sooner
and the driver-port cost has to be funded rather than avoided.

## Status: built, confirmed on hardware, migrated in-tree

**2026-08-21** — the port was executed and **built clean at 5.10.252**:
`make kernel` and `make drv` both exit 0, all four carried drivers compile
untouched, and the dtb's OTP node came out as the matched 4-clock pair. Full
measurements in [`kernel-port/README.md`](kernel-port/README.md).

**2026-08-21, on the board** — a unit was flashed with the 5.10.252 image and
**T1S, the OPC UA server and the CAN gateway were confirmed working.** That is
the bench evidence this plan was waiting on: the claim is no longer "it
compiles".

**2026-08-22** — 5.10.252 was **migrated in-tree as the default kernel**.
`sysdrv/source/kernel` is now the merged tree (Rockchip `develop-5.10` + the
17-file carry set + the six patches), `sysdrv/Makefile.param` is unmodified
vendor code, and a plain `./build.sh` produces a 5.10.252 image with no
environment variable, staging directory or objects redirection. Rebuilt and
re-verified from the migrated tree: `Linux version 5.10.252`, A/B FIT
byte-identical to the packed `boot.img`, rootfs carrying only
`/lib/modules/5.10.252/`. The migration is **10,217 files changed** — 9,915
modified, 302 deleted, 1,044 added — which is what a 92-release stable bump
looks like.

Three defconfig symbols were dropped in the move, all Luckfox-local drivers
absent from Rockchip's tree and none on this product's path (`OF_DTBO`,
`USB_SERIAL_CH343`, `ROCKCHIP_DVBM_PROC_FS`). Letting them go is a recorded
decision, not an oversight.

The build procedure now lives in
[`release-build-runbook.md`](release-build-runbook.md), which also covers the
`.swu` and the kernel/module cross-version hazard.

**2026-08-22, the OTP binding — closed.** `diagnostics.json` on a 5.10.252
unit reports `mode=encrypted` with `binding=soc-otp+emmc-cid`, so the OTP is
live and keying the sidecar. Nothing in this plan now rests on a dtb
inspection: the refresh is verified end to end on hardware.

## Owed

- ~~The refresh itself, per `kernel-port/README.md`.~~ **Built 2026-08-21,
  confirmed on hardware the same day (T1S, OPC UA, CAN), migrated in-tree
  2026-08-22.** The reflash requirement stands for any unit already carrying
  5.10.160 — the updater cannot deliver a kernel.
- ~~The OTP binding read off a 5.10.252 unit.~~ **Done 2026-08-22 — passes**
  (`mode=encrypted`, `binding=soc-otp+emmc-cid`). Nothing on this plan is now
  owed against the 5.10.252 refresh itself.
- ~~`./build.sh cve` before and after, recorded.~~ **Done 2026-08-21**, same
  image and same NVD cache, only the `cpe-extra.csv` version differing:

  | | Kernel matches | Gate |
  |---|---|---|
  | 5.10.160 | **5155** | passed, 0 blocking |
  | 5.10.252 | **2867** | passed, 0 blocking |

  **2288 records retired — 44%** — by 92 stable releases, for a port in which
  not one driver source needed editing. Nothing else moved: 68 monitor, 32
  suppressed, 41 of 69 components checked, both runs. U-Boot stays at 41,
  as expected from a decision not to touch it.

  The residual 2867 is still dominated by subsystems this SoC configuration
  does not build, so the row stays `report-only` on unchanged grounds. The
  number is evidence for the re-base *cadence*, not for a clean kernel.
- Compliance-plan item 5d and both Annex I matrices updated when it lands.
