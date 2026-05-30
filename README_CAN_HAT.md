# CAN Integration — MCP251863 Click on Luckfox Pico Ultra

**Board:** Luckfox Pico Ultra (RV1106)  
**Module:** MikroE MCP251863 Click (`MIKROE-4955`)  
**CAN interface name:** `can0`  
**Bus:** SPI0_M0 — shared with the LAN8651 Single-Pair Ethernet adapter  

> This integration binds the Click board through the Linux `mcp251xfd` driver family so the
> controller still appears as `can0`. The DTS below assumes the module is populated with a
> `40 MHz` oscillator. If your board revision uses a different crystal, update the DTS
> `clock-frequency` and keep `spi-max-frequency` at or below half of that clock.

---

## Table of Contents

1. [Hardware Wiring](#1-hardware-wiring)
2. [How the SPI0 Bus is Shared](#2-how-the-spi0-bus-is-shared)
3. [Files Changed](#3-files-changed)
4. [Building and Flashing](#4-building-and-flashing)
5. [First-Boot Verification](#5-first-boot-verification)
6. [Configuring `can0`](#6-configuring-can0)
7. [Sending and Receiving Frames](#7-sending-and-receiving-frames)
8. [Loopback Self-Test](#8-loopback-self-test)
9. [Diagnostic Script](#9-diagnostic-script)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Hardware Wiring

- `SCK`: Click `SCK` -> Luckfox `SPI0_CLK` (`GPIO1_C1`), shared with LAN8651.
- `MOSI`: Click `SDI` / `MOSI` -> Luckfox `SPI0_MOSI` (`GPIO1_C2`), shared with LAN8651.
- `MISO`: Click `SDO` / `MISO` -> Luckfox `SPI0_MISO` (`GPIO1_C3`), shared with LAN8651.
- `CS`: Click `CS` -> Luckfox `SPI0_CS0` (`GPIO1_C0`), which is the hardware chip select for `spi0.0`.
- `INT`: Click `INT` -> Luckfox `GPIO2_A7`, active-low interrupt used by `mcp251xfd`.
- `3V3`: Click `3V3` -> Luckfox `3V3`.
- `GND`: Click `GND` -> Luckfox `GND`.
- `CANH`: Click `CAN H` -> CAN bus high.
- `CANL`: Click `CAN L` -> CAN bus low.

Notes:

- Leave the Click board on `SPI0_CS0` (`GPIO1_C0`). `SPI0_CS1` is already used by the LAN8651 path.
- `RST`, `INT1` / RX interrupt, and any extra mikroBUS sideband pins are not required for the basic
  `can0` binding in this kernel.
- Keep the CAN bus terminated correctly at the two physical ends of the network.

---

## 2. How the SPI0 Bus is Shared

Both the MCP251863 Click controller and the LAN8651 Single-Pair Ethernet adapter are attached to the
same SPI0_M0 bus. They are distinguished by separate hardware chip-selects:

| Device           | SPI CS             | Kernel pin group  | `reg` in DTS |
| ---------------- | ------------------ | ----------------- | ------------ |
| MCP251863 Click  | SPI0_CS0 GPIO1_C0  | `spi0m0_cs0`      | `<0>`        |
| LAN8651          | GPIO1_B2 (GPIO CS) | `lan8651_cs_pin`  | `<1>`        |

The Rockchip SPI controller still drives CS0 in hardware for the CAN controller. LAN8651 remains on
the second chip-select slot through the existing GPIO-backed CS path.

---

## 3. Files Changed

### 3.1 Device Tree — `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`

(symlinked as `config/dts_config`)

- Replaced the old `mcp2515` binding with an `mcp251xfd` family node at `spi0.0`.
- Added a `fixed-clock` node (`mcp251xfd_osc`) at `40 MHz` for the Click controller.
- Switched the CAN IRQ pinctrl entry to `GPIO2_A7` (`mcp251xfd_int_pin`).
- Kept the node at `reg = <0>` so Linux still binds the interface as `can0`.

### 3.2 Kernel defconfig — `sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig`

(symlinked as `config/kernel_defconfig`)

Changed:

```kconfig
CONFIG_CAN=y
CONFIG_CAN_RAW=y
CONFIG_CAN_BCM=y
CONFIG_CAN_GW=y
CONFIG_CAN_DEV=y
CONFIG_CAN_MCP251XFD=y
```

### 3.3 Buildroot defconfig — `sysdrv/source/buildroot/buildroot-2023.02.6/configs/luckfox_pico_defconfig`

(symlinked as `config/buildroot_defconfig`)

No additional userspace package change is required for this controller swap. The active Ultra
Buildroot defconfig already contains:

```kconfig
BR2_PACKAGE_CAN_UTILS=y
BR2_PACKAGE_IPROUTE2=y
```

That means `ip link`, `candump`, `cansend`, and CAN FD-aware userspace remain available after the
kernel and DT rebuild.

### 3.4 Overlay scripts — `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/`

- `can-diag.sh`: full diagnostic for kernel CAN support, SPI enumeration, driver probe, sysfs attributes, IRQ visibility, and userspace tools.
- `can-tool.py`: pure-Python CAN utility for bitrate setup, send/receive, and loopback self-test when `iproute2` or `can-utils` are unavailable.

---

## 4. Building and Flashing

A full kernel + rootfs rebuild is required:

```sh
cd /home/embedded/luckfox-pico
./build.sh kernel
./build.sh
```

Then flash the resulting images with `rkflash.sh` or the Rockchip flashing tool.

---

## 5. First-Boot Verification

After flashing, verify the driver probed correctly:

```sh
# SPI devices must appear
ls /sys/bus/spi/devices/
# Expected: spi0.0  spi0.1

cat /sys/bus/spi/devices/spi0.0/modalias
# Expected to contain: mcp251xfd  or another mcp251xFD-family string

# can0 interface must exist
ip link show can0
# Expected output contains: can0: <NOARP,ECHO> mtu 16 ...

# Driver probe messages (no errors expected)
dmesg | grep -i 'mcp251xfd\|can0'
# Expected: mcp251xfd spi0.0 can0: ...
# Avoid exact string matching here; the driver may report the detected family variant.
```

---

## 6. Configuring `can0`

The bitrate **must** be set while the interface is DOWN, then the interface is brought UP.

```sh
ip link set can0 down
ip link set can0 type can bitrate 500000
ip link set can0 up
ip link show can0
```

To use CAN FD on the MCP251863 path, configure both nominal and data phase bitrates:

```sh
ip link set can0 down
ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on
ip link set can0 up
ip -details link show can0
```

To set it automatically on boot, add to `/etc/network/interfaces` (or a startup script):

```sh
auto can0
iface can0 inet manual
    pre-up ip link set $IFACE type can bitrate 500000
    up ip link set $IFACE up
    down ip link set $IFACE down
```

Common classical-CAN bitrates for this setup:

- `100 kbit/s`: long-distance or industrial links.
- `125 kbit/s`: common CANopen default.
- `250 kbit/s`: common automotive or mixed-node setup.
- `500 kbit/s`: common automotive default.
- `1 Mbit/s`: common upper-end nominal bitrate.

---

## 7. Sending and Receiving Frames

### Using can-utils

```sh
# Receive — prints every frame on can0
candump can0

# Send a standard frame: ID=0x123, 4 bytes of data
cansend can0 123#DEADBEEF

# Send an extended frame (29-bit ID)
cansend can0 1FFFFFFF#0102030405060708

# Send a CAN FD frame (example: 16 bytes, bitrate switch)
cansend can0 123##1DEADBEEF00112233445566778899AABB

# Generate test traffic
cangen can0 -g 10 -I 123 -L 4

# Show bus statistics
ip -details -statistics link show can0
```

### Using can-tool.py (works on any image, no can-utils required)

```sh
# Send
can-tool.py send 123 DEADBEEF

# Receive for 10 seconds
can-tool.py recv --timeout 10

# Configure + bring up in one step
can-tool.py setup --bitrate 500000

# Help
can-tool.py --help
```

---

## 8. Loopback Self-Test

The MCP251863 controller path supports an internal loopback mode that echoes every transmitted frame back to the
receive buffer without putting anything on the CAN bus wires. This is the safest first test.

```sh
# Using can-tool.py (works on any image)
can-tool.py diag
# Sends a known frame, checks echo, then restores normal mode.
# PASS means the SPI, interrupt, and `can0` path are working.

# Equivalent using ip + cansend (requires iproute2 + can-utils)
ip link set can0 type can bitrate 500000 loopback on
ip link set can0 up
candump can0 &
cansend can0 7FF#CAFEBABE01020304
ip link set can0 down
ip link set can0 type can bitrate 500000 loopback off
ip link set can0 up
```

---

## 9. Diagnostic Script

`can-diag.sh` checks every layer of the integration and prints a PASS/FAIL summary:

```sh
can-diag.sh          # checks can0 (default)
can-diag.sh can1     # check a different interface
```

Example healthy output:

```text
=== Kernel: CAN subsystem ===
  [PASS] CAN subsystem active (interface or protocol registered)

=== Kernel: MCP251xFD driver probe ===
  [INFO] [  11.687] mcp251xfd spi0.0 can0: ...
  [PASS] Driver probed without errors

=== SPI device enumeration ===
  [PASS] SPI device spi0.0 exists
  [INFO] modalias = spi:mcp251xfd
  [PASS] modalias matches MCP251xFD family

=== CAN network interface: can0 ===
  [PASS] Interface can0 exists
  [INFO] can clock   = 40000000 Hz
  [PASS] CAN clock frequency matches expected oscillator (40000000 Hz)

=== Userspace tools ===
  [PASS] ip found (/sbin/ip)
  [PASS] candump found (/usr/bin/candump)
  ...

=== Summary ===
  Passed: 9   Failed: 0
```

---

## 10. Troubleshooting

### `ip link set can0 type can bitrate ...` returns `"type" is garbage`

The image has BusyBox `ip` instead of iproute2. Rebuild with `BR2_PACKAGE_IPROUTE2=y` (already
added) or use `can-tool.py setup --bitrate 500000` as a workaround.

### `SIOCSIFFLAGS: Invalid argument` when running `ip link set can0 up`

Bitrate has not been configured. Always run the `type can bitrate` command first, then bring the
interface up.

### `can0` does not appear in `ip link`

Check dmesg for `mcp251xfd` probe errors:

```sh
dmesg | grep -i "mcp251xfd\|spi0.0"
```

Common causes:

| dmesg message | Likely cause |
| ------------- | ------------ |
| `unable to set initial baudrate` | Normal — bitrate not yet configured by userspace |
| `SPI transfer failed` | Wiring problem on SCK/MOSI/MISO or CS0 connected to wrong pin |
| `Oscillator frequency ... is too low or high` | `clock-frequency` in DTS does not match the module crystal |
| No MCP251xFD messages at all | Kernel built without `CONFIG_CAN_MCP251XFD=y`, or DTS node missing |

### `candump` / `cansend` not found

The active `luckfox_pico_w_defconfig` already enables `BR2_PACKAGE_CAN_UTILS=y` and
`BR2_PACKAGE_IPROUTE2=y`. If those tools are missing on target, make sure the image was rebuilt
and flashed **after** the kernel and DTS changes. Use `can-tool.py` as a fallback on older images.

### CAN frames sent but nothing received on the remote node

- Verify the remote node is configured to the **same bitrate**.
- Check the CAN bus has exactly **two 120 Ω termination resistors** (one at each physical end).
- Verify the Click board transceiver side is wired to the correct `CANH` / `CANL` pair.
- Check `ip -details -statistics link show can0` for error counters (`bus-off`, `error-passive`).
- If your board revision is not using a `40 MHz` crystal, update the DTS `clock-frequency` and, if
  needed, run `EXPECTED_CAN_CLOCK_HZ=<your_clock_hz> can-diag.sh` while validating the new image.
