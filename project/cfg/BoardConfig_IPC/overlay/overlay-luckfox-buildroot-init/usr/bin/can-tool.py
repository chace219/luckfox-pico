#!/usr/bin/env python3
"""
can-tool.py  –  Configure a SocketCAN interface and test CAN frames WITHOUT iproute2 or can-utils.

Works with BusyBox images that lack 'ip link type can' or candump/cansend.
Uses Python's built-in netlink and AF_CAN socket support.

Usage:
  can-tool.py setup [--iface can0] [--bitrate 500000] [--loopback]
  can-tool.py up    [--iface can0]
  can-tool.py down  [--iface can0]
  can-tool.py send  <id> <hex-data> [--iface can0] [--count N] [--interval MS]
  can-tool.py recv  [--iface can0] [--timeout 5]
  can-tool.py diag  [--iface can0]   (quick hardware loopback self-test)
"""

import argparse
import fcntl
import os
import select
import socket
import struct
import sys
import time

# ---------------------------------------------------------------------------
# Netlink / RTM_NEWLINK constants
# ---------------------------------------------------------------------------
NETLINK_ROUTE   = 0
RTM_NEWLINK     = 16
NLM_F_REQUEST   = 0x0001
NLM_F_ACK       = 0x0004
NLMSG_ERROR     = 2
AF_UNSPEC       = 0

# IFLA attributes
IFLA_IFNAME     = 3
IFLA_LINKINFO   = 18
NLA_F_NESTED    = 0x8000

# IFLA_LINKINFO sub-attributes
IFLA_INFO_KIND  = 1
IFLA_INFO_DATA  = 2

# CAN IFLA_INFO_DATA sub-attributes (linux/can/netlink.h)
IFLA_CAN_BITTIMING  = 1
IFLA_CAN_CTRLMODE   = 5

# struct can_ctrlmode flags
CAN_CTRLMODE_LOOPBACK   = 0x01
CAN_CTRLMODE_LISTENONLY = 0x02
CAN_CTRLMODE_3_SAMPLES  = 0x04

# ioctl constants
SIOCGIFINDEX = 0x8933
SIOCSIFFLAGS = 0x8914
SIOCGIFFLAGS = 0x8913
IFF_UP       = 0x1

# AF_CAN / SocketCAN
AF_CAN          = 29
CAN_RAW         = 1
SOL_CAN_RAW     = 101
CAN_RAW_LOOPBACK   = 3
CAN_RAW_RECV_OWN_MSGS = 4
CAN_EFF_FLAG    = 0x80000000
CAN_RTR_FLAG    = 0x40000000
CAN_ERR_FLAG    = 0x20000000
CAN_SFF_MASK    = 0x000007FF
CAN_EFF_MASK    = 0x1FFFFFFF


# ---------------------------------------------------------------------------
# Netlink helpers
# ---------------------------------------------------------------------------

def _nla(attr_type, data, nested=False):
    """Pack a single netlink attribute (NLA)."""
    if nested:
        attr_type |= NLA_F_NESTED
    nla_len = 4 + len(data)
    pad = (-nla_len) & 3          # bytes needed to align to 4
    return struct.pack('HH', nla_len, attr_type) + data + b'\x00' * pad


def _ifindex(ifname):
    """Return the integer ifindex for *ifname*."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        ifreq = struct.pack('16si', ifname.encode(), 0)
        res = fcntl.ioctl(s, SIOCGIFINDEX, ifreq)
        return struct.unpack('16si', res)[1]


def _nl_send_and_ack(msg):
    """Send *msg* on a NETLINK_ROUTE socket; raise OSError on NLMSG_ERROR."""
    with socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_ROUTE) as nl:
        nl.bind((0, 0))
        nl.send(msg)
        resp = nl.recv(4096)
    rlen, rtype = struct.unpack('IH', resp[:6])
    if rtype == NLMSG_ERROR:
        err = struct.unpack('i', resp[16:20])[0]
        if err != 0:
            raise OSError(-err, os.strerror(-err))


# ---------------------------------------------------------------------------
# CAN interface configuration via netlink
# ---------------------------------------------------------------------------

def can_set_bitrate(ifname, bitrate, loopback=False):
    """
    Configure *bitrate* on *ifname* using RTM_NEWLINK.
    Equivalent to: ip link set <ifname> type can bitrate <bitrate>
    The interface must be DOWN before calling this.
    """
    ifindex = _ifindex(ifname)

    # struct can_bittiming (8 × u32): bitrate, sample_point, tq,
    # prop_seg, phase_seg1, phase_seg2, sjw, brp
    # Kernel's can_calc_bittiming() fills everything from bitrate + clock.
    bittiming = struct.pack('8I', bitrate, 0, 0, 0, 0, 0, 0, 0)
    info_data = _nla(IFLA_CAN_BITTIMING, bittiming)

    if loopback:
        # struct can_ctrlmode: mask(u32), flags(u32)
        ctrlmode = struct.pack('II',
                               CAN_CTRLMODE_LOOPBACK,
                               CAN_CTRLMODE_LOOPBACK)
        info_data += _nla(IFLA_CAN_CTRLMODE, ctrlmode)

    linkinfo_data = (
        _nla(IFLA_INFO_KIND, b'can\x00') +
        _nla(IFLA_INFO_DATA, info_data, nested=True)
    )
    linkinfo = _nla(IFLA_LINKINFO, linkinfo_data, nested=True)

    # ifinfomsg: family(u8), pad(u8), type(u16), index(i32), flags(u32), change(u32)
    ifinfomsg = struct.pack('BBHiII', AF_UNSPEC, 0, 0, ifindex, 0, 0)
    payload   = ifinfomsg + linkinfo

    nlhdr = struct.pack('IHHII',
                        16 + len(payload),  # nlmsg_len
                        RTM_NEWLINK,        # nlmsg_type
                        NLM_F_REQUEST | NLM_F_ACK,
                        1,                  # seq
                        0)                  # pid
    _nl_send_and_ack(nlhdr + payload)


def iface_up(ifname):
    """Bring network interface up (SIOCSIFFLAGS IFF_UP)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        ifreq = struct.pack('16sH14s', ifname.encode(), 0, b'\x00' * 14)
        res   = fcntl.ioctl(s, SIOCGIFFLAGS, ifreq)
        flags = struct.unpack('H', res[16:18])[0]
        flags |= IFF_UP
        ifreq = struct.pack('16sH14s', ifname.encode(), flags, b'\x00' * 14)
        fcntl.ioctl(s, SIOCSIFFLAGS, ifreq)


def iface_down(ifname):
    """Take network interface down."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        ifreq = struct.pack('16sH14s', ifname.encode(), 0, b'\x00' * 14)
        res   = fcntl.ioctl(s, SIOCGIFFLAGS, ifreq)
        flags = struct.unpack('H', res[16:18])[0]
        flags &= ~IFF_UP
        ifreq = struct.pack('16sH14s', ifname.encode(), flags, b'\x00' * 14)
        fcntl.ioctl(s, SIOCSIFFLAGS, ifreq)


def iface_is_up(ifname):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        ifreq = struct.pack('16sH14s', ifname.encode(), 0, b'\x00' * 14)
        res   = fcntl.ioctl(s, SIOCGIFFLAGS, ifreq)
        flags = struct.unpack('H', res[16:18])[0]
        return bool(flags & IFF_UP)


# ---------------------------------------------------------------------------
# SocketCAN frame helpers
# ---------------------------------------------------------------------------

def _open_can(ifname, recv_own=False):
    s = socket.socket(AF_CAN, socket.SOCK_RAW, CAN_RAW)
    if recv_own:
        s.setsockopt(SOL_CAN_RAW, CAN_RAW_RECV_OWN_MSGS, 1)
    s.bind((ifname,))
    return s


def _pack_frame(can_id, data):
    dlc = min(len(data), 8)
    return struct.pack('=IB3x8s', can_id, dlc, data[:dlc].ljust(8, b'\x00'))


def _unpack_frame(raw):
    can_id, dlc = struct.unpack('=IB', raw[:5])
    data = raw[8:8 + (dlc & 0x0F)]
    kind = 'ERR' if can_id & CAN_ERR_FLAG else \
           'EXT' if can_id & CAN_EFF_FLAG else 'STD'
    real_id = can_id & (CAN_EFF_MASK if kind == 'EXT' else CAN_SFF_MASK)
    return real_id, kind, dlc & 0x0F, data


def send_frame(ifname, can_id, data_bytes, count=1, interval_ms=100):
    with _open_can(ifname) as s:
        frame = _pack_frame(can_id, data_bytes)
        for i in range(count):
            s.send(frame)
            real_id, kind, dlc, _ = _unpack_frame(frame)
            print(f"TX [{i+1}/{count}]  {kind} id={real_id:#05x}  "
                  f"dlc={dlc}  data={data_bytes[:dlc].hex().upper()}")
            if i < count - 1:
                time.sleep(interval_ms / 1000.0)


def recv_frames(ifname, timeout=5.0):
    print(f"Listening on {ifname} for {timeout:.0f}s  (Ctrl-C to stop) ...")
    count = 0
    deadline = time.time() + timeout
    with _open_can(ifname) as s:
        try:
            while True:
                remaining = deadline - time.time()
                if remaining <= 0:
                    break
                r, _, _ = select.select([s], [], [], remaining)
                if r:
                    raw = s.recv(16)
                    can_id, kind, dlc, data = _unpack_frame(raw)
                    ts = time.strftime('%H:%M:%S')
                    print(f"  {ts}  RX  {kind} id={can_id:#05x}  "
                          f"dlc={dlc}  data={data.hex().upper()}")
                    count += 1
        except KeyboardInterrupt:
            pass
    print(f"Received {count} frame(s).")
    return count


# ---------------------------------------------------------------------------
# Self-test using hardware loopback mode
# ---------------------------------------------------------------------------

def run_diag(ifname, bitrate=500000):
    """
    Enable CAN hardware loopback, send a known frame, verify reception.
    The controller internal loopback echoes TX back to RX without touching the bus.
    """
    print(f"[diag] Bringing {ifname} down for configuration ...")
    try:
        iface_down(ifname)
    except OSError:
        pass

    print(f"[diag] Setting bitrate={bitrate} + loopback=ON ...")
    can_set_bitrate(ifname, bitrate, loopback=True)
    iface_up(ifname)
    print(f"[diag] Interface up.")

    MAGIC_ID   = 0x7FF
    MAGIC_DATA = bytes.fromhex('CAFEBABE01020304')

    print(f"[diag] Sending test frame id={MAGIC_ID:#05x} data={MAGIC_DATA.hex().upper()} ...")
    with _open_can(ifname, recv_own=True) as s:
        s.send(_pack_frame(MAGIC_ID, MAGIC_DATA))
        r, _, _ = select.select([s], [], [], 2.0)
        if not r:
            print("[diag] FAIL – no frame received within 2 s")
            print("       Possible causes: controller not powered, SPI wiring error,")
            print("       oscillator absent, or driver probe failed.")
            return False
        raw = s.recv(16)
        can_id, kind, dlc, data = _unpack_frame(raw)
        if can_id == MAGIC_ID and data == MAGIC_DATA[:dlc]:
            print(f"[diag] PASS – echo received: id={can_id:#05x} data={data.hex().upper()}")
        else:
            print(f"[diag] FAIL – unexpected echo: id={can_id:#05x} data={data.hex().upper()}")
            return False

    # Disable loopback and restore normal mode
    print("[diag] Disabling loopback, restoring normal bitrate ...")
    iface_down(ifname)
    can_set_bitrate(ifname, bitrate, loopback=False)
    iface_up(ifname)
    print(f"[diag] {ifname} ready for normal CAN operation at {bitrate} bit/s.")
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_setup(args):
    print(f"Bringing {args.iface} down ...")
    try:
        iface_down(args.iface)
    except OSError:
        pass
    print(f"Configuring bitrate={args.bitrate}"
          f"{' + loopback' if args.loopback else ''} ...")
    can_set_bitrate(args.iface, args.bitrate, loopback=args.loopback)
    print(f"Bringing {args.iface} up ...")
    iface_up(args.iface)
    print(f"Done.  {args.iface} is {'UP' if iface_is_up(args.iface) else 'DOWN'}.")


def cmd_up(args):
    iface_up(args.iface)
    print(f"{args.iface} is now UP.")


def cmd_down(args):
    iface_down(args.iface)
    print(f"{args.iface} is now DOWN.")


def cmd_send(args):
    try:
        can_id   = int(args.id, 16)
        raw_data = bytes.fromhex(args.data)
    except ValueError as exc:
        sys.exit(f"Error: {exc}")
    send_frame(args.iface, can_id, raw_data,
               count=args.count, interval_ms=args.interval)


def cmd_recv(args):
    recv_frames(args.iface, timeout=args.timeout)


def cmd_diag(args):
    ok = run_diag(args.iface, bitrate=args.bitrate)
    sys.exit(0 if ok else 1)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--iface', default='can0', help='CAN interface (default: can0)')
    sub = p.add_subparsers(dest='cmd', required=True)

    # setup
    s_setup = sub.add_parser('setup', help='Configure bitrate and bring interface up')
    s_setup.add_argument('--bitrate', type=int, default=500000)
    s_setup.add_argument('--loopback', action='store_true',
                         help='Enable controller internal loopback (test only)')
    s_setup.set_defaults(func=cmd_setup)

    # up / down
    s_up = sub.add_parser('up', help='Bring interface up (bitrate must already be set)')
    s_up.set_defaults(func=cmd_up)

    s_down = sub.add_parser('down', help='Take interface down')
    s_down.set_defaults(func=cmd_down)

    # send
    s_send = sub.add_parser('send', help='Send a CAN frame')
    s_send.add_argument('id',   help='CAN ID in hex, e.g. 123')
    s_send.add_argument('data', help='Payload in hex, e.g. DEADBEEF (max 8 bytes)')
    s_send.add_argument('--count',    type=int, default=1,   help='Number of frames')
    s_send.add_argument('--interval', type=int, default=100, help='Interval ms between frames')
    s_send.set_defaults(func=cmd_send)

    # recv
    s_recv = sub.add_parser('recv', help='Dump received CAN frames')
    s_recv.add_argument('--timeout', type=float, default=10.0, help='Seconds to listen')
    s_recv.set_defaults(func=cmd_recv)

    # diag
    s_diag = sub.add_parser('diag', help='Hardware loopback self-test (checks the controller path)')
    s_diag.add_argument('--bitrate', type=int, default=500000)
    s_diag.set_defaults(func=cmd_diag)

    args = p.parse_args()
    try:
        args.func(args)
    except OSError as exc:
        sys.exit(f"Error: {exc}")
    except PermissionError:
        sys.exit("Error: permission denied – run as root.")


if __name__ == '__main__':
    main()
