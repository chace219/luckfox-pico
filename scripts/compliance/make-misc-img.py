#!/usr/bin/env python3
"""Generate the misc.img that carries AVB A/B slot metadata.

Why this exists: the SDK ships no such file. BoardConfig set
RK_MISC=wipe_all-misc.img, which does not exist in the tree at all -- and
build.sh only copies RK_MISC when RK_ENABLE_RECOVERY=y, which neither Joral
board sets. So `misc` was flashed as erased NAND (all 0xff) or not at all,
and spl_ab.c read uninitialised metadata on every boot. It failed its CRC
check silently and fell back to its default path, which is why A/B appeared
to "work" while only ever booting slot A.

The two files the SDK does ship are not A/B metadata:
  blank-misc.img     48 KiB, a bootloader_message struct
  recovery-misc.img  48 KiB, an Android recovery command (--wipe_all)
Neither carries the \\0AB0 magic that spl_ab.c looks for.

Layout, from include/android_avb/avb_ab_flow.h (AvbABData, 32 bytes packed):
     0  magic[4]        = "\\0AB0"
     4  version_major   = 1
     5  version_minor   = 0
     6  reserved1[2]
     8  slots[0]        priority, tries_remaining, successful_boot, reserved
    12  slots[1]        same
    16  last_boot
    17  reserved2[11]
    28  crc32           big-endian, zlib crc32 over the preceding 28 bytes

Written at AB_METADATA_OFFSET = 4 sectors = byte 2048 (include/spl_ab.h),
which is where spl_ab.c reads and writes it via blk_dread/blk_dwrite.

Factory state (chosen deliberately, 2026-09-02):
  slot A  priority 15, tries 7, successful_boot = 1
  slot B  priority 0,  tries 0, successful_boot = 0   -- empty, unbootable
A is trusted rather than on trial, which is right for a factory image: the
unit boots A and does not burn retry counts before it has ever been updated.
Slot B stays priority 0 so nothing tries to boot an empty partition; the
first SWUpdate install is what populates and raises it.
"""
import struct, sys, zlib

AVB_AB_MAGIC = b"\0AB0"
AB_METADATA_OFFSET = 2048          # 4 sectors * 512
MISC_SIZE = 4 * 1024 * 1024        # the frozen 'misc' partition, both boards


def ab_data(a_pri, a_tries, a_ok, b_pri, b_tries, b_ok):
    d = bytearray(32)
    d[0:4] = AVB_AB_MAGIC
    d[4] = 1                        # version_major
    d[5] = 0                        # version_minor
    # d[6:8] reserved1
    d[8], d[9], d[10], d[11] = a_pri, a_tries, a_ok, 0
    d[12], d[13], d[14], d[15] = b_pri, b_tries, b_ok, 0
    d[16] = 0                       # last_boot = slot A
    # d[17:28] reserved2
    crc = zlib.crc32(bytes(d[0:28])) & 0xFFFFFFFF
    struct.pack_into(">I", d, 28, crc)          # big-endian, per htobe32
    return bytes(d)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "misc.img"
    blob = ab_data(a_pri=15, a_tries=7, a_ok=1,
                   b_pri=0,  b_tries=0, b_ok=0)
    img = bytearray(b"\0" * MISC_SIZE)
    img[AB_METADATA_OFFSET:AB_METADATA_OFFSET + len(blob)] = blob
    with open(out, "wb") as f:
        f.write(img)
    print(f"wrote {out}: {MISC_SIZE} bytes, AvbABData at {AB_METADATA_OFFSET}")
    print(f"  magic   {blob[0:4]!r}  version {blob[4]}.{blob[5]}")
    print(f"  slot A  priority={blob[8]} tries={blob[9]} successful={blob[10]}")
    print(f"  slot B  priority={blob[12]} tries={blob[13]} successful={blob[14]}")
    print(f"  crc32   0x{struct.unpack('>I', blob[28:32])[0]:08X} (big-endian)")


if __name__ == "__main__":
    main()
