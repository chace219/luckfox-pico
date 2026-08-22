# CRA: what is left, and who owns it

*Written 2026-08-23 for product management and legal. The engineering detail
lives in [`cra-compliance-plan.md`](cra-compliance-plan.md), which is 4,300
lines and assumes you know the codebase. This page is the same position in
plain language: what is still open, who has to move it, and what happens if
nobody does.*

---

## Where we stand

The Cyber Resilience Act asks for two things. **Annex I Part I** is eight
security properties the product itself must have. **Annex I Part II** is a
process for handling vulnerabilities after it ships.

**All eight product properties are met.** Secure defaults, no known
unaddressed vulnerabilities at shipment, protected data, a minimised attack
surface, access control, security logging, a signed update mechanism and
factory reset — each is implemented and each has been demonstrated on real
hardware rather than only in a test suite.

**The process side is four-fifths there.** We can produce a bill of materials
for every release, we check every release against public vulnerability
databases, and we have a written disclosure policy. What is missing is a
working mailbox, a signing-key ceremony, and a lawyer's sign-off.

None of what remains is a coding problem. That is the headline.

---

## 1. The one hard deadline: 11 September 2026

**Nineteen days from today**, EU vulnerability-reporting obligations begin —
and they apply to units already in the field, not only to new ones. From that
date, a security researcher who finds a problem in our product must have a
published way to tell us, and we must be able to receive it.

Everything engineering owes here is finished. The address is printed in both
product manuals, in the on-device help and in the customer PDFs. The files that
go on the website are written and validated and waiting.

**What is left is three steps, and the order matters:**

1. **Create the `security@joralllc.com` mailbox** as a Workspace group —
   product management plus at least one engineer, so a report is never sitting
   in one person's inbox while they are on holiday.
2. **Then** publish the two prepared files to joralllc.com.
3. **Then** confirm from outside the company that mail to the address arrives.

**Do not do step 2 before step 1.** A researcher who writes to a published
address and hears nothing concludes we do not answer — and what they typically
do next is publish the vulnerability instead of reporting it. An advertised
dead mailbox is worse than no mailbox.

**Owner: product management.** Effort: under an hour, plus a web upload.

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
| **Broker-authenticated MQTT test** | The only outstanding test that needs equipment we do not have set up — a message broker whose credentials we control |
| **Two small bench checks** | One replay test and one log check, each about ten minutes on a unit; neither gates anything |
| **First automated fuzzing run** | Automated attack-input testing now runs nightly, but the first full run has not happened yet. The weaker version of it has, with nothing found |
| **Scheduled hardware testing** | Bench sessions are still arranged by hand rather than on a calendar. Every serious defect this programme has found came from running the product, not from reading it, so this is worth formalising |
| **Fifteen unbooted board variants** | The build offers sixteen hardware profiles; all are hardened and checked automatically, but only one has ever been switched on here. We do not have the other boards |
| **Two component reviews due 9 November** | Two known issues in a scripting language we ship are accepted risks with a documented reason and a review date the build enforces. Two closed-source vendor components carry the same treatment |

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

1. **This week:** create the security mailbox, publish the two files, confirm
   from outside. *That is the deadline; nothing else is.*
2. **Same meeting:** sign the signing policy, confirm the five-year support
   period, start the legal review, answer the two product questions.
3. **Before first shipment:** hold the key ceremony.

One conversation covers items 2 and 3 of that list. Only the first is bound to
a date.
