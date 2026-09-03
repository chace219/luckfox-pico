# Article 14 notices — ready to fill

*Regulation (EU) 2024/2847, Article 14. Duty begins **11 September 2026**.*

This directory holds the two notices that Article 14 makes us write under a
clock, drafted now so that on the day nobody is composing prose. It also holds
the checklist that tells us whether we *can* send the second one — a customer
notice is only as good as the list it goes to.

## Where Joral stands — 28 August 2026

**No unit has been placed on the EU market, and no incident has occurred.**
That matters for how alarmed to be, and it changes nothing on this page:

- The Article 14 duty attaches to products *placed on the Union market*. With
  nothing shipped, the 24-hour clock has nothing to attach to on 11 September.
  It attaches **the moment the first unit ships** — and from that moment the
  law is already in force, with no run-up.
- So the binding date for this pack is **first shipment**, and 11 September
  is simply the day after which first shipment carries the duty with it. The
  mailbox, the duty officer, the platform login and the drill all have to
  exist *before unit one*, not before 11 September.
- The distribution list is empty today. That makes it trivially "confirmed"
  — and makes the shipping checklist the place where it stops being empty.
- No case has been opened. Case numbering starts at `JORAL-A14-2026-001`.

| File | What it is | Who fills it | Clock |
|---|---|---|---|
| [`early-warning.md`](early-warning.md) | The 24-hour early warning to ENISA + the coordinating CSIRT, with the 72-hour notification and final-report fields underneath so the same file grows into all three | Duty officer | 24 h / 72 h / 14 d (1 month for an incident) |
| [`customer-notice.md`](customer-notice.md) | The Art. 14(8) notice to affected users | Duty officer, PM signs | "Timely" — target: with or before the 72-hour notification |
| [`distribution-list.md`](distribution-list.md) | What the customer list has to contain, where the data comes from, and what "confirmed" means | Product management | Before first shipment, then per shipment |

## How the three fit together

```
somebody writes to security@joralllc.com  (or: we see it ourselves)
        │
        ▼  T0 = the moment we become AWARE — log it, do not wait to understand it
        │
  ┌─────┴──────────────────────────────────────────────────────────┐
  │  ≤ 24 h   early-warning.md §A   → single reporting platform    │
  │  ≤ 72 h   early-warning.md §B   → same platform, same case     │
  │           customer-notice.md    → distribution-list.md         │
  │  ≤ 14 d   early-warning.md §C   → after the fix is available   │
  │           (1 month for a severe incident)                       │
  └────────────────────────────────────────────────────────────────┘
```

Three things to hold onto on the day:

1. **T0 is awareness, not understanding.** A credible report that a fielded
   unit is being exploited starts the clock. Reproducing it, confirming it, or
   having a fix are all things we do *inside* the 24 hours, not before them.
2. **The early warning commits us to nothing.** It says "we are aware, we are
   looking, these are the member states we know units are in". It is
   deliberately thin. Sending a thin one on time beats a complete one late,
   and the regulation says so ("unless already provided" at each later stage).
3. **The duty officer files it without waiting for anyone.** That authority is
   decision 3 on Carl's list. If it has not been given, this directory does not
   help.

## What is engineering's, and already in place

- **Which builds are affected** — every release ships with an SBOM keyed by
  build identifier and a CVE-gate report (`./build.sh cve`,
  `scripts/compliance/cve-check.py`). Given a component name or CVE, the
  affected build IDs are a lookup, not an investigation. The build ID is shown
  in the web-console header, by `<daemon> --version`, and in the startup log.
- **"A corrective measure is available"** — the signed A/B update path. The
  14-day final-report window starts from that moment, and the path exists.
  It needs the key ceremony to have happened for the signature to mean
  anything (Carl's decision 4).

## Two things counsel decides, and this directory leaves blank

- **Which CSIRT.** For a manufacturer with no main establishment in the Union
  the coordinator follows the authorised representative, and failing one, the
  importer / distributor chain. The template has a field; counsel fills it
  once and it stays filled.
- **How sensitive the report is.** Art. 14 lets us say. The default in the
  template is *"sensitive — do not disclose beyond the CSIRT network until the
  corrective measure is published"*. Counsel may want different words.

## Before first shipment (and in any case before 11 September)

- [ ] Duty officer and deputy named, with authority to file §A unaided.
- [ ] CSIRT and authorised-representative fields filled by counsel.
- [ ] Platform account exists; someone has logged in and seen the form.
      **The platform's own form wins over this template's structure** — the
      value of the template is that every answer is already known.
- [ ] `distribution-list.md` checklist complete: a list exists, it has the
      fields, and a test mail reached every address on it.
- [ ] One drill: a fabricated report, T0 logged, §A filled and read aloud,
      affected builds looked up, `customer-notice.md` filled and sent to an
      internal address. Thirty minutes. Note what was slow.

## Rebuilding the PDF

`../../cra-article-14-notice-pack.pdf` is the reading copy of these four files
in Joral's house style (palette and fonts taken from joralllc.com). To
regenerate after editing the Markdown, from `media/joral/`:

```sh
npm i --no-save marked@12
node disclosure/art14/build-pack.mjs        # writes cra-article-14-notice-pack.html
google-chrome --headless=new --no-pdf-header-footer --virtual-time-budget=10000 \
  --print-to-pdf="$PWD/cra-article-14-notice-pack.pdf" "file://$PWD/cra-article-14-notice-pack.html"
```
