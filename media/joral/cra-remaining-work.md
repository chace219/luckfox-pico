# CRA: what is left, and who owns it

*Written 2026-08-23 for product management and legal; **revised 2026-08-25**, when
§1 turned out to name the wrong obligation — see the note in that section.*

*The engineering detail lives in [`cra-compliance-plan.md`](cra-compliance-plan.md),
which is 4,300 lines and assumes you know the codebase. This page is the same position in
plain language: what is still open, who has to move it, and what happens if
nobody does.*

---

## Where we stand

The Cyber Resilience Act asks for three things. **Annex I Part I** is eight
security properties the product itself must have. **Annex I Part II** is a
process for handling vulnerabilities after it ships. Both of those are due
**11 December 2027**. **Article 14** is a duty to report actively exploited
vulnerabilities and severe incidents to the authorities on a 24-hour clock, and
it is due **11 September 2026** — that is the one date on this page.

**All eight product properties are met.** *(One of them briefly was not: an
OpenSSL patch release on 25 August exposed three findings, caught and fixed
the same day it was checked, 29 August — see §3.)* Secure defaults, no known
unaddressed vulnerabilities at shipment, protected data, a minimised attack
surface, access control, security logging, a signed update mechanism and
factory reset — each is implemented and each has been demonstrated on real
hardware rather than only in a test suite.

**The process side is four-fifths there.** We can produce a bill of materials
for every release, we check every release against public vulnerability
databases, and we have a written disclosure policy. What is missing is a
working mailbox, a named person to answer it on a clock, a signing-key
ceremony, and a lawyer's sign-off.

None of what remains is a coding problem. That is the headline.

---

## 1. The one hard deadline: 11 September 2026

**Seventeen days from today**, our reporting obligations begin — and they apply
to units already in the field, not only to new ones.

> **Corrected 2026-08-25.** This section previously said the September date was
> when *"a researcher must have a published way to tell us"*. That duty exists, but
> it is part of the Annex I requirements and lands on **11 December 2027**. What
> lands on **11 September 2026** is the opposite direction: **we** must report to
> the authorities.

From 11 September, if a vulnerability in our product is being **actively exploited**,
or a **severe security incident** occurs, we must tell the EU agency ENISA and a
national cyber-incident team, through an EU reporting platform, on a fixed clock:

| | |
|---|---|
| **Within 24 hours** | An early warning — from the moment we *become aware*, not from the moment we understand it, reproduce it, or have a fix. A short notice that something is being exploited is enough, and is required |
| **Within 72 hours** | A fuller notification: the product, the nature of the exploit, and any mitigation available or advised |
| **Within 14 days** | The final report, once a corrective measure exists (one month for an incident) |

There is a fourth duty in the same hours that is easy to miss: **we must also tell
affected customers**, and if we do not do it in reasonable time, the authorities may
tell them for us.

### Why this one is not negotiable

- **It is a regulation, not a directive** — directly binding in every member state,
  with no national implementation to wait for and no grace period after the date.
- **It reaches backwards.** Units we have already sold into the EU are inside it.
  Contract status and warranty state make no difference.
- **We do not control the trigger.** We do not choose when someone exploits a
  vulnerability, or when they tell us they have. The 24-hour clock starts at whatever
  hour we find out.
- **Enforcement runs to withdrawal from the market**, and breaches of these
  obligations sit in the regulation's top fine band. The figure is one for counsel to
  confirm rather than take from a memo; the order of magnitude is existential for a
  company our size.
- **The failure is visible in the worst setting.** A missing CE mark is found in an
  audit. A missed 24-hour report is found in the middle of a live exploitation event,
  in front of the customer it affects.

### The mailbox: necessary, and not sufficient

Everything engineering owes here is finished. The address is printed in both
product manuals, in the on-device help and in the customer PDFs. The files that
go on the website are written and validated and waiting.

The mailbox is not itself the September obligation. It is the **tripwire that makes
the obligation performable**: the realistic way a manufacturer our size first learns
that a vulnerability in its fielded units is being exploited is that somebody writes
in and says so. A 24-hour clock we cannot hear start is a 24-hour clock we miss. So
it stays the first thing to do — but it closes the channel and nothing else.

**What is left is three steps, and the order matters:**

1. **Create the `security@joralllc.com` mailbox** as a Workspace group —
   product management plus at least one engineer, so a report is never sitting
   in one person's inbox while they are on holiday.
2. **Then** publish the two prepared files to joralllc.com.
3. **Then** confirm from outside the company that mail to the address arrives.

**Do not do step 2 before step 1.** A researcher who writes to a published
address and hears nothing concludes we do not answer — and what they typically
do next is publish the vulnerability instead of reporting it. An advertised
dead mailbox is worse than no mailbox — and after 11 September it converts a
private report into a public zero-day with a 24-hour clock already running.

**Owner: product management.** Effort: under an hour, plus a web upload.

### Five more things, before the same date

Each is a decision or an errand. None needs engineering time.

1. **Name a duty officer and a deputy.** *Product management.* A 24-hour clock needs
   a person, not a group: who reads the mailbox each working day, who covers holidays
   and weekends, and who may file the early warning **without waiting for Carl**. The
   early warning commits us to no finding — it says we are aware and looking — so
   gating it on one person's availability is the single most likely way we miss it.
2. **Establish which national team we report to.** *Legal.* Reports go to ENISA *and*
   to the cyber-incident team of the country where the manufacturer is established in
   the EU — or where its EU authorised representative is, for a manufacturer based
   outside it. We are a US company, so counsel needs to tell us which one that is and
   whether an authorised representative is required or advisable. **This is the only
   item whose duration we do not control. Start it first.**
3. **Get access to the reporting platform before we need it.** *Product management.*
   Whatever registration it requires, do it in a quiet week. Nobody should be creating
   a login for the first time inside a 24-hour window.
4. **Draft the two notices now.** *Product management.* A fill-in-the-blanks early
   warning, and a customer notice for the duty to inform affected users. Twenty
   minutes of writing now, an hour we will not have later. The customer notice needs a
   distribution list — who we email when a fielded unit is affected — which we should
   confirm exists. **Drafted 2026-08-28:** both notices and the distribution-list
   checklist are in [`disclosure/art14/`](disclosure/art14/). What is left is filling
   the two counsel fields, and the test mail to every address on the list.
   **Position on 2026-08-28: no unit has been placed on the EU market and no
   incident has occurred** — so the clock has nothing to attach to on 11 September
   and attaches at first shipment instead. The binding date for every item in this
   section is therefore *before unit one*; 11 September is only the day after which
   unit one carries the duty with it.
5. **Run one 30-minute drill before 11 September.** *Product management and one
   engineer.* Send a fabricated report to the new mailbox and walk it end to end: who
   saw it, how fast, which builds are affected, what the early warning would say, who
   signs it, who tells the customer. Every serious defect this programme has found
   came from running something rather than reading it; this is that principle applied
   to the process instead of the product.

**What makes this cheap for us**, and it was deliberate: every release carries a bill
of materials tied to its build identifier and cross-checked against the vulnerability
report, so *"which builds are affected?"* has an answer in the first hour rather than
after an investigation; and the signed update path is proven on hardware, so *"a
corrective measure is available"* is reachable inside the 14 days — once the key
ceremony in §2a has happened.

---

## 2. Four decisions, one meeting

None of these is date-bound the way the mailbox is, but the first two **block
first customer shipment**. They fit in a single conversation.

### a. Sign the firmware signing policy, and hold the key ceremony
**Owner: Carl. Effort: a signature and about an hour.**

The product accepts firmware updates only if they are correctly signed — that
part works and has been proven on hardware. But today it signs with a
**development key** that lives in a working directory rather than in custody.
Shipping a unit that trusts a development key would mean shipping a unit whose
update mechanism we cannot vouch for.

The procedure is drafted and ready to sign, including what to do if a key is
ever compromised. Nothing else is waiting on it. **No customer unit can ship
until this happens.**

### b. Confirm the support period
**Owner: Carl. Same meeting.**

The CRA requires us to state, publicly, how long we will provide security
updates. The drafted answer is **five years** with a published end date. It
needs a decision rather than a discussion — it is in the same memo as the
signing policy.

One thing worth knowing before signing: no version of the underlying operating
system we can build on today is supported for a full five years by its own
upstream. That is a property of the hardware platform, not a mistake in our
plan. The defensible position — and the one the regulation actually asks for —
is a written plan for moving to a newer base, plus evidence we can do it. We
have both; we performed exactly that move this month.

### c. Legal review of the end-user licence
**Owner: legal.**

Three things: counsel needs to review the EULA, one jurisdiction placeholder in
it needs filling in, and we need to confirm the **`support@joralllc.com`**
address it directs customers to actually exists. That last one is the same
failure as the security mailbox, so it belongs in the same conversation.

### d. Two product questions engineering cannot answer alone
**Owner: product management.**

- **Should the audit log be sent off the device?** Every unit keeps a durable
  local record of logins, failures and configuration changes. Whether it should
  also push that to a central collector is a deployment decision — both designs
  are written up, and either is a small piece of work once chosen.
- **Should a nonsensical sensor scaling be rejected?** A hand-edited
  configuration file can currently contain a scaling factor that produces
  meaningless readings. Nothing crashes; the readings are simply not numbers.
  Whether to refuse such a file at import is a product call. It is a one-line
  change either way.

---

## 3. What engineering still has open

Nothing here blocks shipment, and nothing needs a decision from outside the
team. Listed so the picture is complete rather than flattering.

| | What it is |
|---|---|
| ~~**OpenSSL security patch**~~ | **Closed 29 Aug**, same day it was found. A patch release (3.5.8, 25 August) fixed three findings in the cryptography library under every encrypted connection — none reachable on our units, but worth taking rather than triaging. Rebuilt, verified, all release checks pass. What is still open is a short hardware session to re-touch the TLS surfaces, folded into the MQTT bench work below |
| **Broker-authenticated MQTT test** | The only outstanding test that needs equipment we do not have set up — a message broker whose credentials we control |
| **Two small bench checks** | One replay test and one log check, each about ten minutes on a unit; neither gates anything |
| ~~**First automated fuzzing run**~~ | **Done — confirmed 2026-08-29.** Automated attack-input testing has run every night since 23 August on both products, roughly 150–230 million inputs a night, with nothing found. The inputs it discovered are now kept with the code, so every later test run covers them |
| ~~**Scheduled hardware testing**~~ | **Written down 2026-08-29** — `release-build-runbook.md`'s new "Standing bench and review cadence" section: a monthly CVE-gate + security.txt check, the dated `REVIEW_BY` table for every accepted-risk row (next: 9 November), and a nightly-fuzz health check. Still needs an actual calendar entry from product management — a paragraph in a runbook does not fire a reminder by itself |
| **Fifteen unbooted board variants** | The build offers sixteen hardware profiles; all are hardened and checked automatically, but only one has ever been switched on here. We do not have the other boards |
| **Two component reviews due 9 November** | One known issue in a scripting language we ship is an accepted risk *(two until 29 August, when the vulnerability database confirmed our version fixed the other)* with a documented reason and a review date the build enforces. Two closed-source vendor components carry the same treatment |

---

## 4. Known limits to state, not to fix

These are properties of the product, not gaps. They belong in the technical
file, stated plainly, so that an assessor reads them from us rather than
discovering them:

- **First connection to a unit trusts a certificate the unit made itself.** The
  operator confirms a fingerprint out of band. This is normal for equipment on
  an isolated control network.
- **Stored passwords are encrypted and locked to the individual board**, so the
  file is inert if copied elsewhere. It does not protect a running unit against
  someone who already has administrative access — the hardware has no secure
  element, and no design choice changes that.
- **One industrial protocol port carries no authentication**, because the
  protocol itself does not define any. This is why the deployment assumption of
  an isolated machine-control network is written into the compliance file
  rather than left implied.
- **Timestamps before a unit's first internet time sync read as 2021.** Ordering
  is still correct; only the clock is wrong, and only until the unit syncs.
- **The operating system base will be replaced at least once** inside the
  support period. See §2b.

---

## 5. Not engineering's, and not on this list

CE marking, business classification and the EU Declaration of Conformity are
product and legal matters. Engineering's job is to make sure every fact those
documents rest on is true and demonstrable, which is what
`cra-compliance-plan.md` exists to prove.

---

## The shortest path from here

1. **Today:** mail counsel the reporting-routing question (§1, item 2). It is the
   only piece whose duration we do not control, so it goes first even though it is
   the least visible.
2. **This week:** create the security mailbox, publish the two files, confirm from
   outside — and name the duty officer and deputy in the same message.
3. **Same meeting:** sign the signing policy, confirm the five-year support
   period, start the legal review, answer the two product questions.
4. **By 4 September:** platform access obtained, both notices drafted, customer
   distribution list confirmed.
5. **By 9 September:** run the drill. Fix what it exposes — it will expose
   something, and two days of margin is the point.
6. **Before first shipment:** hold the key ceremony.

Steps 1, 2, 4 and 5 are bound to 11 September. Step 3 and the key ceremony are not
— they block first customer shipment, which is a different constraint, and they are
one conversation rather than three.

Nothing should happen on 11 September. That is the objective.
