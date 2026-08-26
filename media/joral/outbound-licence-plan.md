# Outbound licence and EULA — what is left

*Status as of 2026-08-19: the **engineering** half is done and in both trees.
The licence is **proprietary (`LicenseRef-Joral-Proprietary`)**, applied,
declared to the SBOM, and green through both test suites and `./build.sh
cited`. Everything below is legal or administrative, and three of the four
items are one conversation with Carl.*

The decision, the reasoning and what the pass exposed are recorded once, in the
dated **2026-08-19** entry of [`cra-compliance-plan.md`](cra-compliance-plan.md)
(remaining-work item 7 points at it). This file is only the open list — it
exists so the follow-ups do not live solely in a paragraph of a 2000-line
document, which is how the orphaned-commit and stale-citation problems started.

## The window

MPL §2.1 grants are irrevocable for whatever has already been distributed. The
licence was reversible on 2026-08-19 **only because no customer unit had
shipped**. Everything in this file has the same deadline as that fact: it is
cheap before first customer delivery and expensive after. It shares that door
with the **partition-layout freeze** (`cra-compliance-plan.md` item 11) and the
**signing-key ceremony** — three one-way doors that all shut on the same day.

There is no CRA deadline here. The 11 Sep 2026 obligation is Art. 14 reporting
(and the mailbox that makes it performable), not this.

## Open items

| # | Item | Owner | Blocks |
|---|---|---|---|
| 1 | Counsel review of `EULA.md` | Carl → counsel | first customer shipment |
| 2 | `[[JURISDICTION]]` placeholder in EULA §12 | counsel | item 1 signing off |
| 3 | Confirm `support@joralllc.com` exists | Carl | shipping the docs |
| 4 | Decide how the EULA reaches the customer | Carl → engineering | first customer shipment |

### 1. Counsel review of `EULA.md`

`EULA.md` is drafted **from the facts in these trees** — the signed-update
mechanism, the declared support period, the isolated-network deployment
assumption, the third-party stack — not from a template a lawyer has approved.
That makes it accurate about the product and unreviewed as a contract.

Clauses worth pointing counsel at specifically, because each one encodes a
decision made elsewhere in this programme and will be wrong if that decision
moves:

- **§5 support period** must stay consistent with
  [`firmware-signing-and-support-policy.md`](firmware-signing-and-support-policy.md)
  (drafted at 5 years with a published end date). Two documents, one number.
- **§6** states that the §3.4 reverse-engineering restriction does **not** bar
  good-faith security research or vulnerability reporting. Without it the EULA
  contradicts `SECURITY.md` in both trees, and a coordinated-disclosure policy
  that a licence agreement forbids you to act on is not a policy.
- **§7** is the **written offer for source** covering the GPL/LGPL/MPL platform
  components. This obligation was always ours and is untouched by going
  proprietary. Three years from receipt of the unit; check the term and the
  "any third party in possession of the object code" wording against the
  GPL-2.0 §3(b) text counsel prefers.
- **§9** carries the deployment assumption (isolated machine-control network,
  not for life-support/nuclear/aviation) and **§10** the liability cap at the
  purchase price.
- **§12** says mandatory law prevails, naming Regulation (EU) 2024/2847
  explicitly. Keep that: a CRA-regulated product whose EULA appears to contract
  out of CRA duties is a worse position than having no EULA.

### 2. Governing law

EULA §12 contains a literal `[[JURISDICTION — to be confirmed by counsel]]`.
It was left visible rather than guessed, because a wrong jurisdiction in a
signed agreement is harder to undo than a blank one. Fill it during item 1.

### 3. `support@joralllc.com`

EULA §7 directs source-code requests to `support@joralllc.com`. **Nobody has
confirmed that mailbox exists.**

This is the same failure mode as `security@joralllc.com`, which has been
printed in both user manuals, both on-device Help sets, the customer PDFs and
both `SECURITY.md` files since 2026-08-09 and still has no mailbox behind it
(`cra-compliance-plan.md` item 1). Raise both in one conversation; the fix is
the same Workspace group ticket.

Acceptance: mail sent to the address is received by a human, tested once.

### 4. How the EULA reaches the customer

Today `EULA.md` exists only in the source trees. Neither product manual has a
legal section. Options, cheapest first:

- **a.** A "Legal and licensing" section in each user manual pointing at the
  EULA and the §7 source offer. Costs a docs pass plus PDF and on-device Help
  regeneration (`/help-docs`).
- **b.** As (a), plus the EULA served from the console's Help so a unit carries
  its own terms.
- **c.** Paper insert / distributor packet, product-management owned.

(a) is the minimum that makes the written offer discoverable by someone who has
a unit and no repository access — which is the whole population the offer is
for. Do it in the same pass as the support-period end date, which the manuals
also do not yet state.

## Invariants to keep

Two things must move **together**, or the SBOM misdescribes our own components
— an Annex I Part II §1 defect, not a cosmetic one:

1. the `SPDX-License-Identifier` on every first-party file, and
2. the `LICENSE` column of each tree's `docs/compliance/app-manifest.csv`.

Both are produced by `scripts/compliance/apply-license-headers.sh` and the
manifest is hand-maintained beside it. Changing the licence again is one
substitution of `SPDX=` in that script plus the manifest rows plus `LICENSE`
and `EULA.md` — that is the whole mechanism, and it has now been exercised
twice.

**A vendored file carries somebody else's notice.** The 2026-08-16 pass stamped
`satisense-edge/core/ai/rknn_api.h` — Rockchip's confidential header — with our
tag, contradicting our own SBOM row for the same file. It is excluded by path
in `is_excluded()` now. Any new vendored source needs the same exclusion before
the script next runs.

## Done, for reference

- `LICENSE` + `EULA.md` in both trees; 43 + 148 files retagged, line counts
  unchanged so no compliance citation moved.
- `app-manifest.csv` first-party rows; both READMEs; an **Outbound licensing**
  section in *both* Annex I matrices (satisense previously had no statement of
  its outbound licence anywhere in its matrix, which is why the `GPL-2.0+`
  drift survived as long as it did).
- Verified: both `make test` suites green, SBOM regenerated at 52 platform + 8
  application components with **zero UNDECLARED**, `./build.sh cited` 21/0.
