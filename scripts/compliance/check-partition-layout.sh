#!/bin/bash
# Freeze gate for the A/B partition layout — CRA Annex I Part I #7 (update
# mechanism), plan item 11, one-way door #1.
#
# WHAT IS FROZEN. The table below is the flash layout of every unit built from
# the `-AB` board profile. The moment a customer unit ships it is frozen FOR
# THAT UNIT'S LIFETIME: the updater delivers one payload, `rootfs.img`, to one
# of two slots. It cannot repartition, it cannot move `oem`, and it cannot grow
# a slot. A layout change after first shipment is a truck roll, not a release.
#
# WHY THIS IS A SCRIPT AND NOT A COMMENT. The table is written down once but
# CONSUMED in five places, three of which cannot be derived at build time:
#
#   - project/cfg/.../-IPC-AB.mk        the source of truth (RK_PARTITION_CMD_IN_ENV)
#   - tools/{linux,windows}/SocToolKit/ipc.json   hand-maintained BYTE OFFSETS,
#                                       used by the factory flashing station
#   - media/joral/ab-boot/swupdate/sw-description.in   hand-written /dev/mmcblk0p9
#                                       and p10 — the install targets
#   - output/image/.env.txt             generated (blkdevparts)
#   - the shipped S20linkmount          generated (by-name symlinks)
#
# The two generated ones can never disagree. The three hand-maintained ones
# can, and a disagreement is not a build failure — it is a factory station
# writing `oem.img` over `userdata`, or an update installing onto the running
# slot. Both are silent until hardware. So this asserts every consumer against
# ONE constant, and the constant is here rather than in the board config on
# purpose: a gate that reads its expectation out of the file it is checking
# cannot fail (the lesson from test-image-ownership.sh, 2026-08-19).
#
# Runs on a clean checkout — it reads the tree, not a build. The occupancy
# checks are additionally applied to output/image/ when a build is present.
#
# Usage: check-partition-layout.sh [--verbose]
set -u
cd "$(dirname "$0")/../.." || exit 2

# Reader for the packed rootfs — no longer always ext4. See its header.
. "$(dirname "$0")/rootfs-image-lib.sh"

# ── THE FROZEN TABLES ───────────────────────────────────────────────────────
# Do not edit these lines to make the gate pass. Editing one IS a layout change.
#
# RE-CUT 2026-09-01. The Ultra's table went from 4165 MiB to 549 MiB, and a
# second table was added for the Pico Max's 256 MB SPI NAND. Re-opening the
# freeze was legitimate only because no customer unit had shipped. That is now
# the last time it is legitimate.
#
# WHY TWO TABLES AND NOT ONE. A single shared table was tried first and does
# not work, for a reason that is not about sizes: the two boards cannot run
# the same filesystem. The Max's rootfs is ubifs, which COMPRESSES the 80 M
# staged tree to 48 M. The Ultra's is ext4 on a block device, which does not
# compress and needs 116 M for the same tree — and two 116 M slots do not fit
# 256 MB. Running ubifs on the eMMC instead is not available: build.sh packs
# ubifs as a UBI image unconditionally, and UBI is an MTD layer.
#
# What the two tables DO share is structure: same partition names, same order,
# same INDICES (p9/p10 are the rootfs slots on both), same 256 KiB alignment
# discipline. That is what lets one sw-description and one gate cover both.
# Only the sizes differ. The per-board checks below enforce the structure on
# each table rather than trusting that they were edited together.
FROZEN_EMMC="32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),64M(oem),512M(userdata),768M(rootfs_a),768M(rootfs_b)"
FROZEN_NAND="256K(env),256K@256K(idblock),512K(uboot),4M(misc),8M(boot),8M(boot_b),16M(oem),49152K(userdata),80M(rootfs_a),80M(rootfs_b)"

# A "256 MB" NAND is a true 256 MiB of usable pages (unlike a "8 GB" eMMC,
# whose usable capacity needs a conservative floor), so the NAND table has an
# exact budget: it must total this, with no tail.
#
# THIS IS AN ASSUMPTION ABOUT THE PART FITTED, AND IT IS NOT GUARANTEED.
# Luckfox does not fit one SPI NAND size across the range, and this SDK proves
# it: the RV1103 profiles (Pico Mini/Plus/WebBee) carry a 126 MiB table — a
# 128 MB part — while the Pro Max profile carries a 255 MiB one. A board
# revision, a second-source part, or simply a different SKU can therefore be
# HALF the size this table assumes, and the failure mode is not subtle: the
# NAND table consumes 256 MiB exactly, so on a 128 MB part the last partition
# (rootfs_b, and most of rootfs_a) has no chip behind it.
#
# There is no way to check that from the build host — the part is only visible
# on a unit. What CAN be done is to state the assumption where it will be read
# and to make the check fail loudly if the constant is edited without the
# table being resized, which is what the exact-total assertion below does.
#
# BEFORE THE FIRST MAX BUILD IS FLASHED, confirm the fitted part from the
# kernel log on a real unit:
#     dmesg | grep -i 'spi-nand\|mtd'      -> reports the chip and its size
#     cat /proc/mtd                        -> reports the partitions created
# A 128 MB part needs its own table (and its own frozen constant here), not a
# smaller rootfs slot: 2x80 M slots alone exceed such a chip.
NAND_TOTAL=$((256 * 1024 * 1024))

# Erase-block size of the 4K-page SPI NAND class the Max uses. Every partition
# offset AND size must be a multiple of it or the UBI volume will not attach.
# Checked on BOTH tables: the eMMC does not require it, but keeping the two
# structurally identical is the property that makes one sw-description and one
# set of flashing-map semantics correct for both boards.
NAND_ERASE_BLOCK=$((256 * 1024))
# Minimum unallocated tail. Luckfox's stock Pro_Max profile leaves 1 MiB on
# this same chip; a table ending at the last byte is refused by the flasher.
NAND_TAIL_MIN=$((1024 * 1024))

# Nominal 8 GB eMMC on the Pico Ultra. The eMMC table leaves ~6.6 GB
# unallocated; that tail is the post-freeze escape hatch (a partition APPENDED
# there shifts no existing index).
EMMC_USABLE_FLOOR=$((7200 * 1024 * 1024))

BOARDCFG=project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk
BOARDCFG_NAND=project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Max-IPC-AB.mk
IPC_JSONS="tools/linux/SocToolKit/ipc.json tools/windows/SocToolKit/ipc.json"
SWDESC=media/joral/ab-boot/swupdate/sw-description.in
# Both compliance documents that state the layout. Kept verbatim rather than
# reformatted for width: a wrapped copy cannot be checked, and an unchecked
# copy in the technical file is exactly the defect the 2026-08-19 freeze found.
PLANS="media/joral/swupdate-implementation-plan.md media/joral/cra-compliance-plan.md"
IMAGEDIR=output/image

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }
skip() { echo "skip — $1"; }
note() { [ $VERBOSE -eq 1 ] && echo "       $1"; return 0; }

# ── Parse the frozen table into name/offset/size, in partition order ────────
# Format: <size>[@<offset>](<name>)[,...]  — sizes K/M/G, first offset implicit 0.
NAMES=(); OFFSETS=(); SIZES=()
to_bytes() {
	local v=$1 n=${1%[KMGkmg]} u=${1: -1}
	case $u in
	K|k) echo $((n * 1024)) ;;
	M|m) echo $((n * 1024 * 1024)) ;;
	G|g) echo $((n * 1024 * 1024 * 1024)) ;;
	*)   echo "$v" ;;
	esac
}
parse_table() {
	local table=$1 cursor=0 part size off name
	NAMES=(); OFFSETS=(); SIZES=()
	local IFS=,
	for part in $table; do
		name=${part#*\(}; name=${name%\)}
		size=${part%%[@(]*}
		case $part in
		*@*) off=${part#*@}; off=${off%%(*} ;;
		*)   off="" ;;
		esac
		size=$(to_bytes "$size")
		if [ -n "$off" ]; then off=$(to_bytes "$off"); else off=$cursor; fi
		NAMES+=("$name"); OFFSETS+=("$off"); SIZES+=("$size")
		cursor=$((off + size))
	done
}
idx_of() {  # 1-based partition index of a name, or empty
	local want=$1 i
	for i in "${!NAMES[@]}"; do
		[ "${NAMES[$i]}" = "$want" ] && { echo $((i + 1)); return 0; }
	done
	return 1
}
count_of() {
	local want=$1 i n=0
	for i in "${!NAMES[@]}"; do [ "${NAMES[$i]}" = "$want" ] && n=$((n + 1)); done
	echo $n
}
size_of() {
	local want=$1 i
	for i in "${!NAMES[@]}"; do
		[ "${NAMES[$i]}" = "$want" ] && { echo "${SIZES[$i]}"; return 0; }
	done
	return 1
}
human() {  # bytes -> MiB with one decimal, or KiB below 1 MiB
	local b=$1
	if [ "$b" -lt $((1024 * 1024)) ]; then echo "$((b / 1024)) KiB"
	else echo "$(( (b * 10 / 1024 / 1024 + 5) / 10 )) MiB"; fi
}

# ── 1 & 2. Each board's profile carries its frozen table, and each table
#          satisfies the structural invariants ─────────────────────────────
# Both tables are checked in full. The structure is what the two boards SHARE
# — names, order, indices, alignment — so an edit that breaks it on one board
# is caught on that board rather than inferred from the other.
for BOARD in emmc nand; do
	case $BOARD in
	emmc)
		FROZEN=$FROZEN_EMMC; BC=$BOARDCFG
		LABEL="Ultra / eMMC"
		;;
	nand)
		FROZEN=$FROZEN_NAND; BC=$BOARDCFG_NAND
		LABEL="Max / SPI NAND"
		;;
	esac

	parse_table "$FROZEN"
	[ ${#NAMES[@]} -gt 0 ] || { echo "the frozen $BOARD table did not parse — this is a bug in this script"; exit 2; }

	echo
	echo "== Frozen A/B partition layout — $LABEL =="
	for i in "${!NAMES[@]}"; do
		note "$(printf 'p%-2d %-10s @ 0x%08X  %s' $((i + 1)) "${NAMES[$i]}" "${OFFSETS[$i]}" "$(human "${SIZES[$i]}")")"
	done

	if [ ! -f "$BC" ]; then
		bad "$BC missing — the A/B board profile is the thing being frozen"
	else
		actual=$(sed -n 's/^export RK_PARTITION_CMD_IN_ENV="\(.*\)"$/\1/p' "$BC")
		if [ "$actual" = "$FROZEN" ]; then
			ok "board profile matches its frozen table ($LABEL)"
		else
			bad "board profile does NOT match its frozen table ($LABEL)"
			echo "         frozen: $FROZEN"
			echo "         config: ${actual:-<not found>}"
		fi
	fi

	# `misc` must not carry a slot suffix: spl_ab_append_part_slot()
	# special-cases the literal name, and a `misc_a` would be invisible to the
	# bootloader.
	if [ "$(count_of misc)" = "1" ]; then
		ok "'misc' present exactly once and unsuffixed ($LABEL)"
	else
		bad "'misc' must appear exactly once, unsuffixed ($LABEL)"
	fi

	# Slots must be the same size — the updater writes one image to either.
	sa=$(size_of rootfs_a) || sa=""
	sb=$(size_of rootfs_b) || sb=""
	if [ -n "$sa" ] && [ "$sa" = "$sb" ]; then
		ok "rootfs_a and rootfs_b are the same size ($(human "$sa") each, $LABEL)"
	else
		bad "rootfs_a/rootfs_b missing or unequal ($LABEL: a=${sa:-none} b=${sb:-none})"
	fi

	# oem and userdata must survive a slot switch, so they must be single-copy.
	for p in oem userdata; do
		if [ "$(count_of "$p")" = "1" ] && ! idx_of "${p}_a" >/dev/null 2>&1; then
			ok "'$p' is single-copy ($LABEL)"
		else
			bad "'$p' must be single-copy, with no slot suffix ($LABEL)"
		fi
	done

	# boot_b is reserved and empty in v1; it exists so kernel-slot A/B can ship
	# later THROUGH the updater instead of needing a repartition.
	if idx_of boot_b >/dev/null; then
		ok "'boot_b' reserved ($LABEL)"
	else
		bad "'boot_b' missing — kernel-slot A/B would need a repartition ($LABEL)"
	fi

	# The partition INDICES are what the two boards must agree on: the
	# sw-description below names /dev/mmcblk0p9 and p10, and the initramfs
	# resolves by PARTNAME. If a partition moved index on one board only, one
	# of the two would install its update onto the wrong thing.
	if [ "$BOARD" = nand ]; then
		idxfail=0
		parse_table "$FROZEN_EMMC"; emmc_names="${NAMES[*]}"
		parse_table "$FROZEN_NAND"; nand_names="${NAMES[*]}"
		if [ "$emmc_names" = "$nand_names" ]; then
			ok "both tables carry the same partitions in the same order (so the same indices)"
		else
			bad "the two tables' partition order differs — one sw-description cannot be right for both"
			note "eMMC: $emmc_names"
			note "NAND: $nand_names"
			idxfail=1
		fi
		[ $idxfail -eq 0 ] || true
		parse_table "$FROZEN"
	fi

	# Contiguous, starting at 0, no gaps or overlaps.
	gapfail=0; cursor=0
	for i in "${!NAMES[@]}"; do
		if [ "${OFFSETS[$i]}" -ne "$cursor" ]; then
			bad "partition gap/overlap before '${NAMES[$i]}' ($LABEL): expected offset $cursor, table says ${OFFSETS[$i]}"
			gapfail=1
		fi
		cursor=$((OFFSETS[i] + SIZES[i]))
	done
	[ $gapfail -eq 0 ] && ok "table is contiguous from offset 0 ($LABEL)"

	TOTAL=$cursor

	# Every offset and size on a 256 KiB erase-block boundary. Required on the
	# NAND (a UBI partition that starts or ends mid-erase-block does not
	# attach). It is deliberately NOT applied to the eMMC.
	#
	# 2026-09-02: it once was, on the reasoning that identical structure across
	# the two boards makes one sw-description correct for both. That reasoning
	# was wrong and it bricked an Ultra. Satisfying the 256 KiB rule on eMMC
	# meant moving idblock from 32K to 256K, and the RV1106 BootROM is masked
	# silicon: it loads the first-stage loader from a FIXED offset (sector 64 =
	# 32 KiB) and never reads the partition table. The board went dark before
	# U-Boot -- no kernel, no init, so no RNDIS adapter, no SSH, no HTTP.
	#
	# eMMC is a block device behind a controller. It has no erase-block
	# alignment requirement at all, so this rule buys nothing there and costs
	# the one offset the silicon actually mandates.
	if [ "$BOARD" = nand ]; then
		alignfail=0
		for i in "${!NAMES[@]}"; do
			if [ $((OFFSETS[i] % NAND_ERASE_BLOCK)) -ne 0 ]; then
				bad "'${NAMES[$i]}' starts at ${OFFSETS[$i]}, not a multiple of the $(human "$NAND_ERASE_BLOCK") erase block ($LABEL)"
				alignfail=1
			fi
			if [ $((SIZES[i] % NAND_ERASE_BLOCK)) -ne 0 ]; then
				bad "'${NAMES[$i]}' is $(human "${SIZES[$i]}"), not a multiple of the $(human "$NAND_ERASE_BLOCK") erase block ($LABEL)"
				alignfail=1
			fi
		done
		[ $alignfail -eq 0 ] && ok "every offset and size is $(human "$NAND_ERASE_BLOCK")-aligned ($LABEL)"
	fi

	# The one offset the RV1106 BootROM mandates on eMMC. Non-negotiable:
	# the loader must live at 32 KiB or the board does not boot at all.
	if [ "$BOARD" = emmc ]; then
		idb_off=""
		for i in "${!NAMES[@]}"; do
			[ "${NAMES[$i]}" = idblock ] && idb_off="${OFFSETS[$i]}"
		done
		if [ -z "$idb_off" ]; then
			bad "no 'idblock' partition in the eMMC table -- the board cannot boot ($LABEL)"
		elif [ "$idb_off" -ne $((32 * 1024)) ]; then
			bad "'idblock' starts at $idb_off, not 32768 (32 KiB). The RV1106 BootROM reads the loader from that fixed offset and ignores the partition table -- this layout will not boot ($LABEL)"
		else
			ok "'idblock' sits at the BootROM's mandatory 32 KiB offset ($LABEL)"
		fi
	fi

	if [ "$BOARD" = nand ]; then
		# The chip's LAST erase blocks must stay unallocated. A table that
		# ends at exactly 0x10000000 is arithmetically valid and still fails
		# to flash: rkdevtool rejects the final partition with "Partition
		# ending is larger than flash size" (bench, 2026-09-02). Luckfox's own
		# Pro_Max profile -- same chip, known good -- totals 255 MiB and leaves
		# 1 MiB. So the tail is REQUIRED, not slack to be reclaimed, and this
		# check was previously backwards: it rewarded consuming the whole chip.
		if [ "$TOTAL" -gt $((NAND_TOTAL - NAND_TAIL_MIN)) ]; then
			bad "table totals $(human "$TOTAL"), leaving less than the required $(human "$NAND_TAIL_MIN") tail on a $(human "$NAND_TOTAL") chip — the flasher will reject the last partition"
		elif [ "$TOTAL" -le "$NAND_TOTAL" ]; then
			ok "table totals $(human "$TOTAL") — fits the Max's $(human "$NAND_TOTAL") SPI NAND with a $(human $((NAND_TOTAL - TOTAL))) tail"
		else
			bad "table totals $(human "$TOTAL"), past the Max's $(human "$NAND_TOTAL") SPI NAND — will not fit that board"
		fi
	else
		if [ "$TOTAL" -le "$EMMC_USABLE_FLOOR" ]; then
			ok "table totals $(human "$TOTAL") — fits the Ultra's conservative $(human "$EMMC_USABLE_FLOOR") eMMC floor"
			note "$(human $((EMMC_USABLE_FLOOR - TOTAL))) left unallocated on the Ultra. That tail is the only"
			note "post-freeze escape hatch: a partition APPENDED there shifts no existing"
			note "index, so it is the one layout change a fielded unit could survive."
			note "It does NOT exist on the Max, whose chip its table consumes exactly."
		else
			bad "table totals $(human "$TOTAL"), past the $(human "$EMMC_USABLE_FLOOR") usable eMMC floor"
		fi
	fi
done

# The remaining sections check the artifacts of a BUILD, and a build is of one
# board at a time -- so they must follow WHICH board was built, not assume the
# eMMC one. Until 2026-09-02 they hard-coded $FROZEN_EMMC, which made a
# perfectly good Max build report two failures (its env.img carries the NAND
# table and is 256 KiB, both correct for that board). A gate that fails on
# correct artifacts gets ignored, which is the same end state as no gate.
#
# The selected board is .BoardConfig.mk, a symlink build.sh maintains. Fall
# back to eMMC when it is absent (a bare checkout with no lunch yet).
BUILT_BOARD=emmc
BUILT_CFG=$(readlink -f .BoardConfig.mk 2>/dev/null || true)
if [ -n "$BUILT_CFG" ] && [ -f "$BUILT_CFG" ]; then
	if grep -q '^export RK_BOOT_MEDIUM=spi_nand' "$BUILT_CFG"; then
		BUILT_BOARD=nand
	fi
fi

if [ "$BUILT_BOARD" = nand ]; then
	FROZEN=$FROZEN_NAND
	# The kernel names the NAND partition table differently, and by-name links
	# on a UBI rootfs are not /dev/mmcblk0pN block nodes.
	ENV_KEY="mtdparts=spi-nand0:"
	ENV_SLOT_NAME=nand
	BUILT_LABEL="Max / SPI NAND"
else
	FROZEN=$FROZEN_EMMC
	ENV_KEY="blkdevparts=mmcblk0:"
	ENV_SLOT_NAME=emmc
	BUILT_LABEL="Ultra / eMMC"
fi
parse_table "$FROZEN"
note "build artifacts checked against the SELECTED board: $BUILT_LABEL"
echo

# ── 3. SocToolKit flashing maps — hand-maintained byte offsets ──────────────
# The factory station writes by ABSOLUTE OFFSET. A stale entry here does not
# fail a build; it writes an image over the wrong partition on a real unit.
# These maps carry ABSOLUTE BYTE OFFSETS, which is an eMMC notion: the station
# seeks to a byte and writes. SPI NAND is written by partition NAME through
# MTD, and ipc.json has no medium field and no second table -- one flat list of
# offsets, so it can only ever describe one board. It describes the Ultra.
# Checking it against whichever board happens to be lunched produced ten
# failures on a correct Max build, so it is checked only when the eMMC profile
# is the selected one.
if [ "$BUILT_BOARD" != emmc ]; then
	skip "SocToolKit flashing maps — eMMC-only artifacts (absolute byte offsets); selected board is $BUILT_LABEL"
	IPC_JSONS=""
fi
for J in $IPC_JSONS; do
	if [ ! -f "$J" ]; then
		bad "$J missing — the factory flashing map"
		continue
	fi
	jfail=0
	# names, in file order, ignoring the DownloadBin loader entry
	jnames=$(sed -n 's/^ *"name": "\(.*\)",$/\1/p' "$J" | grep -v '^DownloadBin$')
	jaddrs=$(grep -A2 '"name":' "$J" | sed -n 's/^ *"address": "\(0x[0-9A-Fa-f]*\)",\?$/\1/p')
	expect_names=$(printf '%s\n' "${NAMES[@]}")
	if [ "$jnames" != "$expect_names" ]; then
		bad "$J: partition names/order do not match the frozen table"
		note "expected: $(echo "$expect_names" | tr '\n' ' ')"
		note "found:    $(echo "$jnames" | tr '\n' ' ')"
		jfail=1
	fi
	i=0; addrfail=0
	while IFS= read -r a; do
		[ -z "$a" ] && continue
		if [ $i -ge ${#OFFSETS[@]} ]; then addrfail=1; break; fi
		want=$(printf '0x%08X' "${OFFSETS[$i]}")
		if [ "${a^^}" != "${want^^}" ]; then
			bad "$J: '${NAMES[$i]}' at $a, frozen table puts it at $want"
			addrfail=1
		fi
		i=$((i + 1))
	done <<< "$jaddrs"
	[ $addrfail -eq 0 ] && [ $jfail -eq 0 ] && ok "$J: names and byte offsets derive from the frozen table"
done

# ── 4. sw-description.in — the install targets, hardcoded by index ──────────
# The initramfs finds partitions by PARTNAME and is index-independent. This
# file is not: it names /dev/mmcblk0pN. If the indices shift, an update
# installs onto something that is not a rootfs slot.
if [ ! -f "$SWDESC" ]; then
	bad "$SWDESC missing"
else
	pa=$(idx_of rootfs_a) && pb=$(idx_of rootfs_b)
	got=$(sed -n 's@.*device = "/dev/mmcblk0p\([0-9]*\)".*@\1@p' "$SWDESC" | tr '\n' ' ')
	if [ "$got" = "$pa $pb " ]; then
		ok "$SWDESC targets p$pa/p$pb — the frozen rootfs_a/rootfs_b indices"
	else
		bad "$SWDESC targets partitions [$got], frozen table says rootfs_a=p$pa rootfs_b=p$pb"
	fi
fi

# ── 5. The documents quote the shipped table, not an earlier draft ──────────
# Annex II asks for the REAL update procedure. Until 2026-08-19 the swupdate
# plan specified uboot_a/uboot_b and boot_a — four partitions no unit has ever
# carried. Nothing was built from it, which is precisely why nothing caught it.
for PLAN in $PLANS; do
	# BOTH tables, not just the lunched one: a document records what we ship,
	# and we ship two boards. Checking only the selected board would let the
	# other table rot silently in the docs between builds.
	if [ ! -f "$PLAN" ]; then
		skip "$PLAN not present"
	else
		pfail=0
		grep -qF "$FROZEN_EMMC" "$PLAN" || {
			bad "$PLAN does not quote the frozen eMMC table — the document describes a layout we do not ship"
			pfail=1
		}
		grep -qF "$FROZEN_NAND" "$PLAN" || {
			bad "$PLAN does not quote the frozen SPI NAND table — the document describes a layout we do not ship"
			pfail=1
		}
		[ $pfail -eq 0 ] && ok "$PLAN quotes both frozen tables verbatim"
	fi
done

# ── 6. PACKED artifacts, when a build is present ───────────────────────────
# Deliberately NOT output/image/.env.txt. build.sh regenerates that file from
# the board config during its own startup (parse_partition_file), so when this
# gate runs as `./build.sh partitions` it has just been rewritten and agrees by
# construction — a check that cannot fail. Found 2026-08-19 by growing
# `userdata` and watching the .env.txt check pass while the packed image set
# still carried the old table.
#
# The evidence is the artifacts that get FLASHED: env.img holds the kernel's
# blkdevparts, and the S20linkmount inside rootfs.img holds the by-name links
# the unit will really use. Neither is touched by a build.sh startup.
if [ -f "$IMAGEDIR/env.img" ]; then
	want="${ENV_KEY}${FROZEN}"
	# env.img is a NUL-separated key=value blob, so split on NUL before
	# matching: a `[^ ]*` pattern runs straight through the terminator and
	# swallows the next variable, which made this compare unconditionally
	# unequal — a check that always fails is as useless as one that never does.
	got=$(tr '\0' '\n' < "$IMAGEDIR/env.img" | grep -aoE '(blkdevparts|mtdparts)=[^ ]*' | head -1)
	if [ "$got" = "$want" ]; then
		ok "packed env.img carries the frozen table"
	else
		bad "packed env.img does NOT carry the frozen table — this image set would partition differently"
		note "image:  ${got:-<no blkdevparts found>}"
		note "frozen: $want"
		note "the tree is right and the build is stale: rebuild before flashing or tagging"
	fi
else
	skip "packed env.img — no build present"
fi

# The reader has to match the rootfs FILESYSTEM, which is no longer always
# ext4: the 2026-09-01 re-cut moved both boards' rootfs to squashfs (it packs
# the tree to 33 M where ext4 needed 116 M, which is what makes a 64 M slot
# possible). debugfs reads ext4 and returns nothing at all on a squashfs image
# — so leaving it as the only reader would have turned this check into ten
# confident failures on a perfectly good image, which is how a gate gets
# disabled. rootfs-image-lib.sh probes the format and picks the tool; it is
# shared with the other gates rather than open-coded here, because the first
# version of this block WAS open-coded and used `unsquashfs -cat`, which the
# SDK's own 4.3 unsquashfs (ahead of the host's on build.sh's PATH) does not
# have. It passed when run from a shell and silently skipped under
# `./build.sh partitions`.
if [ ! -f "$IMAGEDIR/rootfs.img" ]; then
	skip "S20linkmount inside rootfs.img — no build present"
else
	reader=$(rootfs_reader "$IMAGEDIR/rootfs.img" || true)
	lm=""
	[ -n "$reader" ] && lm=$(rootfs_cat_file "$IMAGEDIR/rootfs.img" /etc/init.d/S20linkmount)

	if [ -z "$reader" ]; then
		if [ "$BUILT_BOARD" = nand ]; then
			# KNOWN GAP, not a passing check. The Max's rootfs.img is a UBI
			# volume; reading a file out of it needs a UBI/UBIFS extractor no
			# build host here has (ubireader is not installed, and the SDK
			# ships only mkfs/ubinize plus an inode-ownership scanner that
			# cannot resolve paths or contents). So on NAND the by-name links
			# the unit will really use are NOT verified by this gate.
			#
			# Called out rather than left as a bare skip because a silent skip
			# on an absence-style check is the failure mode this gate already
			# hit once with debugfs-on-squashfs: it reads as green.
			skip "S20linkmount inside rootfs.img — NOT VERIFIED on SPI NAND: no UBI reader on this host"
			note "the by-name symlinks inside the Max's rootfs are unchecked."
			note "Verify on the unit after flashing: ls -l /dev/block/by-name/"
			note "and confirm rootfs_a is p9 and rootfs_b is p10."
		else
			skip "S20linkmount inside rootfs.img — no reader for this image format (need unsquashfs or debugfs)"
		fi
	elif [ -z "$lm" ]; then
		skip "S20linkmount inside rootfs.img — could not read it with $reader"
	else
		lfail=0
		for i in "${!NAMES[@]}"; do
			printf '%s' "$lm" | grep -qF "ln -sf /dev/mmcblk0p$((i + 1)) ${NAMES[$i]}" || {
				bad "rootfs.img's S20linkmount: '${NAMES[$i]}' is not linked to p$((i + 1))"
				lfail=1
			}
		done
		[ $lfail -eq 0 ] && ok "S20linkmount inside rootfs.img: by-name links match the frozen table (read with $reader)"
	fi
fi

# ── 7. Occupancy — does what we pack still fit what we froze? ───────────────
# The freeze is only defensible while the images have headroom. rootfs is the
# one that grows; if it ever crosses its slot the layout cannot be widened on
# a fielded unit, so this is the number to watch, not a formality.
if [ -d "$IMAGEDIR" ]; then
	declare -A IMGMAP=(
		[env]=env.img [idblock]=idblock.img [uboot]=uboot.img [misc]=misc.img
		[boot]=boot.img [oem]=oem.img [userdata]=userdata.img
		[rootfs_a]=rootfs.img [rootfs_b]=rootfs.img
	)
	# Whole-partition raw images: env, uboot and misc ARE their partition, byte
	# for byte (misc.img is a 4 M zero-filled record area). 100% is correct for
	# these and means nothing — only "must not exceed" applies. The headroom
	# rule is for the images whose size tracks what we put in them.
	WHOLE=" env uboot misc "
	ofail=0; any=0
	for i in "${!NAMES[@]}"; do
		n=${NAMES[$i]}; f=${IMGMAP[$n]:-}
		[ -z "$f" ] && continue                      # boot_b ships empty in v1
		[ -f "$IMAGEDIR/$f" ] || continue
		any=1
		sz=$(stat -c %s "$IMAGEDIR/$f")
		cap=${SIZES[$i]}
		pct=$((sz * 100 / cap))
		if [ "$sz" -gt "$cap" ]; then
			bad "$f is $(human "$sz") — larger than '$n' ($(human "$cap"))"
			ofail=1
		elif [ "${WHOLE#*" $n "}" != "$WHOLE" ]; then
			note "$(printf '%-12s %-14s %3d%% of %s (whole-partition image)' "$n" "$f" "$pct" "$(human "$cap")")"
		elif [ "$pct" -ge 80 ]; then
			bad "$f fills ${pct}% of '$n' — a frozen partition with no headroom left"
			ofail=1
		else
			note "$(printf '%-12s %-14s %3d%% of %s' "$n" "$f" "$pct" "$(human "$cap")")"
		fi
	done
	if [ $any -eq 1 ] && [ $ofail -eq 0 ]; then
		ok "every packed image fits its frozen partition; the content images keep >20% headroom"
	elif [ $any -eq 0 ]; then
		skip "occupancy — no packed images in $IMAGEDIR"
	fi
else
	skip "occupancy — no $IMAGEDIR"
fi

echo
echo "$pass passed, $fail failed"
if [ $fail -ne 0 ]; then
	cat <<'EOF'

The layout is FROZEN (plan item 11, one-way door #1). A failure here means one
consumer of the table drifted from the others, and the ones this gate exists
for are silent until hardware: the SocToolKit map is read by the factory
flashing station, and sw-description.in names the partition an update installs
onto. Fix the consumer.

Changing the layout itself is a different act, and after the first customer
shipment it is a truck roll: edit FROZEN here, every consumer above, and record
the decision in media/joral/swupdate-implementation-plan.md.
EOF
	exit 1
fi
exit 0
