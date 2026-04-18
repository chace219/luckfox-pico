#!/bin/sh

set -eu

say() {
	printf '%s\n' "$*"
}

read_dt_u32_be() {
	[ -f "$1" ] || return 1
	set -- $(od -An -tx1 -N4 "$1" 2>/dev/null)
	[ "$#" -eq 4 ] || return 1
	printf '%d' "$((0x$1 * 16777216 + 0x$2 * 65536 + 0x$3 * 256 + 0x$4))"
}

have_dt_node=0
have_spi0_master=0
have_spi01_device=0
have_eth1=0
have_lan865x_driver=0
spi0_num_cs="(missing)"

if [ -f /sys/firmware/devicetree/base/spi@ff500000/num-cs ]; then
	spi0_num_cs=$(read_dt_u32_be /sys/firmware/devicetree/base/spi@ff500000/num-cs 2>/dev/null || echo "(invalid)")
fi

if grep -a -r -q 'microchip,lan8650\|microchip,lan8651' /sys/firmware/devicetree/base 2>/dev/null; then
	have_dt_node=1
fi

if [ -d /sys/class/spi_master/spi0 ]; then
	have_spi0_master=1
fi

if [ -d /sys/bus/spi/devices/spi0.1 ]; then
	have_spi01_device=1
fi

if [ -d /sys/class/net/eth1 ]; then
	have_eth1=1
fi

if [ -d /sys/bus/spi/drivers/lan8650 ] || [ -d /sys/bus/spi/drivers/lan8651 ]; then
	have_lan865x_driver=1
fi

say "LAN8651 stage check"
say ""
say "Observed state:"
say "  running DT has LAN8651 node: ${have_dt_node}"
say "  spi0 master exists:          ${have_spi0_master}"
say "  spi0 num-cs:                 ${spi0_num_cs}"
say "  spi0.1 device exists:        ${have_spi01_device}"
say "  LAN865x SPI driver present:  ${have_lan865x_driver}"
say "  eth1 exists:                 ${have_eth1}"

say ""
say "Interpretation:"

if [ "$have_dt_node" -eq 0 ]; then
	say "  The running image does not contain the LAN8651 device-tree node."
	say "  This is a build/boot/DTB selection problem in the software project."
	say "  Wiring is not the primary reason yet, because Linux never tried to create the shield device."
	exit 1
fi

if [ "$have_spi0_master" -eq 0 ]; then
	say "  The running DT has a LAN8651 node, but spi0 is not present as a master."
	say "  This still points first to software configuration or DT mismatch, not to LAN8651 chip responsiveness."
	exit 1
fi

if [ "$have_spi01_device" -eq 0 ]; then
	say "  spi0 exists, but spi0.1 was not instantiated."
	if [ "$spi0_num_cs" = "1" ] || [ "$spi0_num_cs" = "(missing)" ]; then
		say "  The likely cause is that spi0 is configured for only one chip select."
		say "  The Rockchip SPI driver defaults to one CS unless DT sets num-cs = <2>."
		say "  With that setting missing, chip-select 1 cannot appear as spi0.1."
	else
		say "  This usually means the active DT does not describe the child device the way the running kernel expects."
	fi
	say "  Hardware wiring on MOSI/MISO/SCK/CS does not by itself prevent spi0.1 from appearing in sysfs."
	say "  So the first suspicion is still software/DT/image mismatch."
	exit 1
fi

if [ "$have_eth1" -eq 0 ]; then
	say "  spi0.1 exists, but eth1 does not."
	if [ "$have_lan865x_driver" -eq 0 ]; then
		say "  The LAN865x SPI driver is not registered in the running kernel."
		say "  This points first to kernel config/image mismatch, not to shield wiring."
	else
		say "  The driver exists in the kernel, so the remaining problem is bind/probe or actual SPI communication."
		say "  At this stage, wiring can absolutely be the cause."
	fi
	if command -v dmesg >/dev/null 2>&1; then
		say ""
		say "Recent relevant dmesg lines:"
		dmesg | grep -i 'lan865\|oa-tc6\|oa_tc6\|microchip\|spi0\.1' | tail -n 80 || true
	fi
	exit 1
fi

say "  eth1 is present. The LAN8651 path is up far enough for Linux to expose the interface."
exit 0