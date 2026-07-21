# PLCA and CAN Operations Guide

This guide is for the current Luckfox Pico Ultra Buildroot image using:

- LAN8651 10BASE-T1S on SPI0.1
- MCP2518FD CAN controller on SPI0.0
- Buildroot defconfig `luckfox_pico_w_defconfig`

It focuses on day-to-day bring-up, checking PLCA role and node settings, and testing CAN traffic against a USB-CAN adapter on a PC.

## 1. What the current image is configured for

### LAN8651 PLCA defaults from DTS

The Ultra device tree configures LAN8651 with:

- PLCA enabled
- node ID `0` (**coordinator** — generates the BEACON)
- node count `8`

The board is the segment's PLCA coordinator by default. On media-gateway
images the daemon re-applies the PLCA settings from
`/etc/media-gateway/t1s.conf` at startup and on every web-console save, so the
runtime role is governed by that file / the web UI — its factory default is
identical (coordinator, node ID 0, node count 8).

When testing against an EVB-LAN8670-USB on a PC, configure the **EVB as a
subordinate** with a non-zero node ID (e.g. node 1) — or demote the board
instead (see below); a segment must have exactly one coordinator.

### MCP2518FD CAN defaults at boot

At boot, `S98can0config` runs `/usr/bin/can0-apply.sh`, which configures
`can0` from the `[can_bus]` section of `/etc/media-gateway/gateway.conf`
(factory default: classic CAN, `500000` bit/s, sample point 80 %,
`restart-ms 100`). The same script runs on every web-console save, so boot and
runtime use one code path. Set `CAN_AUTOCONFIG=0` in the environment to skip
automatic bring-up.

The boot path never enables loopback. Loopback is only enabled temporarily
when you explicitly request it, for example with `can-tool.py diag` or with
`ip link ... loopback on`.

## 2. PLCA quick checks

The LAN8651 interface may appear as `eth0` or `eth1` depending on the image and what other NICs are present. Replace `eth0` below if your LAN8651 shows up under a different name.

### Check that the LAN8651 interface exists and link is up

```sh
ip link show eth0
dmesg | grep 'eth0: Link'
lan8651-check.sh eth0
```

Expected signs of a healthy link:

- `LOWER_UP` in `ip link show`
- `Link is Up - 10Mbps/Half` in `dmesg`

### Read the current PLCA settings

```sh
lan8651_plca_ctrl eth0 get
```

The important fields are:

- `PLCA enabled`: should be `yes` for a PLCA segment
- `Role`: `COORDINATOR` for node ID `0`, otherwise `subordinate`
- `Node ID`: unique per node on the segment
- `Node count`: must match on every node
- `TO timer`: beacon timing, default tool value is `32`

### Recommended two-node setup with EVB-LAN8670-USB on the PC

Luckfox board (factory default — no command needed):

- coordinator
- node ID `0`
- node count `8`

PC EVB-LAN8670-USB:

- subordinate
- node ID `1`
- node count `8`

To re-assert the board's default role after experiments:

```sh
lan8651_plca_ctrl eth0 set coordinator 8 32
lan8651_plca_ctrl eth0 get
```

### Make the board a subordinate

Only do this if another node on the segment (e.g. the PC EVB) is the
coordinator — a segment with two coordinators (or none) does not work.

```sh
lan8651_plca_ctrl eth0 set subordinate 1 8 32
lan8651_plca_ctrl eth0 get
```

On media-gateway images, make the role change persistent via the web console
(Configuration → PLCA Settings) or `/etc/media-gateway/t1s.conf` — otherwise
the daemon restores the configured role on its next reload.

### If DHCP over SPE is not working

First force the expected PLCA state (factory default: coordinator), then retry
DHCP:

```sh
ip addr flush dev eth0
lan8651_plca_ctrl eth0 set coordinator 8 32
ip link set eth0 up
udhcpc -i eth0 -n -q
```

(If this board has deliberately been made a subordinate, use
`set subordinate <id> 8 32` with its assigned node ID instead.)

If you need a static ICS-style address for testing:

```sh
ip addr flush dev eth0
ip addr add 192.168.137.220/24 dev eth0
ip link set eth0 up
```

### Runtime SPI failure of the LAN8651 (and the watchdog that recovers it)

The 5.10 `oa_tc6` driver treats a runtime `Config unsync error` / `Rxd header
bad` as **non-recoverable** (`Device error: -19` in dmesg): the interface goes
dead and stays dead — DHCP, PLCA writes and MDIO reads all fail. The telltale
signature is `lan8651_plca_ctrl eth0 get` returning the **same garbage word
for all three registers** (e.g. `0xFFB9`), plus `ctrl read/write echo
mismatch ... RX[00 00 ...]` spam in dmesg. This was observed in the field
after ~23 h of operation with `spi-max-frequency = <15000000>`; the DTS now
uses 10 MHz for the LAN8651 (same mitigation as the MCP251863, ADR-013).

On media-gateway images, `S55t1s-watchdog` supervises the interface and
recovers this state automatically:

1. **soft** — re-applies the PLCA config from `/etc/media-gateway/t1s.conf`
   (`plca-config set`)
2. **hard** — unbinds/rebinds the `lan8650` SPI driver (full probe = MAC-PHY
   software reset) and restarts `S50media-gateway` so bridge, DHCP and PLCA
   are rebuilt through the normal startup path

Recovery triggers after 3 consecutive failed health checks (~30 s); failed
attempts retry with backoff. Watch it with `logread | grep t1s-watchdog` (or
`dmesg`). If the hard recovery keeps failing, the chip's SPI engine is wedged
beyond software reach — a full **power cycle** (not `reboot`) is required.

## 3. CAN userspace available in the current Buildroot config

The current `luckfox_pico_w_defconfig` now enables:

- `BR2_PACKAGE_IPROUTE2=y`
- `BR2_PACKAGE_CAN_UTILS=y`

After rebuilding and flashing that image, you should have standard tools such as:

- `ip`
- `candump`
- `cansend`
- `cangen`

There is also a fallback Python tool already in the image overlay:

- `/usr/bin/can-tool.py`

That tool works even on minimal images where SocketCAN support exists but `iproute2` or `can-utils` are missing.

## 4. CAN bring-up and health checks

### Check that MCP2518FD is present

```sh
can-diag.sh
ls /sys/bus/spi/devices/
cat /sys/bus/spi/devices/spi0.0/modalias
dmesg | grep -i mcp251
```

Expected signs:

- `spi0.0` exists
- modalias contains `mcp2518fd`
- `can0` exists

### Configure `can0` with standard tools

```sh
ip link set can0 down
ip link set dev can0 type can bitrate 500000
ip link set can0 up
ip -details -statistics link show can0
```

### Configure `can0` with the fallback helper

```sh
python3 /usr/bin/can-tool.py --iface can0 setup --bitrate 500000
```

## 5. Is CAN currently in loopback mode?

Normally, no.

The boot path (`S98can0config` → `can0-apply.sh`) configures `can0` in normal
mode; nothing at boot enables loopback.

### Check loopback with `iproute2`

```sh
ip -details link show can0
```

If loopback is enabled, the CAN mode flags typically show `LOOPBACK`.

### Practical test for accidental loopback

If you unplug the CAN bus wiring and still see your own transmitted frame received immediately, loopback is on.

### Tools that intentionally enable loopback

These are expected to put the interface into loopback temporarily:

```sh
python3 /usr/bin/can-tool.py --iface can0 diag
ip link set dev can0 type can bitrate 500000 loopback on
```

`can-tool.py diag` restores normal mode when it finishes.

## 6. Test CAN against a USB-CAN adapter on a PC

This assumes:

- the MCP2518FD transceiver is wired correctly
- CAN_H and CAN_L from the Luckfox side are connected to the PC USB-CAN adapter
- both ends use the same bitrate
- the bus is properly terminated

### Wiring checklist

- CAN_H to CAN_H
- CAN_L to CAN_L
- common ground between boards/adapters
- 120 ohm termination across the bus, usually one at each end

### Board-side commands

```sh
ip link set can0 down
ip link set dev can0 type can bitrate 500000
ip link set can0 up
ip -details -statistics link show can0
```

Receive on the board:

```sh
candump can0
```

Send from the board:

```sh
cansend can0 123#11223344
cansend can0 321#A1B2C3D4
```

Generate periodic traffic from the board:

```sh
cangen can0 -g 100 -I 123 -L 8
```

### Linux PC with a SocketCAN-capable USB-CAN adapter

If the PC adapter appears as `can0` on the host:

```sh
sudo ip link set can0 down
sudo ip link set dev can0 type can bitrate 500000
sudo ip link set can0 up
ip -details -statistics link show can0
```

Receive on the PC:

```sh
candump can0
```

Send from the PC:

```sh
cansend can0 456#AABBCCDD
```

### Expected bidirectional test flow

On the board:

```sh
candump can0
```

On the PC:

```sh
cansend can0 456#AABBCCDD
```

You should see the frame appear on the board.

Then reverse direction:

On the PC:

```sh
candump can0
```

On the board:

```sh
cansend can0 123#11223344
```

You should see the frame appear on the PC.

## 7. Test CAN without `can-utils`

If you are on an older rootfs without full `iproute2` support, use the helper tool.

Board-side setup:

```sh
python3 /usr/bin/can-tool.py --iface can0 setup --bitrate 500000
```

Receive on the board:

```sh
python3 /usr/bin/can-tool.py --iface can0 recv --timeout 10
```

Send from the board:

```sh
python3 /usr/bin/can-tool.py --iface can0 send 123 11223344
```

## 8. Loopback self-test for MCP2518FD

Use this when you want to verify the controller and driver even if no external CAN adapter is connected.

```sh
python3 /usr/bin/can-tool.py --iface can0 diag
```

What this proves:

- MCP2518FD is present
- SPI communication is working
- CAN IRQ path is working well enough for loopback

What this does not prove:

- CAN_H/CAN_L wiring to the external adapter
- correct bus termination
- a second node on the bus

## 9. Common failure patterns

### `ip link set ... type can ...` says `type is garbage`

Your image is still using a limited BusyBox `ip`. Use:

```sh
python3 /usr/bin/can-tool.py --iface can0 setup --bitrate 500000
```

or rebuild and flash the updated Buildroot image.

### `candump` shows nothing

Check, in order:

- both ends are at the same bitrate
- loopback is not accidentally enabled
- CAN_H and CAN_L are not swapped
- termination is present
- the PC adapter is actually up and transmitting

### Board sees its own frames with no external node connected

That usually means loopback is enabled.

Reset to normal mode:

```sh
ip link set can0 down
ip link set dev can0 type can bitrate 500000 loopback off
ip link set can0 up
```

## 10. File references

Relevant files in this repo:

- `README_LAN8651_SPE.md`
- `README_CAN_HAT.md`
- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S98can0config`
- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/can0-apply.sh`
- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/can-tool.py`
- `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/can-diag.sh`
- `media/luckfox/examples/lan8651_plca_ctrl.c`
- `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts`
