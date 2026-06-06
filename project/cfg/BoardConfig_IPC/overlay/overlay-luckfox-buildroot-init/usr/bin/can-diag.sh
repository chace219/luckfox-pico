#!/bin/sh
# can-diag.sh - Diagnose MCP251xFD-family CAN interface health
# Usage: can-diag.sh [can-interface]

IFACE="${1:-can0}"
EXPECTED_CAN_CLOCK_HZ="${EXPECTED_CAN_CLOCK_HZ:-40000000}"
PASS=0
FAIL=0

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
info() { echo "  [INFO] $1"; }
section() { echo; echo "=== $1 ==="; }

section "Kernel: CAN subsystem"
# CAN is working if: can0 exists, or AF_CAN appears in /proc/net/protocols (as CAN-RAW etc), or can.ko is loaded
if [ -d /sys/class/net/can0 ] || grep -qi "^CAN" /proc/net/protocols 2>/dev/null || \
   grep -q "^can " /proc/net/protocols 2>/dev/null; then
    pass "CAN subsystem active (interface or protocol registered)"
elif ls /lib/modules/$(uname -r)/kernel/net/can/ 2>/dev/null | grep -q "can.ko"; then
    info "CAN kernel module present but not loaded"
else
    fail "CAN subsystem not found - kernel may lack CONFIG_CAN"
fi

section "Kernel: MCP251xFD driver probe"
DMESG_MCP=$(dmesg 2>/dev/null | grep -i "mcp251xfd\|mcp2518fd\|mcp2517fd\|spi0\.0.*can\|can.*spi0\.0")
if [ -n "$DMESG_MCP" ]; then
    echo "$DMESG_MCP" | while IFS= read -r line; do info "$line"; done
    if echo "$DMESG_MCP" | grep -qi "error\|fail\|probe.*fail\|err="; then
        fail "Driver logged probe errors (see above)"
    else
        pass "Driver probed without errors"
    fi
else
    fail "No MCP251xFD dmesg output found"
    info "Check: was kernel built with CONFIG_CAN_MCP251XFD=y ?"
    info "Check: was DTS mcp251xfd node added and image rebuilt?"
fi

section "SPI device enumeration"
SPI_DEV="/sys/bus/spi/devices/spi0.0"
if [ -d "$SPI_DEV" ]; then
    pass "SPI device spi0.0 exists"
    MODALIAS=$(cat "$SPI_DEV/modalias" 2>/dev/null)
    info "modalias = ${MODALIAS:-<not available>}"
    if echo "$MODALIAS" | grep -qi "mcp251xfd\|mcp2518fd\|mcp2517fd"; then
        pass "modalias matches MCP251xFD family"
    else
        fail "modalias does not match MCP251xFD family (got: $MODALIAS)"
    fi
else
    fail "SPI device spi0.0 not found under /sys/bus/spi/devices/"
    info "Available SPI devices:"
    ls /sys/bus/spi/devices/ 2>/dev/null | while IFS= read -r d; do
        info "  $d ($(cat /sys/bus/spi/devices/$d/modalias 2>/dev/null))"
    done
fi

section "CAN network interface: $IFACE"
if [ -d "/sys/class/net/$IFACE" ]; then
    pass "Interface $IFACE exists"

    OPERSTATE=$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)
    CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)
    FLAGS=$(cat "/sys/class/net/$IFACE/flags" 2>/dev/null)
    info "operstate = ${OPERSTATE}"
    info "carrier   = ${CARRIER:-n/a}"
    info "flags     = ${FLAGS}"

    if [ -f "/sys/class/net/$IFACE/can/state" ]; then
        CAN_STATE=$(cat "/sys/class/net/$IFACE/can/state" 2>/dev/null)
        CAN_BITRATE=$(cat "/sys/class/net/$IFACE/can/bittiming/bitrate" 2>/dev/null)
        CAN_CLOCK=$(cat "/sys/class/net/$IFACE/can/clock/freq" 2>/dev/null)
        info "can state   = ${CAN_STATE:-not configured}"
        info "can bitrate = ${CAN_BITRATE:-not set}"
        info "can clock   = ${CAN_CLOCK} Hz"
        if [ "${CAN_CLOCK:-0}" -eq "$EXPECTED_CAN_CLOCK_HZ" ] 2>/dev/null; then
            pass "CAN clock frequency matches expected oscillator (${EXPECTED_CAN_CLOCK_HZ} Hz)"
        else
            fail "CAN clock frequency is ${CAN_CLOCK:-unknown}, expected ${EXPECTED_CAN_CLOCK_HZ} Hz"
        fi
    else
        info "(CAN sysfs attributes not yet populated - interface not configured)"
    fi

    RX=$(cat "/sys/class/net/$IFACE/statistics/rx_packets" 2>/dev/null)
    TX=$(cat "/sys/class/net/$IFACE/statistics/tx_packets" 2>/dev/null)
    ERR=$(cat "/sys/class/net/$IFACE/statistics/rx_errors" 2>/dev/null)
    info "rx_packets = ${RX:-0}  tx_packets = ${TX:-0}  rx_errors = ${ERR:-0}"
else
    fail "Interface $IFACE not found"
    info "Available network interfaces:"
    ls /sys/class/net/ | while IFS= read -r n; do info "  $n"; done
fi

section "Interrupt pin (GPIO2_A7)"
if grep -qi "mcp251xfd\|mcp2518fd\|mcp2517fd\|spi0.0" /proc/interrupts 2>/dev/null; then
    IRQ_LINE=$(grep -i "mcp251xfd\|mcp2518fd\|mcp2517fd\|spi0.0" /proc/interrupts)
    pass "MCP251xFD IRQ registered: $IRQ_LINE"
else
    info "MCP251xFD IRQ not visible in /proc/interrupts yet (normal if interface not up)"
    grep -i "gpio1\|gpio-1" /proc/interrupts 2>/dev/null | while IFS= read -r l; do info "  $l"; done
fi

section "Userspace tools"
for tool in ip candump cansend cangen canstat; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool found ($(command -v $tool))"
    else
        fail "$tool not found - image needs rebuild with iproute2/can-utils"
    fi
done

section "Summary"
echo "  Passed: $PASS   Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo
    echo "  All checks passed. To configure and test CAN:"
    echo "    can-tool.py setup --bitrate 500000"
    echo "    can-tool.py send 123 DEADBEEF"
    echo "    can-tool.py recv"
    echo
    echo "  (After image rebuild with iproute2 + can-utils:)"
    echo "    ip link set $IFACE type can bitrate 500000"
    echo "    ip link set $IFACE up"
    echo "    candump $IFACE &"
    echo "    cansend $IFACE 123#DEADBEEF"
else
    echo
    echo "  $FAIL issue(s) found. See [FAIL] lines above."
    echo "  If the MCP251xFD controller did not probe: verify wiring, oscillator, and that"
    echo "  the kernel + DTS were rebuilt (./build.sh kernel && ./build.sh)"
fi
echo
