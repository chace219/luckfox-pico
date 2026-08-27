# Expansion Board Pinout — Luckfox Pico Ultra & Pro/Max

Pin assignments for the LAN8651 (10BASE-T1S SPE) + MCP251863 (CAN FD) expansion
board (MikroE Click–style), connector **J2** (`PINHD-2X10`), reference schematic
`89-S&C-R0`.

- **LAN8651 and both MCP251863s share one SPI0 bus** (`SPI0_M0`): they merge on
  MISO/MOSI/CLK and are separated by independent GPIO chip-selects
  (`LAN_RX=CAN_MISO`, `LAN_CLK=CAN_SCK`, `LAN_TX=CAN_MOSI` in the schematic).
  Tables 1 and 2 give the first CAN controller and the LAN8651; **Table 3 adds
  the second CAN controller**, which is the same two GPIOs on both boards.
- Both boards use the **RV1106** SoC, so GPIO names, mux functions, and Luckfox
  Pin numbers are identical. The same expansion board fits both; only the
  physical header layout and default device-tree state differ.

**Luckfox Pin # formula:** `pin = bank*32 + group*8 + index` (group A=0, B=1, C=2, D=3).

---

## Table 1 — Luckfox Pico Ultra (J2)

| J2 pin | Net                | GPIO      | Pin # | Mux function (as used)        | Purpose                        |
|:------:|--------------------|-----------|:-----:|-------------------------------|--------------------------------|
| 1      | +5V                | —         | —     | power rail                    | Board +5V in                   |
| 2      | 3.3V               | —         | —     | power rail                    | Board 3.3V                     |
| 3      | GND                | —         | —     | —                             | Ground                         |
| 4      | GPIO4              | GPIO1_A0  | 32    | I2C2_SCL_M0 (func2)           | Future I²C clock               |
| 5      | GND                | —         | —     | —                             | Ground                         |
| 6      | GPIO11             | GPIO1_A1  | 33    | I2C2_SDA_M0 (func2)           | Future I²C data                |
| 7      | CAN-CS             | GPIO1_C0  | 48    | GPIO (native SPI0_CS0_M0)     | MCP251863 chip-select          |
| 8      | GPIO8              | GPIO1_C4  | 52    | UART4_RX_M1 (func4)           | Future UART RX                 |
| 9      | CAN-INT            | GPIO2_A7  | 71    | GPIO (input)                  | MCP251863 IRQ, level-low       |
| 10     | GPIO5              | GPIO1_C5  | 53    | UART4_TX_M1 (func4)           | Future UART TX                 |
| 11     | LAN_RX / CAN_MISO  | GPIO1_C3  | 51    | SPI0_MISO_M0 (func6)          | Shared SPI MISO                |
| 12     | LAN_CSN            | GPIO1_B2  | 42    | GPIO (alt UART2_TX_M1)        | LAN8651 chip-select            |
| 13     | LAN_CLK / CAN_SCK  | GPIO1_C1  | 49    | SPI0_CLK_M0 (func4)           | Shared SPI clock               |
| 14     | LAN_TX / CAN_MOSI  | GPIO1_C2  | 50    | SPI0_MOSI_M0 (func6)          | Shared SPI MOSI                |
| 15     | LAN_IRQ            | GPIO1_B3  | 43    | GPIO (alt UART2_RX_M1)        | LAN8651 IRQ, edge-falling      |
| 16     | LAN_RST            | GPIO1_B0  | 40    | GPIO output (alt UART4_RX_M0) | LAN8651 RESET_N                |
| 17     | QSPI1_SSN          | *(Hall sensor)* | — | your design               | as-drawn                       |
| 18     | IO24               | GPIO1_D0  | 56    | GPIO (alt UART3_TX_M1)        | Spare GPIO                     |
| 19     | ADD                | *(address strap)* | — | your design             | as-drawn                       |
| 20     | IO25               | GPIO1_D1  | 57    | GPIO (alt UART3_RX_M1)        | Spare GPIO                     |

Verified in `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`:
SPI0 is `okay`; MCP251xFD on CS0=GPIO1_C0, LAN8651 on GPIO-CS=GPIO1_B2, and the
second MCP251863 on GPIO-CS=GPIO2_A4 (Table 3). All
assigned pins are conflict-free (no other peripheral, Wi-Fi SDIO, eMMC, or
console claims them) and all are confirmed broken out on the Ultra header per the
official GPIO diagram.

---

## Table 2 — Luckfox Pico Pro / Max (same expansion board)

**Verified against the official Pro/Max GPIO diagram**
(<https://wiki.luckfox.com/Luckfox-Pico-Pro-Max/GPIO/>). The Pro/Max has a
**different, smaller header layout** than the Ultra: it does **not** break out
GPIO1_A0/A1/B0, and GPIO1_B2/B3 are the default UART2 console. Four of the Ultra
assignments therefore had to be **relocated** to Pro/Max-exposed pins (see
"reloc" column). Same RV1106 SoC, so all mux/Pin# values are identical where the
pin exists.

"HdrPin" = physical position on the Pro/Max 2x20 header. "Pin #" = Luckfox sysfs
number.

| J2 pin | Net               | Pro/Max GPIO | HdrPin | Pin # | Mux function (as used) | reloc |
|:------:|-------------------|--------------|:------:|:-----:|------------------------|:-----:|
| 4      | GPIO4 (I2C SCL)   | GPIO2_A1     | 25     | 65    | I2C4_SCL_M0            | yes   |
| 6      | GPIO11 (I2C SDA)  | GPIO2_A0     | 24     | 64    | I2C4_SDA_M0            | yes   |
| 7      | CAN-CS            | GPIO1_C0     | 12     | 48    | GPIO (SPI0_CS0_M0)     |       |
| 8      | GPIO8 (UART RX)   | GPIO1_C4     | 7      | 52    | UART4_RX_M1            |       |
| 9      | CAN-INT           | GPIO2_A7     | 34     | 71    | GPIO (input)           |       |
| 10     | GPIO5 (UART TX)   | GPIO1_C5     | 6      | 53    | UART4_TX_M1            |       |
| 11     | LAN_RX / CAN_MISO | GPIO1_C3     | 16     | 51    | SPI0_MISO_M0           |       |
| 12     | LAN_CSN           | GPIO2_A2     | 26     | 66    | GPIO                   | yes   |
| 13     | LAN_CLK / CAN_SCK | GPIO1_C1     | 14     | 49    | SPI0_CLK_M0            |       |
| 14     | LAN_TX / CAN_MOSI | GPIO1_C2     | 15     | 50    | SPI0_MOSI_M0           |       |
| 15     | LAN_IRQ           | GPIO2_A3     | 27     | 67    | GPIO                   | yes   |
| 16     | LAN_RST           | GPIO1_C6     | 5      | 54    | GPIO output            | yes   |
| 18     | IO24              | GPIO1_D0     | 19     | 56    | GPIO (UART3_TX_M1)     |       |
| 20     | IO25              | GPIO1_D1     | 20     | 57    | GPIO (UART3_RX_M1)     |       |

"reloc" = relocated vs the Ultra because the Ultra pin is not exposed / usable
on Pro/Max.

All 14 signal pins above are confirmed present on the Pro/Max header and are free
of conflicts in the Pro/Max device tree. Power/GND (J2 1/2/3/5), QSPI1_SSN (17),
ADD (19) are as in Table 1.

### What changed vs the Ultra, and why

| Net     | Ultra pin | Pro/Max pin | Reason for change                                          |
|---------|-----------|-------------|------------------------------------------------------------|
| I2C SCL | GPIO1_A0  | GPIO2_A1    | GPIO1_A0 not broken out on Pro/Max; GPIO2_A1 = I2C4_SCL_M0 |
| I2C SDA | GPIO1_A1  | GPIO2_A0    | GPIO1_A1 not broken out on Pro/Max; GPIO2_A0 = I2C4_SDA_M0 |
| LAN_CSN | GPIO1_B2  | GPIO2_A2    | GPIO1_B2 = default UART2 console on Pro/Max (issue #104)    |
| LAN_IRQ | GPIO1_B3  | GPIO2_A3    | GPIO1_B3 = default UART2 console on Pro/Max (issue #104)    |
| LAN_RST | GPIO1_B0  | GPIO1_C6    | GPIO1_B0 not broken out on Pro/Max                          |

> **Consequence for the hardware:** the Ultra and Pro/Max headers are physically
> different, so a single ribbon/adapter cannot serve both boards. J2's net names
> stay the same, but the J2→Luckfox wiring (or a board-specific adapter) differs
> between Ultra (Table 1) and Pro/Max (Table 2).

---

## Table 3 — Second MCP251863 (CAN 2), both boards

A second CAN FD controller shares the same SPI0 bus as the first and the
LAN8651, on a third GPIO chip-select. **Only five conductors are new** — SCK,
MOSI and MISO are already present and are tapped at the existing J2, not run
again from the SoC.

Unlike the LAN8651 (five nets relocated between boards, Table 2), **CAN 2 uses
the same two GPIOs on Ultra and Pro/Max**. Only the physical header position
differs, which matters to the adapter and not to the device tree.

| Net       | GPIO      | Pin # | Ultra header        | Pro/Max header      | Direction               | Mux           |
|-----------|-----------|:-----:|---------------------|---------------------|-------------------------|---------------|
| CAN2_CS   | GPIO2_A4  | 68    | bottom, left col    | right col, last row | out, active-low         | `RK_FUNC_GPIO` |
| CAN2_INT  | GPIO2_A5  | 69    | bottom, left col    | right col, 2nd-last | in, active-low, level   | `RK_FUNC_GPIO` |
| CAN2_SCK  | GPIO1_C1  | 49    | shared — tap at J2 13 | shared — tap at J2 13 | out                   | `SPI0_CLK_M0`  |
| CAN2_MOSI | GPIO1_C2  | 50    | shared — tap at J2 14 | shared — tap at J2 14 | out                   | `SPI0_MOSI_M0` |
| CAN2_MISO | GPIO1_C3  | 51    | shared — tap at J2 11 | shared — tap at J2 11 | in                    | `SPI0_MISO_M0` |
| CAN2_VDD  | 3V3       | —     | top row 1 / bottom row 3 | 3V3_OUT        | 3.3 V                   | logic supply   |
| CAN2_VIO  | 5V        | —     | top rows 1–2        | VBUS / VSYS         | 5 V                     | ATA6563 transceiver |
| CAN2_GND  | GND       | —     | multiple            | multiple            | —                       | keep short     |

### Complete SPI0 bus after the change

| `reg` | Device        | CS (Ultra) | CS (Pro/Max) | CS type | IRQ      | IRQ mode      | SPI clk |
|:-----:|---------------|------------|--------------|---------|----------|---------------|---------|
| 0     | MCP251863 #1  | GPIO1_C0   | GPIO1_C0     | GPIO    | GPIO2_A7 | level-low     | 8 MHz   |
| 1     | LAN8651       | GPIO1_B2   | **GPIO2_A2** | GPIO    | GPIO1_B3 / **GPIO2_A3** | edge-falling | 15 MHz |
| 2     | MCP251863 #2  | GPIO2_A4   | GPIO2_A4     | GPIO    | GPIO2_A5 | level-low     | 8 MHz   |

**All three chip-selects must stay GPIO.** `rockchip_spi_set_cs()` asserts native
`SER[0]` on every GPIO-CS transfer, so a device left on a native CS would be
re-selected by the other two devices' traffic and corrupted.

### Electrical notes

- **Fit external 10 kΩ pull-ups to 3V3 on CAN2_CS and CAN2_INT.** `pcfg_pull_up`
  applies only once the kernel's pinctrl core runs; between power-on and that
  moment GPIO2_A4 floats, and a chip-select that drifts low lets the MCP see
  spurious transactions during boot. The SoC's `sdmmc1m0_idle_pins` group defines
  this pair as `pcfg_pull_down`, so the pad's default bias is not helpfully high.
  (That group is unreferenced on both boards, so it never applies — but it tells
  you what the pad does on its own.)
- **The ATA6563 half needs 5 V.** Two transceivers under sustained TX add roughly
  100–150 mA to the 5 V rail; check it against what the T1S PHY already draws.
- **Oscillator: 40 MHz, bench-verified.** Schematic `89-S&C-R0` shows a 20 MHz X1,
  but that symbol does not match the modules fitted. At 20 MHz the driver computes
  `tq 50ns` and both channels go silent; at 40 MHz it computes `tq 25ns / brp 1`,
  which divides to exactly 500 kbit/s and passes traffic both ways. If a future
  module genuinely carries a different crystal, declare a second `fixed-clock`
  rather than changing the shared one.

### Pins this consumes

`UART1_M1_TX` and `UART1_M1_RX` are the alternate functions on GPIO2_A4/A5.
Nothing uses them today — the Ultra's Bluetooth is on `uart1m0` (GPIO1_A3/A4) —
but **UART1_M1 is no longer available as a future serial port** on either board.
Recorded here so it is a known trade rather than a later surprise.

Everything else stays free: GPIO2_A6, GPIO2_B0/B1, GPIO1_C4/C5/C7, GPIO4_C0/C1
(and, on the Ultra, GPIO2_A0–A3 which the Pro/Max spends on the relocated nets).

Verified in both `rv1106g-luckfox-pico-ultra.dts` and
`rv1106g-luckfox-pico-pro-max.dts` against the **compiled DTB**, not the source:
`num-cs = <3>`, the third `cs-gpios` entry resolving to gpio2 pin 4, and `can@2`
interrupts to pin 5 level-low.

---

## Design notes

1. **Two SPI chips, one bus, separate chip-selects.** SCK/MOSI/MISO are shared;
   CAN and LAN each get their own GPIO CS plus an IRQ line. Keep **both** CS lines
   as GPIO chip-selects — do not put one on native SPI CS0. The Rockchip
   controller also asserts native SER[0] on every GPIO-CS transfer, so mixing
   native + GPIO CS lets LAN traffic re-select the CAN controller and corrupt it.

2. **I²C pull-ups.** GPIO1_A0/A1 are pull-none Schmitt-trigger pads. Add external
   4.7 kΩ pull-ups on SDA/SCL on the expansion board.

3. **LAN_RST (GPIO1_B0) vs UART4.** GPIO1_B0 is the SoC's UART4_RX_M0 pin. The
   future UART is assigned to UART4_**M1** (GPIO1_C4/C5), so they coexist — but
   never mux UART4 to its M0 group or it collides with LAN_RST.

4. **Do not use UART2 on this connector.** UART2_M1 maps to GPIO1_B2/B3 — the
   Ultra LAN_CSN / LAN_IRQ pins (and the Pro/Max default console).

5. **CAN oscillator.** The Ultra device tree declares the MCP251863 clock as
   **40 MHz**. The `89-S&C-R0` schematic shows a **20 MHz** crystal (X1). These
   must match: either fit a 40 MHz part or set `clock-frequency = <20000000>` in
   the device tree. A mismatch produces the wrong CAN bit rate.

## Pro/Max-specific caveats (from device tree)

1. **SPI0 ships `disabled`** on Pro/Max (`rv1106g-luckfox-pico-pro-max.dts`),
   vs `okay` on the Ultra. Wiring is the same; only the DT default differs.
2. **GPIO1_C3 (SPI MISO)** is used as an SPI-LCD reset in the Pro/Max IPC
   reference (`rv1106-luckfox-pico-pro-max-ipc.dtsi:287`). Only relevant if an
   SPI display is enabled — not used by the LAN/CAN expansion.
3. **GPIO1_B2 / GPIO1_B3 are the default UART2 debug console** on the Pro/Max
   (`uart2m1_xfer` = GPIO1_B2/B3), confirmed by LuckfoxTECH/luckfox-pico issue
   #104 (GPIO 42/43 stuck high). This is why Table 2 relocates LAN_CSN/LAN_IRQ
   off B2/B3 to GPIO2_A2/A3. The Ultra does not have this problem (console =
   `ttyFIQ0`/uart0), so Table 1 keeps them on B2/B3.

## Header exposure — status (verified)

Both boards' assignments were checked against the official Luckfox GPIO diagrams:

- **Ultra:** all Table 1 GPIOs (GPIO1_A0/A1/B0/B2/B3/C0-C5/D0/D1, GPIO2_A7) are
  broken out on the Ultra headers. Table 1 is confirmed.
- **Pro/Max:** the header is smaller (26 GPIO on 2x20). Confirmed **not** broken
  out: **GPIO1_A0, GPIO1_A1, GPIO1_B0** (hence the relocations in Table 2).
  GPIO1_B2/B3 are present but are the console (see caveat 3). All Table 2 GPIOs
  are confirmed present and usable.

Diagrams used:

- Ultra: <https://wiki.luckfox.com/Luckfox-Pico-Ultra/GPIO/>
- Pro/Max: <https://wiki.luckfox.com/Luckfox-Pico-Pro-Max/GPIO/>

## Source files

- Ultra DT: `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`
- Pro/Max DT: `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-pro-max.dts`
- SoC pinctrl (all SPI/I2C/UART mux groups): `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-pinctrl.dtsi`
- Related: `README_CAN_HAT.md`, `README_LAN8651_SPE.md`
