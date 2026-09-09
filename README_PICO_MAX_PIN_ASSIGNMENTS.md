# Luckfox Pico Pro Max — LAN8651 + CAN Pin Assignments

Quick reference for the pins the LAN8651 (10BASE-T1S SPE) and the two MCP251863
(CAN FD) controllers occupy on the **Pico Pro Max** board. All three devices share
a single `SPI0_M0` bus and are separated by independent GPIO chip-selects.

Verified against `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-pro-max.dts`
and `include/dt-bindings/pinctrl/rockchip.h`. For the Ultra board, the full J2
connector mapping, and the design rationale, see
[`README_EXPANSION_BOARD_PINOUT.md`](README_EXPANSION_BOARD_PINOUT.md).

**Luckfox Pin # formula:** `pin = bank*32 + group*8 + index` (group A=0, B=1, C=2, D=3).
"HdrPin" = physical position on the Pro/Max 2x20 header.

---

## Shared SPI0 bus (all three devices)

| Net       | GPIO     | Pin # | HdrPin | Mux function   | Direction |
|-----------|----------|:-----:|:------:|----------------|-----------|
| SPI0_CLK  | GPIO1_C1 | 49     | 14     | `SPI0_CLK_M0`  | out       |
| SPI0_MOSI | GPIO1_C2 | 50     | 15     | `SPI0_MOSI_M0` | out       |
| SPI0_MISO | GPIO1_C3 | 51     | 16     | `SPI0_MISO_M0` | in        |

These three are tapped once and run to all three devices.

## LAN8651 (10BASE-T1S, `spi0.1`, `ethernet@1`)

| Net      | GPIO     | Pin # | HdrPin | Mux / bias               | Purpose                    |
|----------|----------|:-----:|:------:|--------------------------|----------------------------|
| LAN_CSN  | GPIO2_A2 | 66     | 26     | GPIO, `pcfg_pull_none`   | Chip-select, active-low    |
| LAN_IRQ  | GPIO2_A3 | 67     | 27     | GPIO in, `pcfg_pull_up`  | IRQ, **edge-falling**      |
| LAN_RST  | GPIO1_C6 | 54     | 5      | GPIO out, `pcfg_pull_up` | RESET_N, active-low        |

SPI clock 15 MHz. PLCA enabled, node-id 0 (coordinator), node-count 8.

> **LAN_RST is required on this board.** Without `reset-gpios`,
> `devm_gpiod_get_optional()` returns NULL and the driver silently skips reset,
> leaving RESET_N floating — the part then answers SPI with a near-constant zero
> on MISO (correct clocking, no data). The Ultra holds RESET_N high passively and
> needs no such property; the Max has no such guarantee.

## CAN 1 — MCP251863 #1 (`spi0.0`, `can@0` → `can0`)

| Net      | GPIO     | Pin # | HdrPin | Mux / bias               | Purpose                  |
|----------|----------|:-----:|:------:|--------------------------|--------------------------|
| CAN1_CS  | GPIO1_C0 | 48     | 12     | GPIO out, `pcfg_pull_up` | Chip-select, active-low  |
| CAN1_INT | GPIO2_A7 | 71     | 34     | GPIO in, `pcfg_pull_up`  | IRQ, **level-low**       |

SPI clock 8 MHz. GPIO1_C0 is also the native `SPI0_CS0_M0` pad but is deliberately
muxed as a plain GPIO — see the note below.

## CAN 2 — MCP251863 #2 (`spi0.2`, `can@2` → `can1`)

| Net      | GPIO     | Pin # | HdrPin | Mux / bias               | Purpose                  |
|----------|----------|:-----:|:------:|--------------------------|--------------------------|
| CAN2_CS  | GPIO2_A4 | 68     | 21     | GPIO out, `pcfg_pull_up` | Chip-select, active-low  |
| CAN2_INT | GPIO2_A5 | 69     | 22     | GPIO in, `pcfg_pull_up`  | IRQ, **level-low**       |

SPI clock 8 MHz. Same two GPIOs as on the Ultra — only the header position differs.

## Power

| Net  | Pro/Max source | Used by                                  |
|------|----------------|------------------------------------------|
| 3V3  | 3V3_OUT        | LAN8651, both MCP251863 logic supplies   |
| 5V   | VBUS / VSYS    | Both ATA6563 CAN transceivers            |
| GND  | multiple       | all — keep returns short                 |

Two transceivers under sustained TX add roughly 100–150 mA to the 5 V rail; budget
that against what the T1S PHY already draws.

---

## Complete SPI0 bus summary

| `reg` | Device       | sysfs    | CS       | Pin # | IRQ      | Pin # | IRQ mode      | SPI clk |
|:-----:|--------------|----------|----------|:-----:|----------|:-----:|---------------|---------|
| 0     | MCP251863 #1 | `spi0.0` | GPIO1_C0 | 48    | GPIO2_A7 | 71    | level-low     | 8 MHz   |
| 1     | LAN8651      | `spi0.1` | GPIO2_A2 | 66    | GPIO2_A3 | 67    | edge-falling  | 15 MHz  |
| 2     | MCP251863 #2 | `spi0.2` | GPIO2_A4 | 68    | GPIO2_A5 | 69    | level-low     | 8 MHz   |

---

## Notes

**All three chip-selects must stay GPIO.** The Rockchip controller
(`SPI_MASTER_GPIO_SS`) also asserts native `SER[0]` on every GPIO-CS transfer, so a
device left on a native CS would be re-selected by the other two devices' traffic
and corrupted. Making every device GPIO-CS keeps them isolated.

**Fit external 10 kΩ pull-ups to 3V3 on CAN2_CS and CAN2_INT.** `pcfg_pull_up`
applies only once the kernel's pinctrl core runs. Before that, GPIO2_A4/A5 take
their power-on bias, which is pull-down (cf. the SoC's `sdmmc1m0_idle_pins` group —
unreferenced here, so it never applies, but it documents what the pads do on their
own). A chip-select that drifts low lets the MCP see spurious transactions during
boot.

**Oscillator: 40 MHz, bench-verified — do not "correct" to 20 MHz.** Both modules
share one `fixed-clock`. The driver takes it as SYSCLK directly (it never enables
the MCP's PLL), so a mismatch silently scales every bit rate: the link reports the
requested value while the wire runs at another. Schematic `89-S&C-R0` shows a
20 MHz X1, but that symbol does not match the modules fitted — at 20 MHz the driver
computes `tq 50ns` and both channels go silent; at 40 MHz it computes
`tq 25ns / brp 1`, which divides to exactly 500 kbit/s and passes traffic both ways.

**UART1_M1 is spent, and enabling it breaks CAN 2.** `UART1_M1_TX`/`RX` are the
alternate functions on GPIO2_A4/A5 (HdrPin 21/22), so UART1_M1 is no longer
available as a future serial port. Worse,
`rv1106-luckfox-pico-pro-max-ipc.dtsi` already assigns
`&uart1 { pinctrl-0 = <&uart1m1_xfer>; }`, where `uart1m1_xfer` is
`<2 RK_PA4 4>` / `<2 RK_PA5 4>` — exactly CAN2_CS and CAN2_INT. That is inert only
because `uart1` is `status = "disabled"` in `rv1106.dtsi`. **Do not set `uart1` to
`okay` on this board:** it re-muxes both CAN2 pins away from GPIO, the chip-select
stops toggling, and the only symptom is
`mcp251xfd spi0.2: Failed to detect MCP251xFD (osc=0x00000000)`.

**Pins relocated from the Ultra.** The Pro/Max header is smaller and does not break
out GPIO1_A0/A1/B0, while GPIO1_B2/B3 are the default UART2 console:

| Net     | Ultra    | Pro/Max  | Reason                                            |
|---------|----------|----------|---------------------------------------------------|
| LAN_CSN | GPIO1_B2 | GPIO2_A2 | GPIO1_B2 is the Pro/Max UART2 console             |
| LAN_IRQ | GPIO1_B3 | GPIO2_A3 | GPIO1_B3 is the Pro/Max UART2 console             |
| LAN_RST | GPIO1_B0 | GPIO1_C6 | GPIO1_B0 not broken out on Pro/Max                |

A single ribbon/adapter therefore cannot serve both boards.

## Verifying on the board

```sh
mount -t debugfs none /sys/kernel/debug
grep -E "gpio-(48|54|66|67|68|69|71)\b" /sys/kernel/debug/gpio
```

Each pin should appear claimed by its consumer (`spi0 CS0`/`CS1`/`CS2` for the
chip-selects) and set to the direction in the tables above. A chip-select absent
from that list means pinctrl never applied its group; one present and correct but
flat on a scope means the fault is in copper past the SoC ball.
