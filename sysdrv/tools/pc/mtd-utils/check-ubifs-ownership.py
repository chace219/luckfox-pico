#!/usr/bin/env python3
"""Read inode ownership back out of a packed UBIFS image.

CRA Annex I #4 / #5; compliance plan item 13.

Why this exists rather than a `stat` on the staging tree: the staging tree is
owned by the build user, and what matters is the uid the PACKER RECORDED. Those
two disagreed for years here, silently — mkfs_ubi.sh wrapped a `chown -h -R
0:0` and the packer in one `fakeroot` session, but mkfs.ubifs is statically
linked and never consults LD_PRELOAD, so the chown applied to a view the packer
could not see. A build that "handles ownership" and an image that ships
1000:1000 looked identical from outside.

It parses the image directly rather than mounting it: mounting UBIFS needs
nandsim plus root, which a build host does not have and CI will not get.

UBIFS on-media format (fs/ubifs/ubifs-media.h). Common header, 24 bytes:
    0  magic  __le32 = 0x06101831
    4  crc    __le32
    8  sqnum  __le64
   16  len    __le32
   20  node_type __u8      (0 = UBIFS_INO_NODE)
   21  group_type __u8
   22  padding[2]
Inode node continues:
   24  key[16]             (first __le32 of an inode key is the inum)
   40  creat_sqnum, size, atime/ctime/mtime sec (__le64 each)
   80  atime_nsec, ctime_nsec, mtime_nsec, nlink (__le32 each)
   96  uid  __le32
  100  gid  __le32
  104  mode __le32

Scanning for the magic can in principle strike a false positive inside file
data. It is bounded on purpose: a false hit is reported as a node whose length
or mode is nonsensical, and the caller sees more inodes than the tree has, which
is loud. Under-reporting is the dangerous direction and cannot happen — every
real inode node carries the magic.

Usage: check-ubifs-ownership.py <image.ubifs> [--quiet]
Exit 0 if every inode is uid 0 / gid 0, 1 otherwise, 2 on a usage error.
"""
import struct
import sys

MAGIC = b"\x31\x18\x10\x06"
UBIFS_INO_NODE = 0


def inodes(path):
    with open(path, "rb") as fh:
        data = fh.read()
    found = {}
    pos = 0
    while True:
        pos = data.find(MAGIC, pos)
        if pos < 0:
            break
        if pos + 108 <= len(data) and data[pos + 20] == UBIFS_INO_NODE:
            inum = struct.unpack_from("<I", data, pos + 24)[0]
            uid, gid, mode = struct.unpack_from("<III", data, pos + 96)
            # Keep the highest-sqnum record for an inum: an image can carry more
            # than one node per inode, and the newest is the one that counts.
            sqnum = struct.unpack_from("<Q", data, pos + 8)[0]
            prev = found.get(inum)
            if prev is None or sqnum > prev[0]:
                found[inum] = (sqnum, uid, gid, mode)
        pos += 4
    return {inum: rec[1:] for inum, rec in found.items()}


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        return 2
    path = argv[1]
    quiet = "--quiet" in argv[2:]

    try:
        found = inodes(path)
    except OSError as exc:
        print("check-ubifs-ownership: %s" % exc, file=sys.stderr)
        return 2

    if not found:
        print("check-ubifs-ownership: no inode nodes in %s — not a UBIFS image?" % path,
              file=sys.stderr)
        return 2

    bad = {i: v for i, v in found.items() if v[0] != 0 or v[1] != 0}
    if not quiet:
        print("check-ubifs-ownership: %d inodes, %d not root-owned" % (len(found), len(bad)))
    for inum in sorted(bad):
        uid, gid, mode = bad[inum]
        # inode 1 is the filesystem root. Saying so matters: it is the one
        # --squash-uids does not fix, and "create and unlink at /" is a
        # different sentence from "a file is owned by the build user".
        where = " (the filesystem root)" if inum == 1 else ""
        print("  inode %d%s: uid %d gid %d mode %o" % (inum, where, uid, gid, mode))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
