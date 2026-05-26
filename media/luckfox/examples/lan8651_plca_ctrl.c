// SPDX-License-Identifier: GPL-2.0+
/*
 * lan8651_plca_ctrl  –  Runtime PLCA role/parameter control for LAN865x
 *
 * Uses SIOCSMIIREG / SIOCGMIIREG with Clause-45 encoding to read and write
 * the OA TC6 PLCA MMD registers (MMD 31 / vendor space) that lan865x.c
 * programs at probe time from DTS.
 *
 * Usage:
 *   lan8651_plca_ctrl <iface> get
 *   lan8651_plca_ctrl <iface> set coordinator   [node_count] [tot_timer]
 *   lan8651_plca_ctrl <iface> set subordinate <node_id> [node_count] [tot_timer]
 *
 * Examples:
 *   lan8651_plca_ctrl eth0 get
 *   lan8651_plca_ctrl eth0 set coordinator 8
 *   lan8651_plca_ctrl eth0 set subordinate 1 8
 *
 * PLCA MMD register map (MMD 31 == MDIO_MMD_VEND2):
 *   0xCA01  PLCA_CTRL0   [15]=EN, rest reserved
 *   0xCA02  PLCA_CTRL1   [15:8]=node_count, [7:0]=node_id
 *   0xCA04  PLCA_TOTMR   [7:0]=to_timer (beacon interval, default 0x18)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <linux/sockios.h>
#include <linux/mii.h>
#include <linux/ethtool.h>

/* Clause-45 packing used by the kernel mii_ioctl path:
 *   phy_reg = (mmd << 16) | reg_offset
 * The kernel net/core/dev_ioctl.c / net/core/ethtool.c handle this when
 * the driver exposes phy_do_ioctl_running() as ndo_do_ioctl.
 * Many drivers accept the MII_ADDR_C45 flag (0x8000) OR honour the
 * upper-16-bit MMD packing; we try both.
 */
#define MII_ADDR_C45_PACK(mmd, reg)  ((1 << 30) | ((mmd) << 16) | (reg))

#define PLCA_MMD                 31           /* MDIO_MMD_VEND2 */
#define PLCA_CTRL0_REG           0xCA01
#define PLCA_CTRL1_REG           0xCA02
#define PLCA_TOTMR_REG           0xCA04

#define PLCA_EN_BIT              (1 << 15)
#define PLCA_NCNT_SHIFT          8
#define PLCA_NCNT_MASK           0xFF00
#define PLCA_ID_MASK             0x00FF

#define PLCA_COL_DET_CTRL0       0x0087        /* LAN86XX vendor reg */
#define COL_DET_EN               (1 << 15)

static int sock = -1;
static struct ifreq ifr;

static int mdio_read(unsigned int reg_c45)
{
    struct mii_ioctl_data *mii = (struct mii_ioctl_data *)&ifr.ifr_data;
    mii->phy_id  = 0;                         /* PHY addr 0 on synthetic bus */
    mii->reg_num = (unsigned short)reg_c45;
    /* Try the upper-word MMD encoding that some kernel paths decode */
    mii->reg_num = (unsigned short)(reg_c45 & 0xFFFF);
    /* Pass MMD in phy_id upper bits – kernel mii_ioctl decodes this for C45 */
    mii->phy_id  = (unsigned short)((reg_c45 >> 16) | 0x8000);

    if (ioctl(sock, SIOCGMIIREG, &ifr) < 0)
        return -errno;
    return (int)(unsigned short)mii->val_out;
}

static int mdio_write(unsigned int reg_c45, unsigned short val)
{
    struct mii_ioctl_data *mii = (struct mii_ioctl_data *)&ifr.ifr_data;
    mii->phy_id  = (unsigned short)((reg_c45 >> 16) | 0x8000);
    mii->reg_num = (unsigned short)(reg_c45 & 0xFFFF);
    mii->val_in  = val;

    if (ioctl(sock, SIOCSMIIREG, &ifr) < 0)
        return -errno;
    return 0;
}

static void plca_print(int ctrl0, int ctrl1, int totmr)
{
    int enabled    = !!(ctrl0 & PLCA_EN_BIT);
    int node_count = (ctrl1 & PLCA_NCNT_MASK) >> PLCA_NCNT_SHIFT;
    int node_id    = (ctrl1 & PLCA_ID_MASK);

    printf("PLCA_CTRL0 (0xCA01) = 0x%04X\n", ctrl0);
    printf("PLCA_CTRL1 (0xCA02) = 0x%04X\n", ctrl1);
    printf("PLCA_TOTMR (0xCA04) = 0x%04X\n", totmr);
    printf("\n");
    printf("  PLCA enabled  : %s\n", enabled ? "yes" : "no");
    printf("  Role          : %s\n", node_id == 0 ? "COORDINATOR" : "subordinate");
    printf("  Node ID       : %d%s\n", node_id,
           node_id == 0 ? "  (coordinator generates BEACON)" : "");
    printf("  Node count    : %d\n", node_count);
    printf("  TO timer      : %d (beacon interval ~%d µs)\n",
           totmr & 0xFF, (totmr & 0xFF) * 100);
}

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage:\n"
        "  %s <iface> get\n"
        "  %s <iface> set coordinator [node_count [tot_timer]]\n"
        "  %s <iface> set subordinate <node_id> [node_count [tot_timer]]\n"
        "\n"
        "Defaults: node_count=8, tot_timer=32 (3.2 ms beacon interval)\n"
        "\n"
        "Examples:\n"
        "  %s eth0 get\n"
        "  %s eth0 set coordinator 8\n"
        "  %s eth0 set subordinate 1 8\n",
        prog, prog, prog, prog, prog, prog);
}

int main(int argc, char *argv[])
{
    if (argc < 3) { usage(argv[0]); return 1; }

    const char *iface = argv[1];
    const char *cmd   = argv[2];

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { perror("socket"); return 1; }

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, iface, IFNAMSIZ - 1);

    if (strcmp(cmd, "get") == 0) {
        int ctrl0 = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL0_REG));
        int ctrl1 = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL1_REG));
        int totmr = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_TOTMR_REG));

        if (ctrl0 < 0 || ctrl1 < 0 || totmr < 0) {
            fprintf(stderr, "MDIO read failed: %s\n"
                    "Make sure eth0 is up: ip link set %s up\n",
                    strerror(-ctrl0 < 0 ? -ctrl0 : -ctrl1), iface);
            close(sock); return 1;
        }
        plca_print(ctrl0, ctrl1, totmr);
        close(sock); return 0;
    }

    if (strcmp(cmd, "set") == 0 && argc >= 4) {
        const char *role = argv[3];
        int node_id    = -1;
        int node_count = 8;   /* default */
        int tot_timer  = 32;  /* default ~3.2 ms */
        int argoff     = 4;

        if (strcmp(role, "coordinator") == 0) {
            node_id = 0;
            /* Optional: node_count, tot_timer */
            if (argc > argoff) node_count = atoi(argv[argoff++]);
            if (argc > argoff) tot_timer  = atoi(argv[argoff++]);
        } else if (strcmp(role, "subordinate") == 0) {
            if (argc < 5) {
                fprintf(stderr, "subordinate requires a node_id argument\n");
                usage(argv[0]); close(sock); return 1;
            }
            node_id = atoi(argv[argoff++]);
            if (node_id == 0) {
                fprintf(stderr, "Error: node_id 0 is reserved for coordinator\n");
                close(sock); return 1;
            }
            if (argc > argoff) node_count = atoi(argv[argoff++]);
            if (argc > argoff) tot_timer  = atoi(argv[argoff++]);
        } else {
            fprintf(stderr, "Unknown role '%s'. Use 'coordinator' or 'subordinate'\n", role);
            usage(argv[0]); close(sock); return 1;
        }

        /* Step 1: disable PLCA before changing parameters */
        int ctrl0 = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL0_REG));
        if (ctrl0 < 0) {
            fprintf(stderr, "MDIO read CTRL0 failed: %s\n", strerror(-ctrl0));
            close(sock); return 1;
        }
        int ret = mdio_write(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL0_REG),
                             (unsigned short)(ctrl0 & ~PLCA_EN_BIT));
        if (ret < 0) {
            fprintf(stderr, "MDIO write CTRL0 (disable) failed: %s\n", strerror(-ret));
            close(sock); return 1;
        }

        /* Step 2: write node_id and node_count */
        unsigned short ctrl1 = (unsigned short)(
            ((node_count << PLCA_NCNT_SHIFT) & PLCA_NCNT_MASK) |
            (node_id & PLCA_ID_MASK));
        ret = mdio_write(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL1_REG), ctrl1);
        if (ret < 0) {
            fprintf(stderr, "MDIO write CTRL1 failed: %s\n", strerror(-ret));
            close(sock); return 1;
        }

        /* Step 3: write TO timer */
        ret = mdio_write(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_TOTMR_REG),
                         (unsigned short)(tot_timer & 0xFF));
        if (ret < 0) {
            fprintf(stderr, "MDIO write TOTMR failed: %s\n", strerror(-ret));
            close(sock); return 1;
        }

        /* Step 4: re-enable PLCA */
        ret = mdio_write(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL0_REG),
                         (unsigned short)(ctrl0 | PLCA_EN_BIT));
        if (ret < 0) {
            fprintf(stderr, "MDIO write CTRL0 (enable) failed: %s\n", strerror(-ret));
            close(sock); return 1;
        }

        /* Step 5: disable collision detection for PLCA operation */
        mdio_write(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_COL_DET_CTRL0), 0x0000);

        /* Confirm */
        ctrl0 = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL0_REG));
        int rctrl1 = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_CTRL1_REG));
        int rtotmr = mdio_read(MII_ADDR_C45_PACK(PLCA_MMD, PLCA_TOTMR_REG));
        printf("Applied. Current state:\n");
        plca_print(ctrl0, rctrl1, rtotmr);

        close(sock);
        return 0;
    }

    usage(argv[0]);
    close(sock);
    return 1;
}
