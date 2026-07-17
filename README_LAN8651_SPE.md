# LAN8651 10BASE-T1S SPE Shield — Integration Guide

This document describes the integration of the **Microchip LAN8651** 10BASE-T1S
Single-Pair Ethernet MAC-PHY on the **Luckfox Pico Ultra** (RV1106, Linux 5.10
vendor kernel).

> **Historical bring-up record.** This guide documents the initial SPE-only
> shield integration (1 MHz SPI over jumper wires, CAN controller not
> instantiated, PLCA subordinate node 1, LAN8651 as `eth1`). The **current**
> tree differs: both LAN8651 and MCP251863 are instantiated on SPI0 with GPIO
> chip-selects, the LAN8651 probes first as `eth0`, and the factory PLCA
> default is **coordinator (node ID 0), node count 8** — see
> `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`,
> `README_PLCA_CAN_OPERATIONS.md`, and `media/joral/media-gateway/README.md`.

---

## Hardware Setup

| Signal | LAN8651 Shield pin | Luckfox Pico Ultra pin | GPIO / function |
|---|---|---|---|
| SCLK | SPI CLK | SPI0_CLK | GPIO1_C1 / `spi0m0_clk` |
| MOSI | SPI SDI | SPI0_MOSI | GPIO1_C2 / `spi0m0_mosi` |
| MISO | SPI SDO | SPI0_MISO | GPIO1_C3 / `spi0m0_miso` |
| CS | CS | GPIO header GPIO1_B2 | GPIO1_B2 / `cs-gpios` |
| IRQ | INT | GPIO header GPIO1_B3 | GPIO1_B3 (falling edge) |
| GND | GND | GND | — |
| 3.3V | VDD | 3V3 | — |

The shield is exposed as **`spi0.1`**. On the Ultra, the second SPI chip-select
slot is backed by **`cs-gpios = <0>, <&gpio1 RK_PB2 GPIO_ACTIVE_LOW>`** rather
than the native `spi0m0_cs1` pin. The MCP2518FD CAN FD controller remains physically
wired to `SPI0_CS0`, but it is **not instantiated in the device tree** for this
temporary SPE-only build.

---

## Kernel Driver Changes

### `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`

Enabled `spi0`, removed the default `spidev@0`, and added the `lan8651:
ethernet@1` SPI device node and pinctrl:

```dts
&spi0 {
  status = "okay";
  num-cs = <2>;
  cs-gpios = <0>, <&gpio1 RK_PB2 GPIO_ACTIVE_LOW>;
  pinctrl-0 = <&spi0m0_clk &spi0m0_miso &spi0m0_mosi &spi0m0_cs0
         &lan8651_cs_pin &lan8651_int_pin>;
  /delete-node/ spidev@0;

lan8651: ethernet@1 {
    compatible = "microchip,lan8651";
  reg = <1>;                          /* cs-gpios slot 1 */
    spi-max-frequency = <1000000>;      /* 1 MHz — reliable over jumper wires */
    microchip,plca-enable;
    microchip,plca-node-id = <1>;       /* 0 = coordinator, 1+ = subordinate */
    microchip,plca-node-count = <8>;    /* must match all nodes on the segment */
    interrupt-parent = <&gpio1>;
  interrupts = <RK_PB3 IRQ_TYPE_EDGE_FALLING>;
    status = "okay";
};
};
```

This keeps the on-board GMAC as `eth0`, so the LAN8651 usually appears as
`eth1`.

**SPI speed note:** The chip is confirmed working at 500 kHz–1 MHz over jumper
wires. At 15 MHz (the datasheet maximum) SPI echo checks fail due to signal
integrity on unshielded wiring. Use `spi-max-frequency = <15000000>` only with
a dedicated PCB.

### `sysdrv/source/kernel/drivers/net/phy/microchip_t1s.c`

Changed PHY ID matching from exact (`PHY_ID_MATCH_EXACT`) to model-level
(`PHY_ID_MATCH_MODEL`) so all LAN865x Rev B silicon revisions are accepted:

```c
/* Before — rejected any revision other than B0 */
PHY_ID_MATCH_EXACT(0x0007C1B3)

/* After — accepts Rev B0, B1, and future minor revisions */
PHY_ID_MATCH_MODEL(0x0007C1B0)
```

### `sysdrv/source/kernel/drivers/net/ethernet/oa_tc6.c`

Three fixes were required:

**1. MDIO bus PHY scan mask**

The synthetic MDIO bus was scanning all 32 addresses. The LAN8651 internal PHY
is only at address 0:

```c
/* oa_tc6_mdiobus_register() */
mdiobus->phy_mask = ~BIT(0);   /* scan address 0 only */
```

**2. Software reset SPI echo bypass**

The LAN8651 starts hardware reset immediately on receiving `SWRESET`, before
completing the SPI echo transaction. `oa_tc6_write_register()` then fails with
`-EPROTO` on the echo check, causing `oa_tc6_sw_reset_macphy()` to return an
error before the chip is even given a chance to reset.

Fix: send the SWRESET SPI frame directly (bypassing echo check), then poll for
completion:

```c
/* Send SWRESET without checking echo — chip starts resetting immediately */
oa_tc6_prepare_ctrl_spi_buf(tc6, OA_TC6_REG_RESET, &regval, 1,
                            OA_TC6_CTRL_REG_WRITE);
size = oa_tc6_calculate_ctrl_buf_size(1);
oa_tc6_spi_transfer(tc6, OA_TC6_CTRL_HEADER, size);
```

**3. Reset completion polling**

`readx_poll_timeout()` with a 1 ms sleep rounds up to a 10 ms kernel tick on a
`CONFIG_HZ=100` kernel, giving only ~12 real iterations before the 1-second
timeout expires (~120 ms wall-clock). The chip needs up to ~300 ms to
re-establish SPI after reset.

Fix: 100 ms flat wait followed by a 3-second manual retry loop:

```c
msleep(100);
for (i = 0; i < 300; i++) {
    if (oa_tc6_read_register(tc6, OA_TC6_REG_STATUS0, &regval) == 0 &&
        (regval & STATUS0_RESETC)) {
        /* reset complete */
        break;
    }
    msleep(10);
}
```

---

## On-Board Tools (`/usr/bin/`)

All tools are installed to `/usr/bin/` via the buildroot overlay at
`project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/`.

### `lan8651-bind.sh` — Driver bind and probe log

Force-bind the `lan8650` SPI driver to `spi0.1` and display the kernel probe
log whether it succeeds or fails.

```sh
lan8651-bind.sh [spi-device] [driver-name]

# Defaults: spi-device=spi0.1, driver-name=lan8650
lan8651-bind.sh
lan8651-bind.sh spi0.1 lan8650
```

Output includes the bound driver state, whether `eth1` appeared, and filtered
`dmesg` showing all LAN865x / OA-TC6 related messages. Key error strings and
their meanings are printed at the end of every failed run.

### `lan8651-spi-test.sh` — Raw SPI hardware verification

Verifies the SPI connection to the LAN8651 without loading the kernel driver.
Reads the OA-TC6 standard registers and checks echo integrity.

```sh
lan8651-spi-test.sh
```

Run this first if the driver fails to probe — it confirms whether the chip is
physically connected and responding over SPI.

### `lan8651-spi-probe.py` — Python SPI register dump

Reads key OA-TC6 and PHY registers directly via `/dev/spidev0.1` (Python
`spidev` module). Reports the full PHY ID and compares it against the expected
`0x0007C1Bx` value.

```sh
lan8651-spi-probe.py [--device /dev/spidev0.1] [--speed 500000]
```

Use this to verify the PHY ID when the kernel driver reports `Can't attach PHY`.

### `lan8651-check.sh` — System state overview

Prints a summary of SPI bus, driver registration, interface presence, and link
state in one command.

```sh
lan8651-check.sh
```

### `lan8651_plca_ctrl` — Runtime PLCA role and parameter control

Changes the PLCA role (coordinator / subordinate) and parameters at runtime
without rebooting or reflashing. Uses `SIOCSMIIREG` / `SIOCGMIIREG` socket
ioctls with Clause-45 MMD register encoding to access the PLCA registers in
MMD 31 (vendor space).

```sh
# Read current PLCA state
lan8651_plca_ctrl eth1 get

# Set as PLCA coordinator (node ID 0 — generates BEACON)
lan8651_plca_ctrl eth1 set coordinator [node_count [tot_timer]]

# Set as PLCA subordinate node
lan8651_plca_ctrl eth1 set subordinate <node_id> [node_count [tot_timer]]
```

**Examples:**

```sh
# Board becomes coordinator, 8-node segment
lan8651_plca_ctrl eth1 set coordinator 8

# Board becomes subordinate node 1 (EVB-LAN8670-USB is coordinator)
lan8651_plca_ctrl eth1 set subordinate 1 8

# Read back to confirm
lan8651_plca_ctrl eth1 get
```

**PLCA register map written by this tool:**

| Register | Address | Field | Meaning |
|---|---|---|---|
| PLCA_CTRL0 | MMD31:0xCA01 | bit 15 | PLCA enable |
| PLCA_CTRL1 | MMD31:0xCA02 | [15:8] | node_count |
| PLCA_CTRL1 | MMD31:0xCA02 | [7:0] | node_id (0 = coordinator) |
| PLCA_TOTMR | MMD31:0xCA04 | [7:0] | beacon TO timer |

**Source:** `media/luckfox/examples/lan8651_plca_ctrl.c`

---

## PLCA Configuration

PLCA (Physical Layer Collision Avoidance) is the medium access mechanism for
10BASE-T1S shared-wire segments. One node must be the **coordinator** (node ID
0); all others are **subordinates**.

### Parameters

| Parameter | DTS property | `plca_ctrl` arg | Description |
|---|---|---|---|
| Enable | `microchip,plca-enable` | always on when set | Enables PLCA MAC mode |
| Node ID | `microchip,plca-node-id` | `<node_id>` | 0 = coordinator |
| Node count | `microchip,plca-node-count` | `[node_count]` | Total nodes, **must match on every node** |
| TO timer | `microchip,plca-to-timer` | `[tot_timer]` | Beacon interval (×100 µs) |

### Typical two-node setup with EVB-LAN8670-USB

```
[Luckfox Pico Ultra]              [PC]
  LAN8651                    EVB-LAN8670-USB
  node-id = 1   ───────────   node-id = 0 (coordinator)
  node-count = 8               node-count = 8
```

```sh
# On the Luckfox board — default (configured via DTS, no command needed):
lan8651_plca_ctrl eth1 get   # should show node_id=1, coordinator=no

# To make the board the coordinator instead (also reconfigure EVB to node 1):
lan8651_plca_ctrl eth1 set coordinator 8
```

Configure the EVB-LAN8670-USB node ID via Microchip's **LAN867x EVB
Configuration Utility** on the PC (set node ID = 1, node count = 8).

---

## Network Usage

Once `eth1` is up and PLCA is established, the interface behaves as standard
Ethernet. All IP protocols work normally.

### Checking link state

```sh
ip link show eth1
# Should show: state UP and "Link is Up - 10Mbps/Half"
dmesg | grep 'eth1: Link'
```

### Static IP

```sh
# Kill DHCP client if running (Windows ICS assigns via DHCP)
kill $(ps | grep '[u]dhcpc.*eth1' | awk '{print $1}') 2>/dev/null
ip addr flush dev eth1
ip addr add 192.168.137.220/24 dev eth1
ip link set eth1 up
```

### DHCP from Windows ICS

When the EVB-LAN8670-USB is connected to a Windows 11 PC with Internet
Connection Sharing enabled, Windows runs a DHCP server on the ICS adapter
(`192.168.137.x` subnet):

```sh
udhcpc -i eth1 -n -q
```

### Ping and connectivity notes

- `ping -I eth1 <pc-ip>` may fail even when the link works — Windows Firewall
  blocks inbound ICMP on ICS adapters by default.
- Enable it in PowerShell (Administrator):
  ```powershell
  netsh advfirewall firewall add rule name="ICMPv4 SPE" protocol=icmpv4:8,any dir=in action=allow
  ```
- Internet access via `eth1` works through Windows ICS NAT without firewall
  changes (traffic is NATed, not destined to the PC).

### TCP / UDP

```sh
# TCP server on the board
nc -l -p 5000

# UDP unicast send to PC
echo "hello" | nc -u <pc-ip> 5001

# UDP multicast
ip route add 224.0.0.0/4 dev eth1
ping -I eth1 224.0.0.1
```

---

## Build Instructions

```sh
# Full image (kernel + rootfs + all tools):
./build.sh

# Kernel only (after DTS or driver changes):
./build.sh kernel

# Flash via SD card update:
#   Copy IMAGE/<latest>/IMAGES/sd_update.img to SD card root,
#   boot the board while holding the SD-update button.
```

The `lan8651_plca_ctrl` binary is cross-compiled for ARM uClibc as part of the
`media/luckfox/examples/` build. It is copied into the buildroot overlay at
`project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/`
and automatically included in every `rootfs.img`.

To cross-compile the tool manually:

```sh
cd media/luckfox/examples
CC=arm-rockchip830-linux-uclibcgnueabihf-gcc make lan8651_plca_ctrl
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `MAC-PHY software reset failed: -71` | SWRESET echo check failing | Kernel fix already applied; check SPI wiring |
| `MAC-PHY reset did not complete within 3 s` | MISO stuck / SPI broken after reset | Run `lan8651-spi-test.sh`; check CS and MISO wiring |
| `No PHY found` | PHY ID reads as 0 or 0xFFFF | Wrong SPI mode or speed; run `lan8651-spi-probe.py` |
| `Can't attach PHY` | PHY ID revision mismatch | `PHY_ID_MATCH_MODEL` fix already applied |
| `eth1` present but RX=0 | PLCA node-count mismatch | Ensure all nodes use same `node-count` value |
| `ping <pc>` fails, internet works | Windows Firewall blocking ICMP | Add inbound ICMP rule on PC (see above) |
| IP address won't stick | `udhcpc` overwriting manual assignment | Kill `udhcpc` before using `ip addr` |
