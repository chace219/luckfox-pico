#!/bin/bash

#################################################
# 	Board Config
#################################################
export LF_ORIGIN_BOARD_CONFIG=BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk
# Target CHIP
export RK_CHIP=rv1106

# app config
export RK_APP_TYPE=RKIPC_RV1106

# Config CMA size in environment
export RK_BOOTARGS_CMA_SIZE="66M"

# Kernel dts
export RK_KERNEL_DTS=rv1106g-luckfox-pico-ultra.dts

#################################################
#	BOOT_MEDIUM
#################################################

# Target boot medium
export RK_BOOT_MEDIUM=emmc

# Uboot defconfig fragment
export RK_UBOOT_DEFCONFIG_FRAGMENT="rk-emmc.config rv1106-luckfox-rgb-reset.config"

# specify post.sh for delete/overlay files
# export RK_PRE_BUILD_OEM_SCRIPT=rv1103-spi_nor-post.sh

# config partition in environment
# A/B VARIANT of the Pico Ultra board config — identical except the
# partition layout below. Select with ./build.sh lunch. Spike runbook:
# media/joral/ab-boot/README.md.
#
# RK_PARTITION_CMD_IN_ENV format:
#     <partdef>[,<partdef>]
#       <partdef> := <size>[@<offset>](part-name)
# Note:
#   If the first partition offset is not 0x0, it must be added. Otherwise, it needn't adding.
# ── A/B update layout (swupdate-implementation-plan.md) ─────────────────────
# ***FROZEN 2026-08-19 — one-way door #1.*** This line is the source of truth
# for the flash layout of every shipped unit. Enforced by
# scripts/compliance/check-partition-layout.sh (`./build.sh partitions`), which
# holds its own copy of the string and asserts every consumer against it — the
# two SocToolKit flashing maps, sw-description.in's install targets, the
# generated blkdevparts and by-name links, and image occupancy per partition.
# Editing the line below without editing the gate is caught; editing both is a
# deliberate layout change, and after the first customer unit ships that is a
# truck roll, not a release.
#
# Deltas vs the single-slot layout:
#   misc      4M   AVB A/B slot metadata (record at LBA start+4; see
#                  media/joral/ab-boot/src/misc_ab.c). Name must stay exactly
#                  "misc" — spl_ab_append_part_slot() special-cases it.
#   boot      32M  kernel+fdt+resource+ab-boot initramfs FIT (single copy in
#                  v1 — the initramfs picks the rootfs slot)
#   boot_b    32M  RESERVED, empty in v1: lets kernel-slot A/B ship later via
#                  the updater without repartitioning
#   userdata  512M (was 256M) now also carries both products' state/
#                  (Phase 0) beside the audit logs. Measured use 18M; growing
#                  it to 1024M was considered and declined 2026-08-19 (see the
#                  swupdate plan) — the audit cap is a rootfs variable, not a
#                  partition limit.
#   rootfs_a/rootfs_b 1536M each (~10x the current 151M image)
# Partition indices: p1 env, p2 idblock, p3 uboot, p4 misc, p5 boot,
# p6 boot_b, p7 oem, p8 userdata, p9 rootfs_a, p10 rootfs_b.
# INDICES SHIFTED vs single-slot — the hand-maintained consumers, all checked
# by `./build.sh partitions`:
#   - tools/*/SocToolKit/ipc.json: image->partition map + byte offsets, read by
#     the factory flashing station
#   - media/joral/ab-boot/swupdate/sw-description.in: /dev/mmcblk0p9 and p10,
#     the partitions an update installs onto
# build.sh handles the rootfs_a name (it strips `_a` when deriving root=).
# NOT in that list, contrary to what this comment said until 2026-08-19:
# sysdrv/tools/board/emmc/emmc_fstab. No build rule installs it — the shipped
# mounts come from the GENERATED /etc/init.d/S20linkmount. See its header.
export RK_PARTITION_CMD_IN_ENV="32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),512M(oem),512M(userdata),1536M(rootfs_a),1536M(rootfs_b)"

# config partition's filesystem type (squashfs is readonly)
# emmc:    squashfs/ext4
# nand:    squashfs/ubifs
# spi nor: squashfs/jffs2
# RK_PARTITION_FS_TYPE_CFG format:
#     AAAA:/BBBB/CCCC@ext4
#         AAAA ----------> partition name
#         /BBBB/CCCC ----> partition mount point
#         ext4 ----------> partition filesystem type
export RK_PARTITION_FS_TYPE_CFG=rootfs_a@IGNORE@ext4,userdata@/userdata@ext4,oem@/oem@ext4

# config filesystem compress (Just for squashfs or ubifs)
# squashfs: lz4/lzo/lzma/xz/gzip, default xz
# ubifs:    lzo/zlib, default lzo
# export RK_SQUASHFS_COMP=xz
# export RK_UBIFS_COMP=lzo

#################################################
#	TARGET_ROOTFS
#################################################

# Target rootfs
export LF_TARGET_ROOTFS=buildroot

# Buildroot defconfig
export RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig

#################################################
# 	Defconfig
#################################################

# Target arch
export RK_ARCH=arm

# Target Toolchain Cross Compile
export RK_TOOLCHAIN_CROSS=arm-rockchip830-linux-uclibcgnueabihf

#misc image
export RK_MISC=wipe_all-misc.img

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
#export RK_CAMERA_SENSOR_IQFILES="sc4336_OT01_40IRC_F16.json sc3336_CMK-OT2119-PC1_30IRC-F16.json sc530ai_CMK-OT2115-PC1_30IRC-F16.json"

# Config sensor lens CAC calibrattion bin files
export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16"
#export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16 CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16"

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
#export RK_ENABLE_WIFI_CHIP=AIC8800DC

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
export RK_POST_OVERLAY="overlay-luckfox-config overlay-luckfox-buildroot-init overlay-luckfox-buildroot-shadow overlay-luckfox-buildroot-rgb"
