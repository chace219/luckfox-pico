#!/usr/bin/env python3
"""ubifs-mode.py — read the MODE and ownership of a path in a packed UBIFS image.

The companion to ubifs-read.py, which reads a file's CONTENT. This reads its
inode metadata, because the defect that motivated it is invisible in content:
POSIX chown(2) clears the set-user-ID bit, so the packer's `chown -h -R 0:0`
stripped the 4755 off the console privop dispatchers and they reached the image
as plain 755 (bench, Max, 2026-09-10 — every privileged console verb failed,
presenting as a .swu upload dying mid-body with "network error").

A mechanism assertion cannot catch that. This reads the packed image, so the
gate checks the artifact that actually ships.

  ubifs-mode.py <image> <path>...

<image> may be a raw UBIFS image or a ubinized flash image (UBI# magic);
the container is unwrapped in memory by ubifs-read.py's ubi_unwrap.

Offsets are from the in-tree kernel's sysdrv/source/kernel/fs/ubifs/ubifs-media.h
(struct ubifs_ino_node): ch(24) + key(16) + creat_sqnum(8) + size(8) +
3x __le64 *_sec + 3x __le32 *_nsec + nlink(4) puts uid at +96, gid at +100,
mode at +104. Confirmed against known-mode control files rather than assumed:
/etc/shadow reads 0600, /etc/passwd 0644, /usr/sbin 040755 (S_IFDIR), all uid 0.
Pass a control file alongside whatever you are checking and the offsets prove
themselves on every run.
"""
import struct, sys, os
import importlib.util
spec = importlib.util.spec_from_file_location(
    "ubifs_read", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ubifs-read.py"))
ur = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ur)

UID_OFF, GID_OFF, MODE_OFF = 96, 100, 104

def resolve(img, path):
    dents = []
    inos = {}
    for ntype, off, length in ur.scan_nodes(img):
        if ntype == ur.UBIFS_DENT_NODE:
            (inum,) = struct.unpack("<Q", img[off + 40:off + 48])
            (nlen,) = struct.unpack("<H", img[off + 50:off + 52])
            name = img[off + 56:off + 56 + nlen]
            if inum:
                dents.append((ur.key_ino(img, off), name, inum))
        elif ntype == ur.UBIFS_INO_NODE:
            uid, gid = struct.unpack("<II", img[off + UID_OFF:off + UID_OFF + 8])
            (mode,) = struct.unpack("<I", img[off + MODE_OFF:off + MODE_OFF + 4])
            inos[ur.key_ino(img, off)] = (mode, uid, gid)

    ino = ur.ROOT_INO
    for comp in [c for c in path.split("/") if c]:
        nxt = None
        for p, name, target in dents:
            if p == ino and name == comp.encode():
                nxt = target
        if nxt is None:
            return None
        ino = nxt
    return inos.get(ino)

img = ur.load(sys.argv[1])
for path in sys.argv[2:]:
    r = resolve(img, path)
    if r is None:
        print("%-40s MISSING" % path)
    else:
        mode, uid, gid = r
        print("%-40s mode=%06o  perm=%04o  uid=%d gid=%d  %s"
              % (path, mode, mode & 0o7777, uid, gid,
                 "SETUID" if mode & 0o4000 else "-"))
