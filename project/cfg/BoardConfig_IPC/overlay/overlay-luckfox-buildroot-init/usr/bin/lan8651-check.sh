#!/bin/sh

set -eu

iface="${1:-eth1}"

say() {
	printf '%s\n' "$*"
}

have_lan865x_driver=0

if [ -d /sys/bus/spi/drivers/lan8650 ] || [ -d /sys/bus/spi/drivers/lan8651 ]; then
	have_lan865x_driver=1
fi

say "LAN8651/LAN8650 shield check"
say "Interface target: ${iface}"

say ""
say "SPI masters:"
found_master=0
for master in /sys/class/spi_master/spi*; do
	[ -e "$master" ] || continue
	found_master=1
	say "  $(basename "$master")"
done

if [ "$found_master" -eq 0 ]; then
	say "  no SPI masters found"
fi

say ""
say "Device tree nodes matching LAN865x:"
dt_matches=$(grep -a -r -l 'microchip,lan8650\|microchip,lan8651' /sys/firmware/devicetree/base 2>/dev/null || true)
if [ -n "$dt_matches" ]; then
	printf '%s\n' "$dt_matches" | while IFS= read -r match; do
		[ -n "$match" ] || continue
		say "  ${match%/compatible}"
	done
else
	say "  no LAN865x node found in the running device tree"
fi

say ""
say "SPI devices:"
found_spi=0
for dev in /sys/bus/spi/devices/*; do
	[ -e "$dev/modalias" ] || continue
	found_spi=1
	modalias=$(cat "$dev/modalias")
	driver="(unbound)"
	if [ -L "$dev/driver" ]; then
		driver=$(basename "$(readlink -f "$dev/driver")")
	fi
	say "  $(basename "$dev"): $modalias driver=$driver"
done

if [ "$found_spi" -eq 0 ]; then
	say "  no SPI devices found"
fi

say ""
say "LAN865x SPI driver registered: ${have_lan865x_driver}"

say ""
if [ -d "/sys/class/net/${iface}" ]; then
	say "Network interface ${iface} is present"
	state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo unknown)
	carrier=$(cat "/sys/class/net/${iface}/carrier" 2>/dev/null || echo unknown)
	say "  operstate=$state"
	say "  carrier=$carrier"
	if command -v ethtool >/dev/null 2>&1; then
		say ""
		say "ethtool -i ${iface}:"
		ethtool -i "$iface" || true
		say ""
		say "ethtool ${iface}:"
		ethtool "$iface" || true
	fi
	if command -v ip >/dev/null 2>&1; then
		say ""
		say "ip -s link show dev ${iface}:"
		ip -s link show dev "$iface" || true
	fi
	exit 0
fi

say "Network interface ${iface} is not present"

if command -v dmesg >/dev/null 2>&1; then
	say ""
	say "Recent kernel log entries:"
	dmesg | grep -i 'lan865\|oa-tc6\|microchip\|spi0\|spi1\|spi2' | tail -n 80 || true
fi

say ""
say "Interpretation:"
if [ "$found_spi" -eq 0 ] || ! ls /sys/bus/spi/devices/spi0.* >/dev/null 2>&1; then
	say "  The shield SPI device is not instantiated by the running kernel."
	say "  This is a DTS/build/boot issue, not yet proof of a dead LAN8651."
	if [ -n "$dt_matches" ]; then
		say "  The running DT has a LAN865x node, so check whether spi0 is enabled and wired correctly."
	else
		say "  The running DT does not contain the LAN865x node, so the new DTB/image is probably not booted yet."
	fi
	if [ -f /usr/bin/lan8651-spi-probe.py ]; then
		say "  For raw register probing, boot an image that exposes the shield as /dev/spidevX.Y and run:"
		say "    python3 /usr/bin/lan8651-spi-probe.py --device /dev/spidev0.1"
	fi
elif [ -d /sys/bus/spi/devices/spi0.1 ] && [ ! -d "/sys/class/net/${iface}" ]; then
	if [ "$have_lan865x_driver" -eq 0 ]; then
		say "  spi0.1 exists but the LAN865x SPI driver is not registered in the running kernel."
		say "  This is still a software/image/config problem."
	else
		say "  spi0.1 exists and the LAN865x SPI driver is registered, but the device is still not bound as a network interface."
		say "  The next suspicion is probe failure due to SPI communication, IRQ wiring, or another runtime probe error."
	fi
	if [ -f /usr/bin/lan8651-spi-test.sh ]; then
		say "  To test raw SPI communication in the current unbound state, run:"
		say "    /usr/bin/lan8651-spi-test.sh spi0.1"
	fi
	if [ -f /usr/bin/lan8651-bind.sh ]; then
		say "  To force a LAN865x driver probe and inspect probe logs, run:"
		say "    /usr/bin/lan8651-bind.sh spi0.1 lan8650"
	fi
fi

exit 1