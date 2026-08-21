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
| Kernel | 5.10.160, vendored in-tree | 20 commits / 14 files / +2539/-11 | ~5100 (1683 at CVSS ≥ 7.0), `report-only` |
| U-Boot | 2017.09 Rockchip fork | **none** — all 7 commits are Luckfox's | 41, `report-only` |

Both are `MODE=report-only` in `cpe-extra.csv` on the stated grounds that a
vendor kernel is remediated by moving its base, not by dispositioning five
thousand records. That reasoning is sound and unchanged. What has changed is
that the base is about to stop receiving fixes at all.

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

## Owed

- The refresh itself, per `kernel-port/README.md`, then a bench pass and a
  reflash — **before first shipment**.
- `./build.sh cve` before and after, recorded. The count will fall; by how
  much is not predictable from here and should not be guessed at.
- Compliance-plan item 5d and both Annex I matrices updated when it lands.
