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
# ── RE-CUT 2026-09-01 from 4165 MiB to 549 MiB, and RE-FROZEN ──────────────
# The freeze was re-opened deliberately, on the one ground that makes it
# possible: no customer unit has shipped (ship-blockers-one-way-doors.html —
# the door shuts on the first unit, not on the first freeze). It will not be
# re-openable a second time.
#
# WHY. The product is migrating to the Pico Max, which carries 256 MB of SPI
# NAND against this board's 8 GB eMMC. Sizing that board revealed that this
# one had never been sized at all: the slots were ~13x the image and
# oem/userdata were 512 M each while oem.img holds an EMPTY tree. The 8 GB
# table was inherited, not chosen.
#
# ONE TABLE ON BOTH BOARDS WAS TRIED AND ABANDONED, and the reason is worth
# recording because it looks like it should work. A shared 256 MB table needs
# each rootfs slot under ~90 M. On NAND that is easy — ubifs COMPRESSES, and
# this tree packs to 48 M. On eMMC it is impossible: ext4 does not compress,
# the same tree packs to 116 M (that is already `resize2fs -M`, the minimum
# for the content, not padding), and two 116 M slots do not fit 256 MB. The
# obvious escape — run ubifs on the eMMC too — is not available: build.sh
# packs `ubifs` as a UBI image unconditionally, and UBI is an MTD layer, not
# a block-device one. So the two boards get two tables, each native to its
# medium, and the gate freezes BOTH. See
# BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Max-IPC-AB.mk.
#
# The sizes are measured, not guessed (2026-09-01, build 2026.08.17):
#   rootfs staged tree                        80 M
#   packed ext4  (THIS board, read-write)    116 M  ← what a slot holds
#   packed ubifs-zlib (Max, read-write)       48 M
#   packed squashfs-xz (read-only option)     33 M
# Both products are INSIDE that image — satisense-edge's console and daemon,
# media-gateway, the J1939 tools, python3 and the help docs. This re-cut
# removes no feature; nothing was dropped to make it fit.
#
# THE ROOTFS STAYS READ-WRITE, on both boards. A read-only squashfs rootfs
# was staged first and REVERSED on 2026-09-01: "it is smaller" is not a
# reason to change what the running system can do, and two things break
# concretely under it —
#
#   - S50sshd persists the SSH host identity by writing SYMLINKS into
#     /etc/ssh (`ln -sf` to /userdata/platform/ssh) and by running
#     `ssh-keygen -A`, which writes /etc/ssh directly. On a read-only rootfs
#     both fail, and the failure mode is the one that script exists to
#     prevent: a changed host identity, so every update looks to an operator
#     like a man-in-the-middle.
#   - luckfox-config and the console's recovery paths write under /etc.
#
# Those are fixable, but fixing them is a behaviour change bundled into what
# is supposed to be a partition change, and it would surface on hardware
# rather than here. The slots are sized for the read-write image instead.
#
# EVERY partition below is a multiple of 256 KiB, and so is every offset.
# The eMMC does not require it — the Max's NAND does, and keeping the two
# tables structurally identical (same names, same order, same INDICES, same
# alignment discipline; only the sizes differ) is what lets one
# sw-description, one set of flashing-map semantics and one gate cover both.
# It is why the header partitions moved off their eMMC-native sizes
# (32K/512K/256K env/idblock/uboot became 256K/256K/512K).
#
#   env       256K (was 32K) — U-Boot environment. Grown only to reach the
#                  alignment floor; the environment itself is unchanged.
#   idblock   256K (was 512K) — packed idblock.img is 184K.
#   uboot     512K (was 256K) — packed uboot.img is 256K, so this doubles the
#                  headroom rather than shrinking it.
#   misc      4M   AVB A/B slot metadata (record at LBA start+4; see
#                  media/joral/ab-boot/src/misc_ab.c). Name must stay exactly
#                  "misc" — spl_ab_append_part_slot() special-cases it. The
#                  RECORD is one 512-byte sector, but RK_MISC packs a 4M
#                  wipe_all-misc.img, so the partition stays 4M: the gate
#                  measures the packed image, not the record.
#   boot      8M   kernel+fdt+resource+ab-boot initramfs FIT (single copy in
#                  v1 — the initramfs picks the rootfs slot). Was 32M; the
#                  packed boot.img is 4.5M, so this keeps ~44% headroom.
#   boot_b    8M   RESERVED, empty in v1: lets kernel-slot A/B ship later via
#                  the updater without repartitioning. Unchanged in PURPOSE —
#                  only in size, and it is still a boot.img-sized hole.
#   oem       16M  (was 512M) the payload is EMPTIED by
#                  luckfox-joral-oem-pre.sh, so this holds an empty ext4 —
#                  1.3M packed. 16M rather than 2M only because deleting or
#                  shrinking it further buys nothing and renumbering it would
#                  move every partition after it.
#   userdata  128M (was 512M) both products' state/ (Phase 0) beside the audit
#                  logs. Measured use 18M, so this is ~7x headroom. The audit
#                  cap stays a rootfs variable, not a partition limit — and it
#                  is set small, per the 2026-09-01 decision that this product
#                  does not retain much audit history. Sized larger than the
#                  Max's 59M because this board has the room and userdata is
#                  the one partition whose growth is operational (logs) rather
#                  than a release event.
#   rootfs_a/rootfs_b 192M each (was 1536M), landing on 0x0A500000 and
#                  0x16500000. The packed ext4 is 116M — 60% occupancy, with
#                  76M of growth room in the one dimension that cannot be
#                  widened on a fielded unit. 1536M was ~13x the image.
# The table totals 549 MiB, down from 4165 MiB: an 87% reduction with every
# feature intact and the rootfs still read-write. The remaining ~6.6 GB of
# eMMC is unallocated and is the append-only escape hatch described above —
# far more of it than before, which makes the hatch more useful, not less.
#
# Partition indices are UNCHANGED by this re-cut — p1 env, p2 idblock,
# p3 uboot, p4 misc, p5 boot, p6 boot_b, p7 oem, p8 userdata, p9 rootfs_a,
# p10 rootfs_b — so sw-description.in's /dev/mmcblk0p9 and p10 still name the
# rootfs slots. Only OFFSETS and SIZES move, which is exactly what the
# SocToolKit maps encode. The hand-maintained consumers, all checked by
# `./build.sh partitions`:
#   - tools/*/SocToolKit/ipc.json: image->partition map + byte offsets, read by
#     the factory flashing station
#   - media/joral/ab-boot/swupdate/sw-description.in: /dev/mmcblk0p9 and p10,
#     the partitions an update installs onto
# build.sh handles the rootfs_a name (it strips `_a` when deriving root=).
# NOT in that list, contrary to what this comment said until 2026-08-19:
# sysdrv/tools/board/emmc/emmc_fstab. No build rule installs it — the shipped
# mounts come from the GENERATED /etc/init.d/S20linkmount. See its header.
export RK_PARTITION_CMD_IN_ENV="32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),64M(oem),512M(userdata),768M(rootfs_a),768M(rootfs_b)"

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
# UNCHANGED by the 2026-09-01 re-cut, and deliberately so: ext4 everywhere,
# all three partitions READ-WRITE. The re-cut changed how much space each
# partition gets, not what the running system can do with it. See the layout
# comment above for why the read-only squashfs variant was staged and
# reversed.
#
# ext4 is what sets this board's slot size: it does not compress, so the 80 M
# staged tree packs to a ~116 M image and the slot is 192 M. The Max's NAND
# profile reaches a far smaller slot with ubifs, which does compress — that
# difference in filesystem is exactly why the two boards carry two tables
# rather than one. ubifs is NOT an option here: build.sh packs it as a UBI
# image unconditionally, and UBI is an MTD layer, not a block-device one.
export RK_PARTITION_FS_TYPE_CFG=rootfs_a@IGNORE@ext4,userdata@/userdata@ext4,oem@/oem@ext4

# config filesystem compress (Just for squashfs or ubifs)
# squashfs: lz4/lzo/lzma/xz/gzip, default xz
# ubifs:    lzo/zlib, default lzo
# Neither applies: ext4 is uncompressed. Left as the BSP had them.
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
