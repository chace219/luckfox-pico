#!/bin/bash

#################################################
# 	Board Config
#################################################
# A/B profile for the Luckfox Pico Max — the SPI NAND sibling of
# BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk.
#
# Created 2026-09-01 for the Ultra -> Max migration. The two profiles ship the
# SAME product (media-gateway + satisense-edge), the SAME buildroot defconfig
# and the SAME partition table; they differ only in the boot medium and the
# things that genuinely follow from it — filesystem types, the U-Boot fragment,
# the DTS, and the absence of the RGB overlay.
#
# The partition table below is BYTE-FOR-BYTE the Ultra's, and
# scripts/compliance/check-partition-layout.sh asserts that of both files. That
# is the point of the 2026-09-01 re-cut: the layout facts that cannot be
# derived at build time (the factory flashing maps, the updater's install
# targets, the compliance documents) stay ONE set of facts covering both
# boards, rather than two that drift.
export LF_ORIGIN_BOARD_CONFIG=BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk
# Target CHIP
export RK_CHIP=rv1106

# app config
export RK_APP_TYPE=RKIPC_RV1106

# Config CMA size in environment
export RK_BOOTARGS_CMA_SIZE="66M"

# Kernel dts
# The Max shares the Pro Max device tree: same RV1106G, same SFC-attached SPI
# NAND (&sfc / flash@0 compatible = "spi-nand"), same pinout. If a Max-specific
# DTS is ever added, this is the line to change — nothing else here assumes it.
export RK_KERNEL_DTS=rv1106g-luckfox-pico-pro-max.dts

#################################################
#	BOOT_MEDIUM
#################################################

# Target boot medium: emmc/spi_nor/spi_nand
export RK_BOOT_MEDIUM=spi_nand

# Uboot defconfig fragment
# rk-sfc.config is the SPI-flash controller fragment (the Ultra uses
# rk-emmc.config). The Ultra additionally carries
# rv1106-luckfox-rgb-reset.config; the Max has no RGB display, so it is absent
# here, and so is the matching overlay further down.
export RK_UBOOT_DEFCONFIG_FRAGMENT=rk-sfc.config

# config partition in environment
# RK_PARTITION_CMD_IN_ENV format:
#     <partdef>[,<partdef>]
#       <partdef> := <size>[@<offset>](part-name)
# Note:
#   If the first partition offset is not 0x0, it must be added. Otherwise, it needn't adding.
# ── A/B update layout — the NAND table ─────────────────────────────────────
# ***FROZEN 2026-09-01 — one-way door #1.*** Do not edit this line alone.
# `./build.sh partitions` asserts it against its own constant, together with
# the Ultra's table, the two SocToolKit flashing maps, sw-description.in's
# install targets, the generated blkdevparts and by-name links, and image
# occupancy per partition.
#
# TWO TABLES, NOT ONE, and the reason belongs here because the alternative
# looks obviously better. A single shared table was tried first. It fails on
# the FILESYSTEM, not on the sizes: this board's rootfs is ubifs, which
# COMPRESSES the 80 M staged tree to 48 M, while the Ultra's eMMC rootfs is
# ext4, which does not compress and needs 116 M for the same tree. Two 116 M
# slots do not fit 256 MB. Running ubifs on the eMMC instead is not available
# — build.sh packs ubifs as a UBI image unconditionally and UBI is an MTD
# layer, not a block-device one.
#
# So the two profiles share STRUCTURE and differ in SIZE: same partition
# names, same order, same INDICES (p9/p10 are the rootfs slots on both), same
# 256 KiB alignment. That is what lets one sw-description and one gate cover
# both boards. What differs is only how much space each partition gets.
#
# What matters on THIS board specifically:
#
#   - The table consumes the Max's 256 MB SPI NAND EXACTLY, with no tail. The
#     Ultra leaves ~6.6 GB of its eMMC unallocated as an append-only escape
#     hatch; that hatch DOES NOT EXIST here. On the Max the chip is full.
#
#     *** VERIFY THE FITTED PART BEFORE THE FIRST FLASH. *** 256 MB is an
#     assumption, and this SDK shows it is not a safe one across the range:
#     the RV1103 SPI NAND profiles (Pico Mini/Plus/WebBee) are built for a
#     128 MB part, and only the Pro Max profile assumes 256 MB. A revision or
#     a second-source part could be half of what this table needs, and the
#     failure is total rather than gradual — 2x80M slots alone do not fit a
#     128 MB chip, so rootfs_b would have no flash behind it. On a unit:
#         dmesg | grep -i 'spi-nand\|mtd'   -> the chip and its size
#         cat /proc/mtd                     -> the partitions actually created
#     A 128 MB part needs its own table and its own entry in the gate, not a
#     trimmed rootfs slot.
#
#   - Every offset and every size is a multiple of 256 KiB, the erase-block
#     size of the 4K-page SPI NAND class this board uses. A UBI partition that
#     begins or ends mid-erase-block will not attach. This is why the header
#     partitions are 256K/256K/512K rather than the eMMC-native 32K/512K/256K
#     the Ultra used before the re-cut — those three were what made every
#     later offset unaligned. The gate checks the alignment of both profiles.
#
#   - 80M rootfs slots hold a 48M read-write ubifs-zlib image (measured
#     2026-09-01, build 2026.08.17, both products and python3 included).
#     The number that matters is occupancy AFTER UBI's own overhead, which the
#     image size does not show: an 80 MiB volume of 256 KiB PEBs reserves 2
#     PEBs for the layout volume, ~2% for bad blocks and 1 for wear
#     levelling, and each PEB carries a 248 KiB LEB — so ~75 M is reachable
#     and the image sits at ~63% of it.
#
#   - userdata is 59M here against the Ultra's 128M, for the obvious reason:
#     this chip has 256 MB total. Measured use is 18M, so it is still >3x.
export RK_PARTITION_CMD_IN_ENV="256K(env),256K@256K(idblock),512K(uboot),4M(misc),8M(boot),8M(boot_b),16M(oem),49152K(userdata),80M(rootfs_a),80M(rootfs_b)"

# config partition's filesystem type (squashfs is readonly)
# emmc:    squashfs/ext4
# nand:    squashfs/ubifs
# spi nor: squashfs/jffs2
# RK_PARTITION_FS_TYPE_CFG format:
#     AAAA:/BBBB/CCCC@ext4
#         AAAA ----------> partition name
#         /BBBB/CCCC ----> partition mount point
#         ext4 ----------> partition filesystem type
#
# DIVERGES from the Ultra (ext4 everywhere) because ext4 is not a NAND
# filesystem — it has no wear levelling and no bad-block handling, and the raw
# MTD is not a block device. Everything here is carried on UBI.
#
# ALL THREE ARE READ-WRITE ubifs, the rootfs included. A read-only
# squashfs-on-UBI rootfs was staged first (33M, which would have allowed 64M
# slots) and REVERSED on 2026-09-01: the saving is real but it changes what
# the running system can do, and two things break concretely —
#
#   - S50sshd persists the SSH host identity by writing SYMLINKS into
#     /etc/ssh and by running `ssh-keygen -A`, which writes /etc/ssh
#     directly. Both fail on a read-only rootfs, producing exactly the
#     failure that script exists to prevent: a changed host identity, so
#     every update looks to an operator like a man-in-the-middle.
#   - luckfox-config and the console's recovery paths write under /etc.
#
# Fixing those is a behaviour change that would surface on hardware; it does
# not belong bundled into a partition change. The slot is sized for the
# read-write image instead, and the board keeps the same runtime behaviour as
# the Ultra — which is the property that actually matters when one product
# ships on two boards.
#
# userdata is written continuously (config, state, audit log); oem is empty
# but stays writable for the runtime S22oemclean path, as on the Ultra.
export RK_PARTITION_FS_TYPE_CFG=rootfs_a@IGNORE@ubifs,userdata@/userdata@ubifs,oem@/oem@ubifs

# config filesystem compress (Just for squashfs or ubifs)
# squashfs: lz4/lzo/lzma/xz/gzip, default xz
# ubifs:    lzo/zlib, default lzo
# zlib rather than the lzo default, and it is load-bearing: zlib packs this
# tree to 48M against lzo's 52M, and the 80M slot was sized against the 48M
# figure. lzo decompresses faster, but the margin is not there to spend.
export RK_UBIFS_COMP=zlib

#################################################
#	TARGET_ROOTFS
#################################################

# Target rootfs
export LF_TARGET_ROOTFS=buildroot

# Buildroot defconfig
# The SAME defconfig as the Ultra. No package was removed to reach 256 MB —
# the re-cut was sized against the image this defconfig already produces, so
# both products, the J1939 tools, python3 and the bundled help docs are all
# present on the Max exactly as they are on the Ultra.
export RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig

#################################################
# 	Defconfig
#################################################

# Target arch
export RK_ARCH=arm

# Target Toolchain Cross Compile
export RK_TOOLCHAIN_CROSS=arm-rockchip830-linux-uclibcgnueabihf

#misc image
export RK_MISC=ab-misc.img

# Uboot defconfig
export RK_UBOOT_DEFCONFIG=luckfox_rv1106_uboot_defconfig

# Kernel defconfig
export RK_KERNEL_DEFCONFIG=luckfox_rv1106_linux_defconfig

# Kernel defconfig fragment
export RK_KERNEL_DEFCONFIG_FRAGMENT=rv1106-bt.config

# Config sensor IQ files
# RK_CAMERA_SENSOR_IQFILES format:
#     "iqfile1 iqfile2 iqfile3 ..."
# ./build.sh media and copy <SDK root dir>/output/out/media_out/isp_iqfiles/$RK_CAMERA_SENSOR_IQFILES
export RK_CAMERA_SENSOR_IQFILES="sc4336_OT01_40IRC_F16.json sc3336_CMK-OT2119-PC1_30IRC-F16.json mis5001_CMK-OT2115-PC1_30IRC-F16.json"

# Config sensor lens CAC calibrattion bin files
export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16"

# build ipc web backend
#export RK_APP_IPCWEB_BACKEND=y

# enable install app to oem partition
export RK_BUILD_APP_TO_OEM_PARTITION=y

# enable rockchip test
export RK_ENABLE_ROCKCHIP_TEST=y

# rockchip wifi disabled 2026-08-12: neither product has a Wi-Fi function, no
# init script started any of it, and the SSID/PSK below were never set past
# the BSP placeholders. Enabling this ships hostapd 2.6 / wpa_supplicant 2.6
# (2016) plus prebuilt dnsmasq/iperf into /usr/bin, outside the SBOM and the
# CVE gate (cve-check) entirely. Re-enabling requires declaring every binary
# in scripts/compliance/ first.
export RK_ENABLE_WIFI=n

# config wifi ssid and passwd
#export LF_WIFI_SSID="Your wifi ssid"
#export LF_WIFI_PSK="Your wifi password"

#################################################
#  PRE and POST
#################################################

# specify pre.sh for delete/overlay files
# Joral profiles empty the oem payload instead of pruning it (CRA Annex I #4,
# compliance plan item 14). The stock luckfox-buildroot-oem-pre.sh deleted a
# handful of duplicate libraries and left 198 files / 21 MB of Rockchip IPC
# demo suite that nothing on this product runs; this one rescues the two
# modules that are used into the rootfs and drops the rest. Asserted by
# ./build.sh oem.
export RK_PRE_BUILD_OEM_SCRIPT=luckfox-joral-oem-pre.sh

# specify post.sh for delete/overlay files
export RK_PRE_BUILD_USERDATA_SCRIPT=luckfox-userdata-pre.sh

# image hardening: removes BSP-supplied services we do not ship (see script)
export RK_POST_BUILD_SCRIPT=luckfox-hardening-post.sh

# declare overlay directory
# Same set as the Ultra MINUS overlay-luckfox-buildroot-rgb: that overlay ships
# S25backlight, which insmods the pwm_bl.ko rescued by the oem pre-script for
# the Ultra's RGB display. The Max has no such display, so the overlay would
# install an init script for hardware that is not on the board.
export RK_POST_OVERLAY="overlay-luckfox-config overlay-luckfox-buildroot-init overlay-luckfox-buildroot-shadow"
