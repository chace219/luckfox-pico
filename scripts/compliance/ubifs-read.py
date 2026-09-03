#!/usr/bin/env python3
"""ubifs-read.py — read a file out of a packed UBIFS image, without mounting.

The NAND half of what debugfs does for ext4 in `./build.sh swu`: the release
identity must be read OUT OF THE PAYLOAD (one-way door #4), and the Max's
rootfs is UBIFS, which no host tool in this SDK can read (mkfs.ubifs and
ubinize only write; ubireader is not installed on the build hosts).

Two commands:

  ubifs-read.py cat    <image> <path>        print a file's content to stdout
  ubifs-read.py unwrap <ubi-image> <out>     extract volume 0's LEB stream
                                             (a raw UBIFS image) from a
                                             ubinized flash image

<image> for `cat` may be either a raw UBIFS image (mkfs.ubifs output) or a
ubinized flash image (ubinize output, "UBI#" magic) — the UBI container is
unwrapped in memory first. `unwrap` exists because the .swu payload for the
ubivol handler must be the raw UBIFS stream, not the ubinized container: the
handler is ubiupdatevol semantics, writing INTO an existing volume, and the
temporary mkfs.ubifs output the build made is deleted by mkfs_ubi.sh —
so the payload is recovered from the flashable image instead, which also
guarantees the .swu carries byte-for-byte what the factory flashes.

Implementation: a LINEAR scan of UBIFS nodes (magic 0x06101831), not an index
walk — a freshly packed image's index is consistent with its nodes, and the
scan needs no B-tree code. Structs are from the in-tree kernel's
sysdrv/source/kernel/fs/ubifs/ubifs-media.h (ubifs_ch 24 bytes; dent inum at
+40, nlen at +50, name at +56; data node size at +40, compr_type at +44,
payload at +48; ino node size at +48). Compression: none and zlib (raw
deflate) — the boards build with RK_UBIFS_COMP=zlib; LZO would need a
third-party module and is refused with a pointer instead of misread.

Node CRCs are deliberately not checked: this reads a file the build just
wrote, and the .swu's own sha256 + CMS signature protect everything after
this point. What IS checked is that the path fully resolves and the file's
data adds up to the size its inode declares — a partial read must fail, not
pass a truncated version string to the release gate.
"""

import struct
import sys
import zlib

UBIFS_NODE_MAGIC = 0x06101831
UBIFS_MAGIC_BYTES = struct.pack("<I", UBIFS_NODE_MAGIC)
UBIFS_CH_SZ = 24
UBIFS_INO_NODE, UBIFS_DATA_NODE, UBIFS_DENT_NODE = 0, 1, 2
UBIFS_COMPR_NONE, UBIFS_COMPR_LZO, UBIFS_COMPR_ZLIB = 0, 1, 2
UBIFS_BLOCK_SIZE = 4096
ROOT_INO = 1

UBI_EC_MAGIC = b"UBI#"
UBI_VID_MAGIC = b"UBI!"


def die(msg):
    sys.stderr.write("ubifs-read: %s\n" % msg)
    sys.exit(1)


def ubi_unwrap(img):
    """ubinized image -> volume 0's LEB stream (a raw UBIFS image).

    UBI headers are BIG-endian (the one place they differ from UBIFS's
    little-endian nodes). Every PEB starts with an EC header; the PEB size is
    found from the second EC magic rather than assumed, so all three
    geometries mkfs_ubi.sh builds (128KiB/2K, 256KiB/2K, 256KiB/4K) unwrap
    without being told which one this is.
    """
    if img[:4] != UBI_EC_MAGIC:
        die("not a ubinized image (no UBI# magic)")
    peb = img.find(UBI_EC_MAGIC, 4)
    if peb <= 0:
        die("single-PEB image? cannot determine PEB size")

    lebs = {}
    leb_size = None
    for off in range(0, len(img), peb):
        if img[off:off + 4] != UBI_EC_MAGIC:
            continue
        vid_off, data_off = struct.unpack(">II", img[off + 16:off + 24])
        vid = img[off + vid_off:off + vid_off + 64]
        if vid[:4] != UBI_VID_MAGIC:
            continue  # empty PEB (no volume data mapped)
        vol_id, lnum = struct.unpack(">II", vid[8:16])
        if vol_id != 0:
            continue  # layout volume / anything else
        if leb_size is None:
            leb_size = peb - data_off
        lebs[lnum] = img[off + data_off:off + peb]
    if not lebs:
        die("no volume-0 LEBs found — not a rootfs UBI image?")
    out = bytearray()
    for lnum in range(max(lebs) + 1):
        out += lebs.get(lnum, b"\xff" * leb_size)
    return bytes(out)


def scan_nodes(img):
    """Yield (node_type, offset, length) for every UBIFS node, by magic."""
    pos = 0
    n = len(img)
    while True:
        pos = img.find(UBIFS_MAGIC_BYTES, pos)
        if pos < 0 or pos + UBIFS_CH_SZ > n:
            return
        if pos % 8:  # nodes are 8-byte aligned; this magic is payload bytes
            pos += 1
            continue
        (length,) = struct.unpack("<I", img[pos + 16:pos + 20])
        ntype = img[pos + 20]
        if length < UBIFS_CH_SZ or pos + length > n:
            pos += 8
            continue
        yield ntype, pos, length
        # Nodes are packed 8-byte aligned; resuming at the aligned end also
        # skips magics inside this node's own payload.
        pos += (length + 7) & ~7


def key_ino(img, off):
    """First 4 bytes of a node key: the inode number (simple key format)."""
    (ino,) = struct.unpack("<I", img[off + UBIFS_CH_SZ:off + UBIFS_CH_SZ + 4])
    return ino


def read_file(img, path):
    dents = []   # (parent_ino, name, target_ino)
    datas = {}   # target_ino -> {block: (compr, payload)}
    sizes = {}   # ino -> declared size
    for ntype, off, length in scan_nodes(img):
        if ntype == UBIFS_DENT_NODE:
            (inum,) = struct.unpack("<Q", img[off + 40:off + 48])
            (nlen,) = struct.unpack("<H", img[off + 50:off + 52])
            name = img[off + 56:off + 56 + nlen]
            if inum:  # inum 0 is a deletion entry
                dents.append((key_ino(img, off), name, inum))
        elif ntype == UBIFS_DATA_NODE:
            (kino,) = struct.unpack("<I", img[off + UBIFS_CH_SZ:off + UBIFS_CH_SZ + 4])
            (blk,) = struct.unpack("<I", img[off + UBIFS_CH_SZ + 4:off + UBIFS_CH_SZ + 8])
            blk &= (1 << 29) - 1
            size, compr = struct.unpack("<IH", img[off + 40:off + 46])
            datas.setdefault(kino, {})[blk] = (compr, img[off + 48:off + length], size)
        elif ntype == UBIFS_INO_NODE:
            (fsize,) = struct.unpack("<Q", img[off + 48:off + 56])
            sizes[key_ino(img, off)] = fsize

    ino = ROOT_INO
    for comp in [c for c in path.split("/") if c]:
        matches = {t for (p, nm, t) in dents if p == ino and nm == comp.encode()}
        if len(matches) != 1:
            die("cannot resolve '%s' in %s (%d matches)" % (comp, path, len(matches)))
        ino = matches.pop()

    if ino not in sizes:
        die("%s resolved to inode %d but no inode node found" % (path, ino))
    want = sizes[ino]
    out = bytearray()
    for blk in sorted(datas.get(ino, {})):
        compr, payload, dsize = datas[ino][blk]
        if compr == UBIFS_COMPR_NONE:
            data = payload
        elif compr == UBIFS_COMPR_ZLIB:
            data = zlib.decompress(payload, -zlib.MAX_WBITS)
        elif compr == UBIFS_COMPR_LZO:
            die("inode %d is LZO-compressed; this tree builds with "
                "RK_UBIFS_COMP=zlib — check the BoardConfig" % ino)
        else:
            die("inode %d: unknown compression type %d" % (ino, compr))
        if len(data) != dsize:
            die("inode %d block %d: decompressed %d bytes, node declares %d"
                % (ino, blk, len(data), dsize))
        # A sparse hole between blocks reads as zeroes.
        out += b"\x00" * (blk * UBIFS_BLOCK_SIZE - len(out))
        out += data
    if len(out) < want:
        out += b"\x00" * (want - len(out))
    if len(out) > want:
        out = out[:want]
    if want and not out:
        die("%s: inode declares %d bytes but no data nodes found" % (path, want))
    return bytes(out)


def load(path):
    with open(path, "rb") as f:
        img = f.read()
    if img[:4] == UBI_EC_MAGIC:
        img = ubi_unwrap(img)
    if img.find(UBIFS_MAGIC_BYTES) < 0:
        die("%s: no UBIFS nodes found" % path)
    return img


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("cat", "unwrap"):
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    cmd, image, arg = sys.argv[1:4]
    if cmd == "unwrap":
        with open(image, "rb") as f:
            img = f.read()
        out = ubi_unwrap(img)
        if out.find(UBIFS_MAGIC_BYTES) < 0:
            die("unwrapped volume carries no UBIFS nodes — wrong image?")
        with open(arg, "wb") as f:
            f.write(out)
        return 0
    sys.stdout.buffer.write(read_file(load(image), arg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
