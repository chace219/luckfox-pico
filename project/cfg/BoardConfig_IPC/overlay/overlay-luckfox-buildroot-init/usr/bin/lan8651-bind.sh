#!/bin/sh
# lan8651-bind.sh - Force-bind the LAN865x SPI driver to a SPI device and
# show the kernel probe log regardless of whether the bind succeeds or fails.
# Usage: lan8651-bind.sh [spi-device] [driver-name]
#   spi-device  : sysfs SPI device name, default spi0.1
#   driver-name : SPI driver name,       default lan8650

say() {
	printf '%s\n' "$*"
}

device="${1:-spi0.1}"
driver_name="${2:-lan8650}"
sysfs_dev="/sys/bus/spi/devices/${device}"
driver_dir="/sys/bus/spi/drivers/${driver_name}"
bind_path="${driver_dir}/bind"
override_path="${sysfs_dev}/driver_override"

# Check SPI device exists
if [ ! -d "$sysfs_dev" ]; then
	say "ERROR: ${device} does not exist in /sys/bus/spi/devices"
	say "  Either the DTS node is wrong or the kernel was not (re)built with"
	say "  the LAN8651 node.  Run lan8651-check.sh for a full diagnosis."
	exit 1
fi

# Check driver is loaded
if [ ! -d "$driver_dir" ]; then
	say "ERROR: SPI driver '${driver_name}' is not registered in the running kernel."
	say "  The kernel image may not include CONFIG_LAN865X=y / CONFIG_OA_TC6=y."
	exit 1
fi

# Determine current binding
current_driver="(unbound)"
if [ -L "${sysfs_dev}/driver" ]; then
	current_driver=$(basename "$(readlink -f "${sysfs_dev}/driver")" 2>/dev/null || echo unknown)
fi

say "LAN8651 bind helper"
say "  device:         ${device}"
say "  target driver:  ${driver_name}"
say "  current driver: ${current_driver}"
say ""

# Already bound to the right driver – just dump dmesg and exit
if [ "$current_driver" = "$driver_name" ]; then
	say "${device} is already bound to ${driver_name}."
	if [ -d "/sys/class/net/eth1" ]; then
		say "eth1 is present – probe succeeded previously."
	else
		say "WARNING: bound but eth1 is absent.  Check dmesg below."
	fi
	say ""
	if command -v dmesg >/dev/null 2>&1; then
		say "========== dmesg – LAN865x / OA-TC6 probe log =========="
		dmesg | grep -i \
			'lan865\|oa.tc6\|oa_tc6\|spi0\.1\|ff500000\.spi\|mdio\|microchip\|No PHY\|reset\|irq 0' \
			| tail -n 80
		say "========================================================="
	fi
	exit 0
fi

# Bound to a different driver – refuse to steal
if [ "$current_driver" != "(unbound)" ]; then
	say "ERROR: ${device} is already bound to '${current_driver}'."
	say "  Unbind it first:  echo ${device} > /sys/bus/spi/drivers/${current_driver}/unbind"
	exit 1
fi

# Clear driver_override so OF/id_table matching is used (not the spidev override)
if [ -f "$override_path" ]; then
	printf '' > "$override_path" 2>/dev/null || true
fi

# Attempt bind – intentionally do NOT abort when this fails; the whole
# point is to show the kernel log of WHY it failed.
say "Binding ${device} to ${driver_name} ..."
echo "$device" > "$bind_path" 2>/dev/null
bind_rc=$?

say ""
if [ -L "${sysfs_dev}/driver" ]; then
	bound_drv=$(basename "$(readlink -f "${sysfs_dev}/driver")" 2>/dev/null || echo unknown)
	say "  Result: BOUND to '${bound_drv}'"
	if [ -d "/sys/class/net/eth1" ]; then
		say "  eth1 interface IS present – LAN8651 probe succeeded!"
		say ""
		say "  Bring it up with:"
		say "    ip link set eth1 up"
		say "    ip addr add <your-IP>/24 dev eth1"
	else
		say "  WARNING: driver bound but eth1 not present."
		say "  Check dmesg below for register_netdev or PLCA errors."
	fi
else
	say "  Result: FAILED (rc=${bind_rc}) – probe rejected the device."
	say "  The exact error will be in dmesg below."
fi

say ""
say "========== dmesg – LAN865x / OA-TC6 probe log =========="
if command -v dmesg >/dev/null 2>&1; then
	dmesg | grep -i \
		'lan865\|oa.tc6\|oa_tc6\|spi0\.1\|ff500000\.spi\|mdio\|microchip\|No PHY\|reset\|irq 0' \
		| tail -n 120
	say "========================================================="
	say ""
	say "If probe failed, key messages to look for:"
	say "  'MAC-PHY software reset failed'  -> soft reset timed out (SPI framing issue)"
	say "  'No PHY found'                   -> PHY ID read returned 0 or 0xFFFF"
	say "  'Can'\''t attach PHY'            -> PHY ID mismatch with microchip_t1s driver"
	say "  'Failed to request macphy isr'   -> IRQ request failed for GPIO1_PC4"
	say "  'Failed to config TSU'           -> SPI write failed (echo mismatch)"
	say ""
	say "Run lan8651-spi-test.sh after this to see the PHY hardware ID."
else
	say "  dmesg not available on this image."
fi