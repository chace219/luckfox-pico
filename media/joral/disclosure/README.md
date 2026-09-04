# Publishing the disclosure channel

Everything in this directory is written and validated. **None of it is
published**, and publishing it is not an engineering task — it needs a mailbox
and a web server, and both belong to product management.

This file exists so that hand-off is four concrete steps rather than a line item
in a plan.

## The deadline

**11 September 2026.** From that date **Art. 14** of Regulation (EU) 2024/2847
obliges us to report an actively exploited vulnerability, or a severe incident, to
ENISA and the coordinating national CSIRT — 24 h early warning, 72 h notification,
14 d final report — and to tell affected users. It applies to units already in the
field, not only to what we ship next.

*Corrected 2026-08-25: this file previously said the September date obliged us to
**receive** reports. It does not — the duty to publish a channel is Annex I Part II
§5/§6 and applies from 11 Dec 2027. See the dated entry in
[`../cra-compliance-plan.md`](../cra-compliance-plan.md).*

**Publishing this directory does not discharge Art. 14. It is the tripwire that
makes Art. 14 performable** — the realistic way we first learn a fielded unit is
being exploited is that somebody writes in, and a 24-hour clock we cannot hear start
is a 24-hour clock we miss. The rest of Art. 14 — a named duty officer, counsel's
answer on which CSIRT, platform access, two draft notices, one drill — is
remaining-work item 1 in [`../cra-remaining-work.md`](../cra-remaining-work.md) §1,
and none of it is engineering's either.

Nothing here takes an engineering day. What it takes is a decision and an hour.

## What is in this directory

| File | Publish as | Owner |
|---|---|---|
| [`security.txt`](security.txt) | `https://joralllc.com/.well-known/security.txt` | product management + web |
| [`security-policy.md`](security-policy.md) | `https://joralllc.com/security-policy` | product management + web |
| [`art14/`](art14/) | *not published* — the fill-in 24 h / 72 h / 14 d report, the Art. 14(8) customer notice, and the distribution-list checklist, ready for the day | duty officer + product management |

Both are already consistent with what the devices say — each product's
`SECURITY.md`, both user manuals, and the on-device Help generated from them.
`scripts/compliance/test-security-txt.sh` is what keeps them that way.

## Procedure, in this order

The order is load-bearing. Publishing the files before the mailbox exists is
worse than publishing nothing: a researcher who mails a dead address concludes
we do not answer, and the next thing they do is publish.

**1. Create the mailbox — this gates everything else.**

- Google Workspace **group** `security@joralllc.com`, not a personal alias. A
  personal address fails the first time that person is on leave.
- Members: product management **and at least one engineer**. Two people is the
  minimum that survives one absence.
- Alias `psirt@joralllc.com` to the same group. It costs nothing and catches
  reporters who follow PSIRT convention instead of RFC 2142.
- Confirm delivery by sending mail to it from outside the domain.

**2. Publish the two files.**

- `security.txt` at `/.well-known/security.txt`, served over HTTPS as
  `text/plain; charset=utf-8`. Not as an attachment, not redirected to a
  marketing page.
- The policy at exactly `https://joralllc.com/security-policy`, because that is
  the URL `security.txt` names. If the site's structure requires a different
  path, change the `Policy:` field here first and re-run the check.

**3. Verify from outside.**

```sh
curl -sSI https://joralllc.com/.well-known/security.txt   # 200, text/plain
scripts/compliance/test-security-txt.sh --live            # fetches both URLs
```

**4. Record it.**

Move Annex I Part II rows §5 and §6 from **partial** to **met** in both products'
`docs/compliance/cra-annex1-matrix.md`, and close remaining-work item 1 in the
plan with the date. The rows say *partial* today for a precise reason: the
policy is written and the address is in every shipped document, but **until mail
to it is actually received, there is no channel** — and a matrix row that reads
"met" on the strength of a written policy is the exact failure this programme
keeps finding.

Only after step 3 passes may the documents naming the address ship to customers.

## Then, once a year

`security.txt` carries a mandatory `Expires` field, and RFC 9116 makes a lapsed
file **invalid** — a consumer is entitled to ignore it entirely. Nothing
announces that date.

`scripts/compliance/test-security-txt.sh` fails **60 days before** it, so the
renewal surfaces as a build failure while it is still a chore. Re-issue by
moving the date and re-publishing; there is nothing else to do.

The same check also fails if the address in `security.txt` ever stops matching
the address in a shipped manual or on-device Help. That drift is the realistic
long-term failure here — a unit in the field carries whichever address it was
built with, forever.

## Deliberately not published yet

Each of these is a promise, and an unkept one costs more than the omission —
see the comments in [`security.txt`](security.txt):

- **No OpenPGP key** (`Encryption:`). An unattended key is a black hole for
  exactly the reports that most need confidentiality. The policy instead asks
  reporters to flag sensitive material in the first mail.
- **No acknowledgments page** (`Acknowledgments:`). The policy commits to
  crediting reporters in fix notes; add the field when there is a page.
- **No CSAF feed.** Revisit when the first advisory is issued.

## What this does not cover

The **signing-key ceremony** and the **declared support period**
([`../firmware-signing-and-support-policy.md`](../firmware-signing-and-support-policy.md))
are the other two items waiting on the same signature, and no customer unit
should ship on the per-checkout DEV key. Raise them in the same conversation as
the mailbox — it is one meeting, not three.
