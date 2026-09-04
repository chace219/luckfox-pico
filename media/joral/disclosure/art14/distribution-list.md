# Customer distribution list — does one exist?

*The Art. 14(8) notice is only as good as the list it goes to. This page says
what the list has to contain, where each column comes from, and what
"confirmed" means. Owner: product management. Deadline: before the first unit
ships, then maintained per shipment.*

## Today: the list is empty, and that is the correct state

As of 28 August 2026 no unit has been placed on the EU market, so there is
nobody to notify and the list has no rows. The checklist below is therefore
complete by default. What is **not** done is the thing that keeps it true:
the first row has to be written *before* the first unit leaves, which means
the columns below go into the shipping checklist now, while there is nothing
to ship. The test-mail step runs on the first real contact.

## Why it is more than an address book

Two things in the Article 14 report itself come **off this list**, not from
engineering:

- **Member States on whose territory the product has been made available** —
  a mandatory field in the 24-hour early warning. If we cannot answer it from
  a list, we answer it from memory, inside a 24-hour window.
- **Which customers are on an affected build** — the SBOM tells us which
  *builds* are affected; only this list tells us *who has them*.

A sales CRM with company names and a billing contact is not this list. It has
to reach a person who can walk to the unit.

## What each row needs

One row per unit, or per site if serials are not tracked. Minimum:

| Column | Why | Source |
|---|---|---|
| Customer / integrator | who we are notifying | sales |
| **Technical contact — name, email, phone** | the person who can act on the unit, not the buyer | sales / support hand-over |
| Backup contact | the first contact is on holiday when it matters | same |
| **Country of installation (EU Member State or other)** | mandatory early-warning field | shipping address / integrator |
| Site / installation name | so the contact knows which unit we mean | integrator |
| Product & model | IE-460 / Media Gateway | order |
| **Serial number** | ties to a unit | production |
| **Firmware build ID at shipment** | first cut of "is this unit affected" | production — the build ID printed on the unit and shown in the console |
| Firmware build ID now, if known | updated when support learns of an upgrade | support |
| Date placed on the market | first shipment starts the support period and the Art. 14 duty for that unit | shipping |
| Notification consent / channel | some customers require notices via a portal or a named CISO | contract |

The bold columns are the ones the report cannot be filed without.

## Where it lives

One place, two people able to edit it, exportable to CSV in under a minute.
A Workspace sheet shared with the security@ group is enough. It must not live
in a single person's mailbox or a spreadsheet on a laptop, for the same reason
the mailbox must not be one person's inbox.

## What "confirmed" means — the checklist

- [ ] The list exists, at a known location, and the duty officer and deputy
      can both open it.
- [ ] Every unit shipped to date is on it. Cross-check: number of rows against
      units shipped per production records. If they differ, the list is not
      confirmed.
- [ ] Every row has the bold columns filled.
- [ ] **A test message has been sent to every technical-contact address and
      none bounced.** An address nobody has mailed is an address that may not
      exist. Do this from security@joralllc.com so replies prove the mailbox
      works in both directions at the same time.
- [ ] The Member-State column, deduplicated, has been copied into the
      early-warning template's "Member States" line as the standing answer.
- [ ] Someone owns keeping it current: a row is added **before** a unit
      ships, not after. Put it in the shipping checklist.

