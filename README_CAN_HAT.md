# CAN HAT Integration — Waveshare RS485/CAN HAT on Luckfox Pico Plus

**Board:** Luckfox Pico Plus (RV1103G)  
**HAT:** Waveshare RS485/CAN HAT (MCP2515 + TJA1050 CAN transceiver)  
**CAN oscillator:** 12 MHz (on-board crystal)  
**Bus:** SPI0_M0 — shared with LAN8651 SPE Ethernet adapter  

> Only the CAN port of the HAT is used. The RS-485 interface is not connected or enabled.

---

## Table of Contents

1. [Hardware Wiring](#1-hardware-wiring)
2. [How the SPI0 Bus is Shared](#2-how-the-spi0-bus-is-shared)
3. [Files Changed](#3-files-changed)
4. [Building and Flashing](#4-building-and-flashing)
5. [First-Boot Verification](#5-first-boot-verification)
6. [Configuring the CAN Interface](#6-configuring-the-can-interface)
7. [Sending and Receiving Frames](#7-sending-and-receiving-frames)
8. [Loopback Self-Test (no external node needed)](#8-loopback-self-test-no-external-node-needed)
9. [Diagnostic Script](#9-diagnostic-script)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Hardware Wiring

| HAT Signal | HAT Pin | Luckfox Pico Plus Pin | GPIO      | Notes |
|------------|---------|-----------------------|-----------|-------|
| SCK        | HAT SCK  | SPI0_CLK              | GPIO1_C1  | Shared with LAN8651 |
| MOSI       | HAT MOSI | SPI0_MOSI             | GPIO1_C2  | Shared with LAN8651 |
| MISO       | HAT MISO | SPI0_MISO             | GPIO1_C3  | Shared with LAN8651 |
| CS         | HAT CS   | **SPI0_CS0 — GPIO1_C0** | GPIO1_C0 | **See note below** |
| INT        | HAT INT  | GPIO1_C7              | GPIO1_C7  | Active-low IRQ |
| VCC        | 3.3V     | Luckfox 3V3           | —         | 3.3 V supply |
| GND        | GND      | Luckfox GND           | —         | Common ground |

> **CS pin correction:** The HAT CS line must be connected to **GPIO1_C0** (physical SPI0_CS0,
> kernel pin group `spi0m0_cs0`). GPIO1_D2 is `SPI0_CS1` and is already occupied by the LAN8651
> adapter. Connecting CS to GPIO1_D2 will cause both devices to be selected simultaneously.

---

## 2. How the SPI0 Bus is Shared

Both the MCP2515 CAN controller and the LAN8651 Single-Pair Ethernet adapter are attached to the
same SPI0_M0 bus. They are distinguished by separate hardware chip-selects:

| Device   | SPI CS            | Kernel pin group  | `reg` in DTS |
|----------|-------------------|-------------------|--------------|
| MCP2515  | SPI0_CS0 GPIO1_C0 | `spi0m0_cs0`      | `<0>`        |
| LAN8651  | SPI0_CS1 GPIO1_D2 | `spi0m0_cs1`      | `<1>`        |

The Rockchip SPI controller handles CS assertion in hardware; no GPIO bit-banging is required.

---

## 3. Files Changed

### 3.1 Device Tree — `sysdrv/source/kernel/arch/arm/boot/dts/rv1103g-luckfox-pico-plus.dts`

(symlinked as `config/dts_config`)

- Added a `fixed-clock` node (`mcp2515_osc`) at 12 MHz in the root node.
- Added `mcp2515_int_pin` pinctrl entry for the IRQ line on GPIO1_C7.
- Added `mcp2515: can@0` SPI device node under `&spi0`.
- Extended `&spi0 pinctrl-0` to include `spi0m0_cs0` and the new interrupt pin.

### 3.2 Kernel defconfig — `sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig`

(symlinked as `config/kernel_defconfig`)

Added:

```
CONFIG_CAN=y
CONFIG_CAN_RAW=y
CONFIG_CAN_BCM=y
CONFIG_CAN_GW=y
CONFIG_CAN_DEV=y
CONFIG_CAN_MCP251X=y
```

### 3.3 Buildroot defconfig — `sysdrv/source/buildroot/buildroot-2023.02.6/configs/luckfox_pico_defconfig`

(symlinked as `config/buildroot_defconfig`)

Added:

```
BR2_PACKAGE_CAN_UTILS=y
BR2_PACKAGE_IPROUTE2=y
```

> **Note:** There is also a template copy at `sysdrv/tools/board/buildroot/luckfox_pico_defconfig`.
> Both files were updated. The build system uses the extracted copy via the symlink in `config/`.

### 3.4 Overlay scripts — `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/`

| Script | Purpose |
|--------|---------|
| `can-diag.sh`  | Full diagnostic: checks kernel CAN subsystem, SPI enumeration, driver probe, sysfs attributes, IRQ registration, and userspace tools |
| `can-tool.py`  | Pure-Python CAN utility (no iproute2/can-utils dependency). Configures bitrate via netlink, sends/receives frames via AF_CAN sockets, runs hardware loopback self-test |

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
# MCP2515 SPI device must appear
ls /sys/bus/spi/devices/
# Expected: spi0.0  spi0.1  (mcp2515 and lan8651)

cat /sys/bus/spi/devices/spi0.0/modalias
# Expected: spi:mcp2515

# can0 interface must exist
ip link show can0
# Expected output contains: can0: <NOARP,ECHO> mtu 16 ...

# Driver probe messages (no errors expected)
dmesg | grep -i mcp251
# Expected: mcp251x spi0.0 can0: MCP2515 successfully initialized.
#           mcp251x spi0.0 can0: bit-timing not yet defined  ← normal, configure below
```

---

## 6. Configuring the CAN Interface

The bitrate **must** be set while the interface is DOWN, then the interface is brought UP.

```sh
ip link set can0 type can bitrate 500000
ip link set can0 up
ip link show can0
```

To set it automatically on boot, add to `/etc/network/interfaces` (or a startup script):

```
auto can0
iface can0 inet manual
    pre-up ip link set $IFACE type can bitrate 500000
    up ip link set $IFACE up
    down ip link set $IFACE down
```

Common bitrates supported by MCP2515 at 12 MHz oscillator:

| Bitrate   | Notes |
|-----------|-------|
| 100 kbit/s | Long-distance / industrial |
| 125 kbit/s | CANopen default |
| 250 kbit/s | Common automotive |
| 500 kbit/s | Common automotive |
| 1 Mbit/s  | Maximum for MCP2515 |

---

## 7. Sending and Receiving Frames

### Using can-utils (after rebuild)

```sh
# Receive — prints every frame on can0
candump can0

# Send a standard frame: ID=0x123, 4 bytes of data
cansend can0 123#DEADBEEF

# Send an extended-frame (29-bit ID)
cansend can0 1FFFFFFF#0102030405060708

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

## 8. Loopback Self-Test (no external node needed)

The MCP2515 supports an internal loopback mode that echoes every transmitted frame back to the
receive buffer without putting anything on the CAN bus wires. This is the safest first test.

```sh
# Using can-tool.py (works on any image)
can-tool.py diag
# Sends a known frame, checks echo, then restores normal mode.
# PASS means MCP2515 SPI communication and interrupt are working.

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

```
=== Kernel: CAN subsystem ===
  [PASS] CAN subsystem active (interface or protocol registered)

=== Kernel: MCP2515 driver probe ===
  [INFO] [  11.687] mcp251x spi0.0 can0: MCP2515 successfully initialized.
  [PASS] Driver probed without errors

=== SPI device enumeration ===
  [PASS] SPI device spi0.0 exists
  [INFO] modalias = spi:mcp2515
  [PASS] modalias matches MCP2515

=== CAN network interface: can0 ===
  [PASS] Interface can0 exists
  [INFO] can clock   = 12000000 Hz
  [PASS] CAN clock frequency matches expected 12 MHz oscillator

=== Userspace tools ===
  [PASS] ip found (/sbin/ip)
  [PASS] candump found (/usr/bin/candump)
  ...

=== Summary ===
  Passed: 9   Failed: 0
```

---

## 10. Troubleshooting

### `ip link set can0 type can bitrate ... ` returns `"type" is garbage`

The image has BusyBox `ip` instead of iproute2. Rebuild with `BR2_PACKAGE_IPROUTE2=y` (already
added) or use `can-tool.py setup --bitrate 500000` as a workaround.

### `SIOCSIFFLAGS: Invalid argument` when running `ip link set can0 up`

Bitrate has not been configured. Always run the `type can bitrate` command first, then bring the
interface up.

### `can0` does not appear in `ip link`

Check dmesg for MCP2515 probe errors:

```sh
dmesg | grep -i "mcp251\|spi0.0"
```

Common causes:

| dmesg message | Likely cause |
|---------------|--------------|
| `unable to set initial baudrate` | Normal — bitrate not yet configured by userspace |
| `SPI transfer failed` | Wiring problem on SCK/MOSI/MISO or CS0 connected to wrong pin |
| `MCP251x didn't enter in loopback mode` | Oscillator absent or wrong frequency; check 12 MHz crystal on HAT |
| No MCP2515 messages at all | Kernel built without `CONFIG_CAN_MCP251X=y`, or DTS node missing |

### `candump` / `cansend` not found

`BR2_PACKAGE_CAN_UTILS=y` was added to both buildroot defconfigs. Make sure a full rebuild was
done **after** these changes (`./build.sh kernel && ./build.sh`) and the new image was flashed.
Use `can-tool.py` as a fallback on the current image.

### CAN frames sent but nothing received on the remote node

- Verify the remote node is configured to the **same bitrate**.
- Check the CAN bus has exactly **two 120 Ω termination resistors** (one at each physical end).
  The Waveshare HAT has an on-board 120 Ω resistor that can be enabled by a solder jumper.
- Check `ip -details -statistics link show can0` for error counters (`bus-off`, `error-passive`).
