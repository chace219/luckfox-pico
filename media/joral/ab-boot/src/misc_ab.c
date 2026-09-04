/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * misc_ab — Linux userspace reader/writer for the Rockchip/AVB A/B slot
 * metadata in the `misc` partition.
 *
 * This is the userspace half of the initramfs-driven A/B design
 * (media/joral/swupdate-implementation-plan.md, "Chosen design"): the
 * initramfs uses `select` to pick the slot to boot and burn a try; the
 * health-check service uses `mark-successful` once the slot has proven
 * itself; SWUpdate's post-install hook uses `mark-active` to arm the slot it
 * just wrote; the console uses `status` to display slot state.
 *
 * The on-disk format is defined by the bootloader sources in this SDK and
 * must match them BYTE-EXACTLY — SPL reads the same record when
 * CONFIG_SPL_AB is in play, and keeping the format identical is what
 * preserves the option of handing slot selection back to the bootloader
 * later without a fleet migration:
 *
 *   sysdrv/source/uboot/u-boot/include/android_avb/avb_ab_flow.h
 *     AvbABData: magic "\0AB0", version 1.0, 2 slots of
 *     {priority, tries_remaining, successful_boot}, last_boot,
 *     CRC32 (zlib) over the 28 bytes before the crc field, stored
 *     BIG-ENDIAN. All other fields are single bytes.
 *   sysdrv/source/uboot/u-boot/common/spl/spl_ab.c
 *     Location: one 512-byte sector at LBA (misc_start + 4), i.e. byte
 *     offset 2048 into the partition (AB_METADATA_OFFSET in spl_ab.h).
 *     Record occupies the first 32 bytes of that sector.
 *     Selection: a slot is bootable iff priority > 0 && (successful_boot ||
 *     tries_remaining > 0); with both bootable the higher priority wins
 *     (slot A on a tie); with neither, fall back to last_boot.
 *     Init defaults: A = {15, 7, 0}, B = {14, 7, 0}, last_boot = 0.
 *
 * Usage:
 *   misc_ab status  <dev>            print both slots + the chosen one
 *   misc_ab init    <dev>            write factory defaults (A active)
 *   misc_ab select  <dev>            pick slot, burn a try, update
 *                                    last_boot, write back; prints "a"|"b".
 *                                    THE INITRAMFS CALL.
 *   misc_ab mark-successful <dev> <a|b>   tries=0, successful=1
 *   misc_ab mark-active     <dev> <a|b>   priority=15, tries=7,
 *                                    successful=0, other slot demoted to 14.
 *                                    THE POST-UPDATE CALL.
 *   misc_ab mark-unbootable <dev> <a|b>   priority=tries=successful=0
 *
 * <dev> is the misc partition device (or a plain file in tests — everything
 * is pread/pwrite at fixed offsets, so a scratch file behaves identically).
 * Exit 0 on success; on any failure nothing is written.
 */

#define _XOPEN_SOURCE 500   /* pread/pwrite under -std=c99 */

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/ioctl.h>
#include <sys/stat.h>
#include <mtd/mtd-user.h>

#define AB_MAGIC          "\0AB0"
#define AB_MAGIC_LEN      4
#define AB_MAJOR_VERSION  1
#define AB_MINOR_VERSION  0
#define AB_MAX_PRIORITY   15
#define AB_MAX_TRIES      7
/* AB_METADATA_OFFSET (spl_ab.h) is in 512-byte LBAs. */
#define AB_BYTE_OFFSET    (4 * 512)
#define AB_SECTOR_SIZE    512

typedef struct {
	uint8_t priority;
	uint8_t tries_remaining;
	uint8_t successful_boot;
	uint8_t reserved[1];
} __attribute__((packed)) slot_data_t;

typedef struct {
	uint8_t     magic[AB_MAGIC_LEN];
	uint8_t     version_major;
	uint8_t     version_minor;
	uint8_t     reserved1[2];
	slot_data_t slots[2];
	uint8_t     last_boot;
	uint8_t     reserved2[11];
	uint32_t    crc32;   /* big-endian on disk */
} __attribute__((packed)) ab_data_t;

_Static_assert(sizeof(ab_data_t) == 32, "AvbABData must be 32 bytes");

/* zlib-compatible CRC32 (the bootloader uses U-Boot's crc32(), which is the
 * same polynomial/reflection/init as zlib). Table-free bitwise form — this
 * runs a handful of times per boot on 28 bytes. */
static uint32_t crc32z(const uint8_t *buf, size_t len)
{
	uint32_t crc = 0xffffffffu;
	size_t i;
	int b;

	for (i = 0; i < len; i++) {
		crc ^= buf[i];
		for (b = 0; b < 8; b++)
			crc = (crc >> 1) ^ (0xedb88320u & (-(crc & 1u)));
	}
	return crc ^ 0xffffffffu;
}

static uint32_t record_crc(const ab_data_t *d)
{
	return crc32z((const uint8_t *)d, sizeof(*d) - sizeof(uint32_t));
}

/* The crc32 field sits at a 4-byte-aligned offset but lives in a packed
 * struct, so it is addressed via byte pointers rather than &d->crc32. */
static void put_be32(uint32_t v, void *out)
{
	uint8_t *p = out;

	p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

static uint32_t get_be32(const void *in)
{
	const uint8_t *p = in;

	return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
	       ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void ab_init(ab_data_t *d)
{
	memset(d, 0, sizeof(*d));
	memcpy(d->magic, AB_MAGIC, AB_MAGIC_LEN);
	d->version_major = AB_MAJOR_VERSION;
	d->version_minor = AB_MINOR_VERSION;
	d->slots[0].priority = AB_MAX_PRIORITY;
	d->slots[0].tries_remaining = AB_MAX_TRIES;
	d->slots[1].priority = AB_MAX_PRIORITY - 1;
	d->slots[1].tries_remaining = AB_MAX_TRIES;
	d->last_boot = 0;
}

/* Mirrors spl_slot_normalize(): collapse every illegal or exhausted state to
 * the canonical unbootable one, so the rest of the logic only ever sees legal
 * records. */
static void slot_normalize(slot_data_t *s)
{
	if (s->priority > 0) {
		if (s->tries_remaining == 0 && !s->successful_boot) {
			s->priority = 0;         /* tries exhausted */
		} else if (s->tries_remaining > 0 && s->successful_boot) {
			s->priority = 0;         /* illegal combination */
			s->tries_remaining = 0;
			s->successful_boot = 0;
		}
	} else {
		s->tries_remaining = 0;
		s->successful_boot = 0;
	}
	if (s->priority == 0) {
		s->tries_remaining = 0;
		s->successful_boot = 0;
	}
}

static int slot_bootable(const slot_data_t *s)
{
	return s->priority > 0 &&
	       (s->successful_boot || s->tries_remaining > 0);
}

/* read: returns 0 and a host-order record; -1 on I/O error. A record that is
 * missing/corrupt is replaced by factory defaults IN MEMORY and *reinit is
 * set — callers that write back then persist the recovery, which is exactly
 * what spl_ab_data_read() does. */
static int ab_read(int fd, ab_data_t *d, int *reinit)
{
	uint8_t sect[AB_SECTOR_SIZE];
	ssize_t n;

	*reinit = 0;
	n = pread(fd, sect, sizeof(sect), AB_BYTE_OFFSET);
	if (n != (ssize_t)sizeof(sect)) {
		/* Short read: a misc partition smaller than 2.5 KB is a
		 * provisioning error, not a recoverable state. */
		fprintf(stderr, "misc_ab: read at %d: %s\n", AB_BYTE_OFFSET,
			n < 0 ? strerror(errno) : "short read");
		return -1;
	}
	memcpy(d, sect, sizeof(*d));

	if (memcmp(d->magic, AB_MAGIC, AB_MAGIC_LEN) != 0 ||
	    d->version_major > AB_MAJOR_VERSION ||
	    get_be32((const uint8_t *)d + offsetof(ab_data_t, crc32)) != record_crc(d)) {
		ab_init(d);
		*reinit = 1;
		return 0;
	}
	d->crc32 = get_be32((const uint8_t *)d + offsetof(ab_data_t, crc32));
	return 0;
}

/* On the Pico Max, `misc` is a raw MTD partition and <dev> is its char
 * device (/dev/mtdN): reads work like any file, but NAND cannot rewrite a
 * page in place — the enclosing erase block must be erased first. So the
 * MTD write path is read-modify-erase-write over the WHOLE erase block that
 * holds the record (block 0 of the partition; the record sits at byte 2048,
 * far inside even the smallest 128 KiB block).
 *
 * The erase->write window is a real, milliseconds-wide corruption hazard a
 * block device does not have: power loss inside it loses the record. That is
 * accepted rather than engineered around, because ab_read() already treats a
 * corrupt record as "reinitialise to factory defaults (A active)" — the same
 * self-healing the SPL applies — so the worst case is one boot into slot A,
 * not a brick. Probed with MEMGETINFO at open; a block device or a plain
 * test file fails the ioctl and takes the plain pwrite path. */
static int mtd_probe(int fd, mtd_info_t *mtd)
{
	struct stat st;

	if (fstat(fd, &st) != 0 || !S_ISCHR(st.st_mode))
		return 0;
	if (ioctl(fd, MEMGETINFO, mtd) != 0)
		return 0;
	if (AB_BYTE_OFFSET + AB_SECTOR_SIZE > mtd->erasesize) {
		fprintf(stderr, "misc_ab: erase block (%u) smaller than the "
			"record offset — unsupported flash geometry\n",
			mtd->erasesize);
		return -1;
	}
	return 1;
}

static int ab_write_mtd(int fd, const uint8_t *sect, const mtd_info_t *mtd)
{
	erase_info_t ei = { .start = 0, .length = mtd->erasesize };
	uint8_t *block;
	ssize_t n;
	int rc = -1;

	block = malloc(mtd->erasesize);
	if (!block) {
		fprintf(stderr, "misc_ab: out of memory\n");
		return -1;
	}
	n = pread(fd, block, mtd->erasesize, 0);
	if (n != (ssize_t)mtd->erasesize) {
		fprintf(stderr, "misc_ab: mtd read block 0: %s\n",
			n < 0 ? strerror(errno) : "short read");
		goto out;
	}
	memcpy(block + AB_BYTE_OFFSET, sect, AB_SECTOR_SIZE);
	if (ioctl(fd, MEMERASE, &ei) != 0) {
		/* A failed erase usually means block 0 went bad; there is no
		 * relocation story for the record, so say so loudly. */
		fprintf(stderr, "misc_ab: MEMERASE block 0: %s\n",
			strerror(errno));
		goto out;
	}
	n = pwrite(fd, block, mtd->erasesize, 0);
	if (n != (ssize_t)mtd->erasesize) {
		fprintf(stderr, "misc_ab: mtd write block 0: %s\n",
			n < 0 ? strerror(errno) : "short write");
		goto out;
	}
	rc = 0;
out:
	free(block);
	return rc;
}

static int ab_write(int fd, const ab_data_t *d, const mtd_info_t *mtd)
{
	uint8_t sect[AB_SECTOR_SIZE];
	ab_data_t out;
	ssize_t n;

	memset(sect, 0, sizeof(sect));
	memcpy(&out, d, sizeof(out));
	put_be32(record_crc(&out), (uint8_t *)&out + offsetof(ab_data_t, crc32));
	memcpy(sect, &out, sizeof(out));

	if (mtd)
		return ab_write_mtd(fd, sect, mtd);

	n = pwrite(fd, sect, sizeof(sect), AB_BYTE_OFFSET);
	if (n != (ssize_t)sizeof(sect)) {
		fprintf(stderr, "misc_ab: write at %d: %s\n", AB_BYTE_OFFSET,
			n < 0 ? strerror(errno) : "short write");
		return -1;
	}
	if (fsync(fd) != 0) {
		fprintf(stderr, "misc_ab: fsync: %s\n", strerror(errno));
		return -1;
	}
	return 0;
}

/* Same decision as spl_get_current_slot(): both bootable -> higher priority
 * (A on tie); one -> that one; none -> last_boot. Returns 0/1, or -1 when
 * even last_boot names nothing (only possible on a corrupt record, which
 * ab_read() already replaced — so in practice never). */
static int ab_pick(const ab_data_t *d)
{
	int a = slot_bootable(&d->slots[0]);
	int b = slot_bootable(&d->slots[1]);

	if (a && b)
		return d->slots[1].priority > d->slots[0].priority ? 1 : 0;
	if (a)
		return 0;
	if (b)
		return 1;
	return d->last_boot <= 1 ? d->last_boot : -1;
}

static int parse_slot(const char *s)
{
	if (strcmp(s, "a") == 0 || strcmp(s, "A") == 0)
		return 0;
	if (strcmp(s, "b") == 0 || strcmp(s, "B") == 0)
		return 1;
	fprintf(stderr, "misc_ab: bad slot '%s' (want a|b)\n", s);
	return -1;
}

static void print_status(const ab_data_t *d)
{
	int pick = ab_pick(d);
	int i;

	for (i = 0; i < 2; i++)
		printf("slot_%c: priority=%u tries_remaining=%u "
		       "successful_boot=%u bootable=%s\n",
		       'a' + i, d->slots[i].priority,
		       d->slots[i].tries_remaining,
		       d->slots[i].successful_boot,
		       slot_bootable(&d->slots[i]) ? "yes" : "no");
	printf("last_boot=%c\n", d->last_boot ? 'b' : 'a');
	printf("choice=%s\n", pick < 0 ? "none" : (pick ? "b" : "a"));
}

static void usage(void)
{
	fprintf(stderr,
		"usage: misc_ab status|init|select <dev>\n"
		"       misc_ab mark-successful|mark-active|mark-unbootable "
		"<dev> <a|b>\n");
}

int main(int argc, char **argv)
{
	const char *cmd, *dev;
	ab_data_t d;
	mtd_info_t mtd_info;
	const mtd_info_t *mtd = NULL;
	int fd, reinit, pick, slot = -1, rc = 1, probed;

	if (argc < 3) {
		usage();
		return 1;
	}
	cmd = argv[1];
	dev = argv[2];

	if (strncmp(cmd, "mark-", 5) == 0) {
		if (argc < 4 || (slot = parse_slot(argv[3])) < 0) {
			usage();
			return 1;
		}
	}

	fd = open(dev, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "misc_ab: open %s: %s\n", dev,
			strerror(errno));
		return 1;
	}

	probed = mtd_probe(fd, &mtd_info);
	if (probed < 0) {
		close(fd);
		return 1;
	}
	if (probed)
		mtd = &mtd_info;

	if (strcmp(cmd, "init") == 0) {
		ab_init(&d);
		rc = ab_write(fd, &d, mtd) ? 1 : 0;
	} else if (ab_read(fd, &d, &reinit) != 0) {
		rc = 1;
	} else if (strcmp(cmd, "status") == 0) {
		if (reinit)
			printf("(record was invalid; showing defaults, "
			       "not yet persisted)\n");
		print_status(&d);
		rc = 0;
	} else if (strcmp(cmd, "select") == 0) {
		slot_normalize(&d.slots[0]);
		slot_normalize(&d.slots[1]);
		pick = ab_pick(&d);
		if (pick < 0) {
			fprintf(stderr, "misc_ab: no bootable slot\n");
			rc = 1;
		} else {
			/* Burn a try only while the slot is still proving
			 * itself; a successful slot boots without spending
			 * anything (spl_ab_decrease_tries() semantics). */
			if (!d.slots[pick].successful_boot &&
			    d.slots[pick].tries_remaining > 0)
				d.slots[pick].tries_remaining--;
			d.last_boot = (uint8_t)pick;
			if (ab_write(fd, &d, mtd) == 0) {
				printf("%c\n", pick ? 'b' : 'a');
				rc = 0;
			}
		}
	} else if (strcmp(cmd, "mark-successful") == 0) {
		d.slots[slot].tries_remaining = 0;
		d.slots[slot].successful_boot = 1;
		if (d.slots[slot].priority == 0)
			d.slots[slot].priority = AB_MAX_PRIORITY;
		rc = ab_write(fd, &d, mtd) ? 1 : 0;
	} else if (strcmp(cmd, "mark-active") == 0) {
		d.slots[slot].priority = AB_MAX_PRIORITY;
		d.slots[slot].tries_remaining = AB_MAX_TRIES;
		d.slots[slot].successful_boot = 0;
		/* Demote the other slot below the new one but leave it
		 * bootable — it is the rollback target. */
		if (d.slots[1 - slot].priority >= AB_MAX_PRIORITY)
			d.slots[1 - slot].priority = AB_MAX_PRIORITY - 1;
		rc = ab_write(fd, &d, mtd) ? 1 : 0;
	} else if (strcmp(cmd, "mark-unbootable") == 0) {
		d.slots[slot].priority = 0;
		d.slots[slot].tries_remaining = 0;
		d.slots[slot].successful_boot = 0;
		rc = ab_write(fd, &d, mtd) ? 1 : 0;
	} else {
		usage();
	}

	close(fd);
	return rc;
}
