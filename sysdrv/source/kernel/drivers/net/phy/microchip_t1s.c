// SPDX-License-Identifier: GPL-2.0+
/*
 * Driver for Microchip 10BASE-T1S PHYs
 *
 * Support: Microchip Phys:
 *  lan8650/1 Rev.B0/B1 internal PHYs
 */

#include <linux/bitfield.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/phy.h>

/* Matches Rev B0 (0x0007C1B3).  Use model mask so any sub-revision (B0–BF)
 * is accepted; the init sequence from AN1760 applies to all Rev B silicon.
 */
#define PHY_ID_LAN865X_REVB 0x0007C1B0

#define LAN865X_REG_CFGPARAM_ADDR 0x00D8
#define LAN865X_REG_CFGPARAM_DATA 0x00D9
#define LAN865X_REG_CFGPARAM_CTRL 0x00DA

#define LAN865X_CFGPARAM_READ_ENABLE BIT(1)

static const u32 lan865x_revb_fixup_registers[17] = {
	0x00D0, 0x00E0, 0x00E9, 0x00F5,
	0x00F4, 0x00F8, 0x00F9, 0x0081,
	0x0091, 0x0043, 0x0044, 0x0045,
	0x0053, 0x0054, 0x0055, 0x0040,
	0x0050,
};

static const u16 lan865x_revb_fixup_values[17] = {
	0x3F31, 0xC000, 0x9E50, 0x1CF8,
	0xC020, 0xB900, 0x4E53, 0x0080,
	0x9660, 0x00FF, 0xFFFF, 0x0000,
	0x00FF, 0xFFFF, 0x0000, 0x0002,
	0x0002,
};

static const u16 lan865x_revb_fixup_cfg_regs[2] = {
	0x0084, 0x008A,
};

static const u32 lan865x_revb_sqi_fixup_regs[12] = {
	0x00B0, 0x00B1, 0x00B2, 0x00B3,
	0x00B4, 0x00B5, 0x00B6, 0x00B7,
	0x00B8, 0x00B9, 0x00BA, 0x00BB,
};

static const u16 lan865x_revb_sqi_fixup_values[12] = {
	0x0103, 0x0910, 0x1D26, 0x002A,
	0x0103, 0x070D, 0x1720, 0x0027,
	0x0509, 0x0E13, 0x1C25, 0x002B,
};

static const u16 lan865x_revb_sqi_fixup_cfg_regs[3] = {
	0x00AD, 0x00AE, 0x00AF,
};

static int lan865x_revb_indirect_read(struct phy_device *phydev, u16 addr)
{
	int ret;

	ret = phy_write_mmd(phydev, MDIO_MMD_VEND2, LAN865X_REG_CFGPARAM_ADDR,
			    addr);
	if (ret)
		return ret;

	ret = phy_write_mmd(phydev, MDIO_MMD_VEND2, LAN865X_REG_CFGPARAM_CTRL,
			    LAN865X_CFGPARAM_READ_ENABLE);
	if (ret)
		return ret;

	return phy_read_mmd(phydev, MDIO_MMD_VEND2, LAN865X_REG_CFGPARAM_DATA);
}

static int lan865x_generate_cfg_offsets(struct phy_device *phydev, s8 offsets[])
{
	const u16 fixup_regs[2] = { 0x0004, 0x0008 };
	int ret;
	int i;

	for (i = 0; i < ARRAY_SIZE(fixup_regs); i++) {
		ret = lan865x_revb_indirect_read(phydev, fixup_regs[i]);
		if (ret < 0)
			return ret;

		ret &= GENMASK(4, 0);
		if (ret & BIT(4))
			offsets[i] = ret | 0xE0;
		else
			offsets[i] = ret;
	}

	return 0;
}

static int lan865x_write_cfg_params(struct phy_device *phydev,
				    const u16 cfg_regs[], u16 cfg_params[],
				    u8 count)
{
	int ret;
	int i;

	for (i = 0; i < count; i++) {
		ret = phy_write_mmd(phydev, MDIO_MMD_VEND2, cfg_regs[i],
				    cfg_params[i]);
		if (ret)
			return ret;
	}

	return 0;
}

static int lan865x_setup_cfgparam(struct phy_device *phydev, s8 offsets[])
{
	u16 cfg_results[ARRAY_SIZE(lan865x_revb_fixup_cfg_regs)];

	cfg_results[0] = FIELD_PREP(GENMASK(15, 10), 9 + offsets[0]) |
			 FIELD_PREP(GENMASK(9, 4), 14 + offsets[0]) |
			 0x03;
	cfg_results[1] = FIELD_PREP(GENMASK(15, 10), 40 + offsets[1]);

	return lan865x_write_cfg_params(phydev, lan865x_revb_fixup_cfg_regs,
					cfg_results, ARRAY_SIZE(cfg_results));
}

static int lan865x_setup_sqi_cfgparam(struct phy_device *phydev, s8 offsets[])
{
	u16 cfg_results[ARRAY_SIZE(lan865x_revb_sqi_fixup_cfg_regs)];

	cfg_results[0] = FIELD_PREP(GENMASK(13, 8), 5 + offsets[0]) |
			 (9 + offsets[0]);
	cfg_results[1] = FIELD_PREP(GENMASK(13, 8), 9 + offsets[0]) |
			 (14 + offsets[0]);
	cfg_results[2] = FIELD_PREP(GENMASK(13, 8), 17 + offsets[0]) |
			 (22 + offsets[0]);

	return lan865x_write_cfg_params(phydev, lan865x_revb_sqi_fixup_cfg_regs,
					cfg_results, ARRAY_SIZE(cfg_results));
}

static int lan865x_revb_config_init(struct phy_device *phydev)
{
	s8 offsets[2];
	int ret;
	int i;

	phydev->autoneg = AUTONEG_DISABLE;

	ret = lan865x_generate_cfg_offsets(phydev, offsets);
	if (ret)
		return ret;

	for (i = 0; i < ARRAY_SIZE(lan865x_revb_fixup_registers); i++) {
		ret = phy_write_mmd(phydev, MDIO_MMD_VEND2,
				    lan865x_revb_fixup_registers[i],
				    lan865x_revb_fixup_values[i]);
		if (ret)
			return ret;

		if (i == 1) {
			ret = lan865x_setup_cfgparam(phydev, offsets);
			if (ret)
				return ret;
		}
	}

	ret = lan865x_setup_sqi_cfgparam(phydev, offsets);
	if (ret)
		return ret;

	for (i = 0; i < ARRAY_SIZE(lan865x_revb_sqi_fixup_regs); i++) {
		ret = phy_write_mmd(phydev, MDIO_MMD_VEND2,
				    lan865x_revb_sqi_fixup_regs[i],
				    lan865x_revb_sqi_fixup_values[i]);
		if (ret)
			return ret;
	}

	return 0;
}

static int lan865x_get_features(struct phy_device *phydev)
{
	linkmode_zero(phydev->supported);
	linkmode_set_bit(ETHTOOL_LINK_MODE_TP_BIT, phydev->supported);
	linkmode_set_bit(ETHTOOL_LINK_MODE_10baseT_Half_BIT,
			 phydev->supported);
	linkmode_copy(phydev->advertising, phydev->supported);

	return 0;
}

static int lan86xx_read_status(struct phy_device *phydev)
{
	phydev->link = 1;
	phydev->duplex = DUPLEX_HALF;
	phydev->speed = SPEED_10;
	phydev->autoneg = AUTONEG_DISABLE;

	return 0;
}

static int lan865x_phy_read_mmd(struct phy_device *phydev, int devnum,
				u16 regnum)
{
	struct mii_bus *bus = phydev->mdio.bus;
	int addr = phydev->mdio.addr;

	return __mdiobus_c45_read(bus, addr, devnum, regnum);
}

static int lan865x_phy_write_mmd(struct phy_device *phydev, int devnum,
				 u16 regnum, u16 val)
{
	struct mii_bus *bus = phydev->mdio.bus;
	int addr = phydev->mdio.addr;

	return __mdiobus_c45_write(bus, addr, devnum, regnum, val);
}

static struct phy_driver microchip_t1s_driver[] = {
	{
		PHY_ID_MATCH_MODEL(PHY_ID_LAN865X_REVB),
		.name		= "LAN865X Rev.B Internal PHY",
		/* .features must stay unset: phylib rejects drivers that set both
		 * .features and .get_features, and a rejected driver means the
		 * Generic PHY attaches instead - silently skipping the mandatory
		 * AN1760 Rev.B trim fixups in lan865x_revb_config_init(). */
		.get_features	= lan865x_get_features,
		.config_init	= lan865x_revb_config_init,
		.read_status	= lan86xx_read_status,
		.read_mmd	= lan865x_phy_read_mmd,
		.write_mmd	= lan865x_phy_write_mmd,
	},
};

module_phy_driver(microchip_t1s_driver);

static const struct mdio_device_id __maybe_unused microchip_t1s_tbl[] = {
	{ PHY_ID_MATCH_MODEL(PHY_ID_LAN865X_REVB) },
	{ }
};

MODULE_DEVICE_TABLE(mdio, microchip_t1s_tbl);

MODULE_DESCRIPTION("Microchip 10BASE-T1S PHYs driver");
MODULE_AUTHOR("GitHub Copilot backport");
MODULE_LICENSE("GPL");