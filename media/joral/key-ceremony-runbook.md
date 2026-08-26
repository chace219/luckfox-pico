# Firmware signing key ceremony — runbook

*The **decision** is [`firmware-signing-and-support-policy.md`](firmware-signing-and-support-policy.md)
Part A, drafted 2026-08-14 and awaiting Carl's signature. This file is the
**execution**: what to buy, what to do in the room, what changes in the build
afterwards, and how to prove it actually took. It exists because A.2 is nine
lines of policy and the ceremony is a two-person session with steps that are
irreversible in the wrong order.*

*Nothing here changes the policy. Where the two disagree, the policy is the
decision and this file is wrong.*

---

## What the ceremony produces, and what it switches

Six files, from one script:

| | |
|---|---|
| `private/joral-fw-2026-a.key.pem` | active signing key — to the media, then shredded from disk |
| `private/joral-fw-2026-b.key.pem` | rollover spare — same |
| `public/joral-fw-2026-a.crt.pem` | committed to the repo |
| `public/joral-fw-2026-b.crt.pem` | committed to the repo |
| `public/trusted-certs.pem` | both certs; ships as `/etc/swupdate/trusted-certs.pem` |
| `ceremony-minute.txt` | pre-filled; signed on paper, filed in the technical file |

**The switch is a file, not a flag.** `media/joral/ab-boot/Makefile` looks for
`scripts/compliance/keys/trusted-certs.pem`; if it is there, `install` stages
the production trust store and says so
(`INSTALL  PRODUCTION trust store -> /etc/swupdate/trusted-certs.pem`), and if
it is not, it stages the per-checkout DEV bundle and says *that*
(`NOT FOR SHIPMENT`). `./build.sh swu` reads the same path and changes mode:
with production certs present it writes an **unsigned** `sw-description`, prints
its sha256 and exits 2 with the offline-signing instructions. No code change is
involved in the switchover, and no code change can be forgotten.

---

## Before the day

### 1. Decide the media — and read this before ordering

Policy A.1 says "hardware tokens / encrypted media". The ceremony script emits
**AES-256-encrypted PEM private keys on disk**, so with the flow as written,
"token" means *encrypted removable media*: a PIV token or HSM would need an
import step this runbook does not have and the script does not do.

**Recommended purchase: four identical USB sticks**, LUKS-formatted, in two
labelled sets. Four physical items, as A.3 requires. If a hardware token is
wanted later, A.4 already names the upgrade path — a dedicated signing station
holding the *same* keys, which is a change to how we sign and not to what the
fleet trusts, so it never touches a shipped unit.

This is the only item on the whole page with a delivery time. Order before the
meeting; it costs nothing if the meeting slips.

### 2. Prepare the live USB (on any normal machine)

A current Debian or Ubuntu live image, checksum verified. It needs `openssl`,
`shred`, `cryptsetup` and `ip` — all present on the standard desktop images.
Nothing on this system persists, which is the point.

### 3. Load the transfer stick

`scripts/compliance/fw-key-ceremony.sh`, `scripts/compliance/fw-sign.sh`, and a
printed copy of this runbook. The transfer stick is ordinary and unencrypted; it
never carries a private key.

### 4. Book 90 minutes for a 60-minute ceremony

Present: **Carl and one named engineer** — the two passphrase holders (A.2).
Both stay for the whole session. Two RSA-4096 keygens on a live-USB laptop are
not instant.

### 5. Agree the passphrase beforehand

One passphrase, both holders know it, `openssl` will ask for it four times
(twice per key). Decide it in advance rather than inventing it at the keyboard,
and consider writing it on paper into two sealed envelopes, one per key set —
**both holders forgetting it strands the fleet**, and the recovery for that is
A.5, not a support call.

---

## The ceremony

> The order below is load-bearing in exactly one place: **the passphrase and
> every copy are verified before anything is destroyed.** Everything else is
> housekeeping.

**0. Set the room.** Laptop off ethernet, Wi-Fi hardware disabled (`rfkill block
all`), Bluetooth off. This is the procedure; the script's check is a seatbelt,
not proof.

**1. Boot the live USB.** Do not connect to any network at any point.

```sh
ip route          # must print nothing
ip -br link       # no carrier anywhere
```

The ceremony script refuses to run if it sees a default route.

**2. Check the clock.**

```sh
date -u
```

A live session can boot with a wrong RTC, and the certificates take their
`notBefore` from it. If it is wrong, set it from a phone or a watch — not from
the network:

```sh
date -u -s 'YYYY-MM-DD HH:MM'
```

**3. Generate, into RAM rather than onto flash.**

```sh
mkdir -p /run/ceremony
sh /media/<transfer>/fw-key-ceremony.sh /run/ceremony
```

`/run` is tmpfs: it disappears at power-off whatever else happens. The private
keys the script writes are encrypted, so the copies that later land on flash are
encrypted too — which matters because `shred` is unreliable on flash media, and
this is what makes that irrelevant.

Enter the shared passphrase when prompted (four prompts: two keys, confirmed).

**4. Prove the passphrase before destroying anything.**

```sh
openssl pkey -in /run/ceremony/private/joral-fw-2026-a.key.pem -noout
openssl pkey -in /run/ceremony/private/joral-fw-2026-b.key.pem -noout
```

Each must prompt, accept, and exit 0. **A typo agreed to by two people who both
thought they knew it is the one mistake in this procedure that cannot be walked
back after the disk copies are gone.**

**5. Write the four media.** For each stick, in turn:

```sh
cryptsetup luksFormat /dev/sdX          # confirm; set the stick passphrase
cryptsetup open /dev/sdX ceremony
mkfs.ext4 /dev/mapper/ceremony
mount /dev/mapper/ceremony /mnt
cp /run/ceremony/private/*.key.pem /mnt/
sync
openssl pkey -in /mnt/joral-fw-2026-a.key.pem -noout   # read it BACK, from the stick
openssl pkey -in /mnt/joral-fw-2026-b.key.pem -noout
umount /mnt && cryptsetup close ceremony
```

Both keys go on every stick. Label as you go:
`JORAL FW SIGNING — SET 1 (SAFE) — <date>` and `SET 2 (OFF-SITE)`.

**6. Take the public halves.** Copy `/run/ceremony/public/` to the transfer
stick. These are certificates; they are meant to be public.

**7. Sign the minute.** The script pre-fills the date and the sha256 of both
certificates. Fill in the two names and the four media serials; both holders
sign the paper. It goes in the technical file — an assessor asking how the
signing key is held is asking for exactly this document.

**8. Destroy and power off.**

```sh
shred -u /run/ceremony/private/*.key.pem
poweroff
```

**9. Separate the sets the same day.** Set 1 to the office safe, set 2 off-site.
Two sets in one building overnight is the failure the second set exists to
prevent.

---

## After the ceremony — engineering, same week

**1. Commit the public halves.**

```sh
mkdir -p scripts/compliance/keys
cp <transfer>/public/joral-fw-2026-a.crt.pem \
   <transfer>/public/joral-fw-2026-b.crt.pem \
   <transfer>/public/trusted-certs.pem scripts/compliance/keys/
git add scripts/compliance/keys && git commit
```

**Never commit a `.key.pem`.** There is no gate against it today — see the
open item at the end of this file.

**2. Rebuild, and read the log line.**

```sh
./build.sh media && ./build.sh firmware
```

Expect `INSTALL  PRODUCTION trust store -> /etc/swupdate/trusted-certs.pem`.
That line is the switchover. If it still says DEV, the certs are not where the
Makefile looks.

**3. Cut a release through the offline flow** (policy A.4, ~15 min):

```sh
./build.sh swu                       # exits 2, prints sw-description + its sha256
# carry output/image/sw-description to the offline laptop; verify the sha256
sh fw-sign.sh sign sw-description <SET-1 key-a> <cert-a>
# carry sw-description.sig back
./build.sh swu --sig output/image/sw-description.sig
```

The build then verifies the signature against **the trust store staged for the
image** before it calls the result a release artifact — so a `.swu` the shipped
rootfs would reject can never leave the build.

**4. Start the signing log.** `fw-sign.sh` and `build.sh` both tell the operator
to append a line to `docs/compliance/signing-log.md`, and **that directory does
not exist in this repo**. Create it with the header (date, version, `.swu`
sha256, signer, media serial) and append the first line at the first production
release.

**5. File the paperwork.** Ceremony minute into the technical file; both
certificate fingerprints into `cra-annex2-facts.md` in each product tree.

---

## Proving it took

The log line is a claim. These are the checks:

```sh
# 1. the staged bundle: exactly two certs, both ours, no DEV
openssl crl2pkcs7 -nocrl -certfile media/out/root/etc/swupdate/trusted-certs.pem |
  openssl pkcs7 -print_certs -noout
#   -> CN=joral-fw-2026-a and CN=joral-fw-2026-b
#   -> and NO 'OU=DEV SIGNING - NOT FOR SHIPMENT'

# 2. read it out of the PACKED image, not the staging tree
debugfs -R "cat /etc/swupdate/trusted-certs.pem" output/image/rootfs.img
```

Reading the packed image rather than the tree that fed it is the same
discipline `./build.sh swu` applies to the release identity, and for the same
reason: a staging tree can disagree with the artifact.

**The negative control is the one that proves it.** Keep one DEV-signed `.swu`
from before the switch and try to install it on a production-keyed unit through
the console. It must be **refused**. A unit that accepts both would mean the DEV
certificate survived into the bundle, and nothing in the build would have said
so. Ten minutes on the bench, and it is the leg worth adding to the next bench
session.

Then the positive: install the production-signed `.swu`, confirm the A/B swap
and that the health check marks the slot successful.

---

## Open items this runbook exposes

Small, and all of them cheap next to what they guard:

1. **Nothing mechanically refuses to ship a DEV-keyed image.** `./build.sh swu`
   warns and continues; `archive-release.sh` does not look at the trust store;
   none of the seven gates on the release line does either. The gate that
   closes it is ~20 lines — fail if the staged bundle carries
   `NOT FOR SHIPMENT` — and the window it guards is open *now*, which is the
   only period in which it can be exercised by accident.
2. **`docs/compliance/signing-log.md` is printed by two scripts and does not
   exist.** Create it with the ceremony.
3. **No guard against committing a private key.** The ceremony is the first
   moment a private key is ever near this tree.

## If it goes wrong

- **Passphrase mistyped or forgotten, before the shred** — re-run the ceremony.
  Nothing has shipped; the cost is an hour.
- **A stick fails later** — there are four copies. Replace it, log it, change
  the passphrase at the next signing (A.3).
- **A key or its passphrase is suspected compromised, after units ship** — that
  is A.5, not this file: rotate to the standby key with a signed update. It
  works because both public halves shipped in every image from the first unit,
  which is the whole reason the ceremony generates two keys and not one.
