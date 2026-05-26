#!/usr/bin/env python3

import argparse
import os
import sys

try:
    import spidev
except ImportError as exc:
    print("spidev module not available: {}".format(exc), file=sys.stderr)
    sys.exit(2)


OA_TC6_REG_STDCAP        = 0x0002
OA_TC6_REG_CONFIG0       = 0x0004
OA_TC6_REG_STATUS0       = 0x0008
OA_TC6_REG_BUFFER_STATUS = 0x000B

# LAN865x internal PHY standard registers (accessed via OA-TC6 direct PHY access)
# These live in the OA-TC6 register map at base 0xFF00.
# reg 0 → 0xFF00 (BMCR), reg 1 → 0xFF01 (BMSR),
# reg 2 → 0xFF02 (PHYSID1), reg 3 → 0xFF03 (PHYSID2)
OA_TC6_PHY_STD_REG_BASE  = 0xFF00

# Expected PHY ID for LAN865x Rev B0/B1 (PHY_ID_LAN865X_REVB in microchip_t1s.c)
PHY_ID_LAN865X_REVB      = 0x0007C1B3


def tc6_parity(word: int) -> int:
    parity = word
    parity ^= parity >> 1
    parity ^= parity >> 2
    parity = (parity & 0x11111111) * 0x11111111
    return 0 if ((parity >> 28) & 1) else 1


def make_ctrl_read(addr: int, length: int = 1) -> bytes:
    header = ((addr & 0xFFFF) << 8) | (((length - 1) & 0x7F) << 1)
    header |= tc6_parity(header)
    return header.to_bytes(4, "big") + (b"\x00" * (length * 4 + 4))


def parse_device_path(device_path: str):
    base = os.path.basename(device_path)
    if not base.startswith("spidev") or "." not in base:
        raise ValueError("unexpected spidev path: {}".format(device_path))
    bus_str, cs_str = base[len("spidev"):].split(".", 1)
    return int(bus_str), int(cs_str)


def read_reg(spi_dev, reg: int):
    tx = make_ctrl_read(reg)
    rx = bytes(spi_dev.xfer2(list(tx)))
    echoed = int.from_bytes(rx[4:8], "big")
    sent = int.from_bytes(tx[0:4], "big")
    value = int.from_bytes(rx[8:12], "big")
    return sent, echoed, value, rx


def main():
    parser = argparse.ArgumentParser(description="Read a few OA-TC6 registers over spidev")
    parser.add_argument("--device", default="/dev/spidev0.1", help="spidev node to use")
    parser.add_argument("--speed", type=int, default=500000, help="SPI clock in Hz")
    args = parser.parse_args()

    if not os.path.exists(args.device):
        print("{} does not exist".format(args.device), file=sys.stderr)
        print("Expose the LAN865x on a spidev node first, then retry.", file=sys.stderr)
        return 2

    bus, chip_select = parse_device_path(args.device)
    spi_dev = spidev.SpiDev()
    spi_dev.open(bus, chip_select)
    spi_dev.max_speed_hz = args.speed
    spi_dev.mode = 0
    spi_dev.bits_per_word = 8

    print("LAN865x raw SPI probe via {} @ {} Hz".format(args.device, args.speed))
    print()

    ok = True
    stdcap_val = None

    print("--- OA-TC6 control registers ---")
    for reg, name in (
        (OA_TC6_REG_STDCAP,        "STDCAP"),
        (OA_TC6_REG_CONFIG0,       "CONFIG0"),
        (OA_TC6_REG_STATUS0,       "STATUS0"),
        (OA_TC6_REG_BUFFER_STATUS, "BUFFER_STATUS"),
    ):
        sent, echoed, value, raw = read_reg(spi_dev, reg)
        echo_ok = sent == echoed
        ok = ok and echo_ok
        print("{:<16} (0x{:04x}) = 0x{:08x}  echo_ok={}".format(
            name, reg, value, echo_ok
        ))
        if reg == OA_TC6_REG_STDCAP:
            stdcap_val = value

    dpra_supported = bool(stdcap_val is not None and (stdcap_val & (1 << 8)))
    print()
    print("STDCAP.DPRA (direct PHY reg access): {}".format(
        "SUPPORTED" if dpra_supported else "NOT SUPPORTED – oa_tc6_phy_init will fail"
    ))

    print()
    print("--- Internal PHY standard registers (via direct access, OA-TC6 base 0xFF00) ---")
    if dpra_supported:
        physid1 = physid2 = None
        phy_ok = True
        for reg_offset, label in (
            (0, "BMCR   (reg 0)"),
            (1, "BMSR   (reg 1)"),
            (2, "PHYSID1 (reg 2)"),
            (3, "PHYSID2 (reg 3)"),
        ):
            oa_reg = OA_TC6_PHY_STD_REG_BASE + reg_offset
            sent, echoed, value, raw = read_reg(spi_dev, oa_reg)
            echo_ok = sent == echoed
            ok = ok and echo_ok
            phy_ok = phy_ok and echo_ok
            print("{:<16} (OA-reg 0x{:04x}) = 0x{:04x}  echo_ok={}".format(
                label, oa_reg, value & 0xFFFF, echo_ok
            ))
            if reg_offset == 2:
                physid1 = value & 0xFFFF
            elif reg_offset == 3:
                physid2 = value & 0xFFFF

        if phy_ok and physid1 is not None and physid2 is not None:
            full_id = (physid1 << 16) | physid2
            print()
            print("Combined PHY ID : 0x{:08x}".format(full_id))
            print("Expected RevB   : 0x{:08x}  (PHY_ID_LAN865X_REVB in microchip_t1s.c)".format(
                PHY_ID_LAN865X_REVB))
            if full_id == PHY_ID_LAN865X_REVB:
                print("PHY ID verdict  : EXACT MATCH – microchip_t1s driver will bind")
            elif (full_id & 0xFFFFFFF0) == (PHY_ID_LAN865X_REVB & 0xFFFFFFF0):
                rev = full_id & 0xF
                print("PHY ID verdict  : MODEL MATCH, revision {} (not Rev B0/B1)".format(rev))
                print("  >> Add 0x{:08x} to microchip_t1s.c or change mask to 0xFFFFFFF0".format(
                    full_id))
            elif full_id in (0x00000000, 0xFFFFFFFF):
                print("PHY ID verdict  : INVALID (0x{:08x}) – PHY register access not working".format(
                    full_id))
            else:
                print("PHY ID verdict  : MISMATCH – driver will not bind")
                print("  >> Need to add 0x{:08x} to microchip_t1s.c".format(full_id))
        elif not phy_ok:
            print("PHY register echo mismatch – internal PHY may not be accessible yet")
    else:
        print("  Skipped – DPRA not set in STDCAP, internal PHY register access unavailable")

    spi_dev.close()
    print()

    if ok:
        print("SPI transaction framing looks valid.")
        return 0

    print("SPI echo mismatch detected; wiring, chip-select, or SPI mode is likely wrong.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())