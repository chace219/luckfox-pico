#!/bin/sh
# lan8651-spi-test.sh - Temporarily bind spi0.1 to spidev and run the OA-TC6
# Python register probe.  Now also reads internal PHY PHYSID1/PHYSID2.
# Usage: lan8651-spi-test.sh [spi-device]

say() {
	printf '%s\n' "$*"
}

device="${1:-spi0.1}"
speed="${LAN8651_SPI_SPEED:-500000}"
sysfs_dev="/sys/bus/spi/devices/${device}"
spidev_node="/dev/spidev${device#spi}"
probe_script="/usr/bin/lan8651-spi-probe.py"
override_path="${sysfs_dev}/driver_override"
spidev_bind="/sys/bus/spi/drivers/spidev/bind"
spidev_unbind="/sys/bus/spi/drivers/spidev/unbind"
temporary_bind=0

cleanup() {
	if [ "$temporary_bind" -eq 1 ]; then
		if [ -w "$spidev_unbind" ]; then
			echo "$device" > "$spidev_unbind" 2>/dev/null || true
		fi
		if [ -w "$override_path" ]; then
			printf '\n' > "$override_path" 2>/dev/null || true
		fi
	fi
}

trap cleanup EXIT INT TERM

if [ ! -d "$sysfs_dev" ]; then
	say "${device} does not exist in /sys/bus/spi/devices"
	say "The running kernel has not instantiated the LAN8651 SPI device yet."
	exit 1
fi

current_driver="(unbound)"
if [ -L "${sysfs_dev}/driver" ]; then
	current_driver=$(basename "$(readlink -f "${sysfs_dev}/driver")")
fi

say "LAN8651 raw SPI test"
say "  spi device:   ${device}"
say "  driver:       ${current_driver}"
say "  spidev node:  ${spidev_node}"
say "  spi speed:    ${speed} Hz"

if [ ! -x "$probe_script" ]; then
	say "Probe helper ${probe_script} is not present or not executable."
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	say "python3 is not available on the target image."
	exit 1
fi

if [ ! -e "$spidev_node" ]; then
	if [ "$current_driver" != "(unbound)" ] && [ "$current_driver" != "spidev" ]; then
		say "${device} is already bound to ${current_driver}; refusing to steal it for raw testing."
		exit 1
	fi

	if [ ! -d /sys/bus/spi/drivers/spidev ]; then
		say "spidev driver is not registered in the running kernel."
		exit 1
	fi

	if [ ! -w "$override_path" ] || [ ! -w "$spidev_bind" ]; then
		say "Cannot bind ${device} to spidev via sysfs. Run as root on the target."
		exit 1
	fi

	say "Temporarily binding ${device} to spidev for raw register access"
	echo spidev > "$override_path"
	echo "$device" > "$spidev_bind"
	temporary_bind=1
fi

if [ ! -e "$spidev_node" ]; then
	say "${spidev_node} was not created after spidev bind attempt."
	exit 1
fi

python3 "$probe_script" --device "$spidev_node" --speed "$speed"