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

# ── THE FROZEN TABLE ────────────────────────────────────────────────────────
# Do not edit this line to make the gate pass. Editing it IS the layout change.
FROZEN="32K(env),512K@32K(idblock),256K(uboot),4M(misc),32M(boot),32M(boot_b),512M(oem),512M(userdata),1536M(rootfs_a),1536M(rootfs_b)"

# Nominal 8 GB eMMC on the Pico Ultra. 7.2 GiB is a conservative usable floor
# for a "8 GB" part; the real capacity has not been measured on a unit from
# this build host, so this bounds the table rather than sizing it.
EMMC_USABLE_FLOOR=$((7200 * 1024 * 1024))

BOARDCFG=project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk
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

parse_table "$FROZEN"
[ ${#NAMES[@]} -gt 0 ] || { echo "the frozen table did not parse — this is a bug in this script"; exit 2; }

echo "== Frozen A/B partition layout =="
for i in "${!NAMES[@]}"; do
	note "$(printf 'p%-2d %-10s @ 0x%08X  %s' $((i + 1)) "${NAMES[$i]}" "${OFFSETS[$i]}" "$(human "${SIZES[$i]}")")"
done

# ── 1. The board config is the frozen table, exactly ────────────────────────
if [ ! -f "$BOARDCFG" ]; then
	bad "$BOARDCFG missing — the A/B board profile is the thing being frozen"
else
	actual=$(sed -n 's/^export RK_PARTITION_CMD_IN_ENV="\(.*\)"$/\1/p' "$BOARDCFG")
	if [ "$actual" = "$FROZEN" ]; then
		ok "board profile matches the frozen table"
	else
		bad "board profile does NOT match the frozen table"
		echo "         frozen: $FROZEN"
		echo "         config: ${actual:-<not found>}"
	fi
fi

# ── 2. Invariants the table itself must satisfy ─────────────────────────────
# These do not depend on the constant above being right, so they still bite if
# somebody edits the constant instead of thinking.

# `misc` must not carry a slot suffix: spl_ab_append_part_slot() special-cases
# the literal name, and a `misc_a` would be invisible to the bootloader.
if [ "$(count_of misc)" = "1" ]; then
	ok "'misc' present exactly once and unsuffixed (spl_ab_append_part_slot special-cases the name)"
else
	bad "'misc' must appear exactly once, unsuffixed"
fi

# Slots must be the same size — the updater writes one image to either one.
sa=$(size_of rootfs_a) || sa=""
sb=$(size_of rootfs_b) || sb=""
if [ -n "$sa" ] && [ "$sa" = "$sb" ]; then
	ok "rootfs_a and rootfs_b are the same size ($(human "$sa") each)"
else
	bad "rootfs_a/rootfs_b missing or unequal (a=${sa:-none} b=${sb:-none})"
fi

# oem and userdata must survive a slot switch, so they must be single-copy.
for p in oem userdata; do
	if [ "$(count_of "$p")" = "1" ] && ! idx_of "${p}_a" >/dev/null 2>&1; then
		ok "'$p' is single-copy (must survive a slot switch — Phase 0)"
	else
		bad "'$p' must be single-copy, with no slot suffix"
	fi
done

# boot_b is reserved and empty in v1; it exists so kernel-slot A/B can ship
# later THROUGH the updater instead of needing a repartition.
if idx_of boot_b >/dev/null; then
	ok "'boot_b' reserved (kernel-slot A/B stays shippable post-freeze)"
else
	bad "'boot_b' missing — kernel-slot A/B would need a repartition, i.e. a truck roll"
fi

# Contiguous, starting at 0, no gaps or overlaps.
gapfail=0; cursor=0
for i in "${!NAMES[@]}"; do
	if [ "${OFFSETS[$i]}" -ne "$cursor" ]; then
		bad "partition gap/overlap before '${NAMES[$i]}': expected offset $cursor, table says ${OFFSETS[$i]}"
		gapfail=1
	fi
	cursor=$((OFFSETS[i] + SIZES[i]))
done
[ $gapfail -eq 0 ] && ok "table is contiguous from offset 0 (no gaps, no overlaps)"

TOTAL=$cursor
if [ "$TOTAL" -le "$EMMC_USABLE_FLOOR" ]; then
	ok "table totals $(human "$TOTAL") — fits the conservative $(human "$EMMC_USABLE_FLOOR") usable floor for the 8 GB eMMC"
	note "$(human $((EMMC_USABLE_FLOOR - TOTAL))) left unallocated at the tail. That tail is the only"
	note "post-freeze escape hatch: a partition APPENDED there shifts no existing"
	note "index, so it is the one layout change a fielded unit could survive."
else
	bad "table totals $(human "$TOTAL"), past the $(human "$EMMC_USABLE_FLOOR") usable floor"
fi

# ── 3. SocToolKit flashing maps — hand-maintained byte offsets ──────────────
# The factory station writes by ABSOLUTE OFFSET. A stale entry here does not
# fail a build; it writes an image over the wrong partition on a real unit.
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
	if [ ! -f "$PLAN" ]; then
		skip "$PLAN not present"
	elif grep -qF "$FROZEN" "$PLAN"; then
		ok "$PLAN quotes the frozen table verbatim"
	else
		bad "$PLAN does not quote the frozen table — the document describes a layout we do not ship"
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
	want="blkdevparts=mmcblk0:$FROZEN"
	# env.img is a NUL-separated key=value blob, so split on NUL before
	# matching: a `[^ ]*` pattern runs straight through the terminator and
	# swallows the next variable, which made this compare unconditionally
	# unequal — a check that always fails is as useless as one that never does.
	got=$(tr '\0' '\n' < "$IMAGEDIR/env.img" | grep -ao 'blkdevparts=[^ ]*' | head -1)
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

if [ -f "$IMAGEDIR/rootfs.img" ] && command -v debugfs >/dev/null 2>&1; then
	lm=$(debugfs -R "cat /etc/init.d/S20linkmount" "$IMAGEDIR/rootfs.img" 2>/dev/null)
	if [ -z "$lm" ]; then
		skip "S20linkmount inside rootfs.img — could not read it"
	else
		lfail=0
		for i in "${!NAMES[@]}"; do
			printf '%s' "$lm" | grep -qF "ln -sf /dev/mmcblk0p$((i + 1)) ${NAMES[$i]}" || {
				bad "rootfs.img's S20linkmount: '${NAMES[$i]}' is not linked to p$((i + 1))"
				lfail=1
			}
		done
		[ $lfail -eq 0 ] && ok "S20linkmount inside rootfs.img: by-name links match the frozen table"
	fi
else
	skip "S20linkmount inside rootfs.img — no build present, or debugfs unavailable"
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
