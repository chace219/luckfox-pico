# Article 14 report — early warning, notification, final report

*Fill §A within **24 hours** of T0. §B within **72 hours**. §C within **14 days**
of a corrective or mitigating measure being available (**one month** after §B
for a severe incident). File each through the EU single reporting platform to
ENISA and the coordinating CSIRT. Keep this file as the case record.*

*Status 28 Aug 2026: no case open, no unit on the EU market. First case will be `JORAL-A14-2026-001`.*

*Everything in `[[double brackets]]` is filled on the day. Everything else is
already decided. Delete a line only if it does not apply — leave nothing
blank that you could answer with "not yet known".*

---

## Case header

| Field | Entry |
|---|---|
| Case ID | `JORAL-A14-[[YYYY]]-[[NNN]]` |
| **T0 — moment of awareness** | `[[YYYY-MM-DD HH:MM UTC]]` — **write this down first** |
| How we became aware | `[[ report to security@joralllc.com / own monitoring / customer / CSIRT / public disclosure ]]` |
| Reporter (if any) | `[[ name, organisation, contact — internal only; not sent ]]` |
| Type | `[[ actively exploited vulnerability ]]` **or** `[[ severe incident ]]` |
| Duty officer filing | `[[ name ]]` (deputy: `[[ name ]]`) |
| §A due | T0 + 24 h = `[[ ]]` |
| §B due | T0 + 72 h = `[[ ]]` |
| §C due | `[[ fix-available date ]]` + 14 d (or §B + 1 month for an incident) |

**Which is it?** *Actively exploited vulnerability*: there is evidence someone
is using a weakness in our product against a real unit. *Severe incident*:
something has happened that affects, or could affect, the product's ability to
protect the availability, authenticity, integrity or confidentiality of
sensitive data or functions — or that has led, or could lead, to malicious code
running in the product or the systems it is connected to. If in doubt, file as
whichever fits better and say it is provisional; correcting at §B is allowed.

---

## §A — Early warning (≤ 24 h)

*This is deliberately short. It commits Joral to no finding.*

**Manufacturer**

Joral LLC, `[[ registered address ]]`, USA.  
Authorised representative in the Union: `[[ name / address — from counsel, or "none appointed" ]]`.  
Contact for this report: security@joralllc.com, `[[ duty officer name, phone ]]`.

**Product(s) with digital elements concerned**

`[[ SATISense™ Industrial Edge Platform (IE-460) | 10BASE-T1S Media Gateway | both ]]`  
Firmware builds believed affected: `[[ build IDs, or "under assessment" ]]`.

**Nature**

`[[ one or two sentences: what we have been told or observed, at the level of
"a report indicates a fielded unit's web console can be reached without
credentials and is being used to alter configuration". No exploit detail. ]]`

**Member States on whose territory we are aware the product has been made available**

`[[ list — from distribution-list.md, column "Member State" ]]`
*(Required by Art. 14(2)(a) / 14(4)(a). If the list is incomplete say
"at least:" and name what we know.)*

**For a severe incident only — is it suspected to be caused by unlawful or malicious acts?**

`[[ yes / no / unknown at this time ]]`

**Status**

Joral became aware at `[[T0]]`. Assessment is under way. A notification with
further detail will follow within 72 hours of awareness.

**Sensitivity**

Joral considers this report sensitive. Please do not disseminate beyond the
CSIRT network and ENISA until the corrective measure has been published.
`[[ counsel may adjust the wording ]]`

---

## §B — Notification (≤ 72 h) — *unless already provided in §A*

**Product concerned — general information**

Product: `[[ ]]` — Model: `[[ IE-460 / Media Gateway ]]`  
Affected firmware builds: `[[ build IDs from the SBOM / CVE-gate lookup ]]`  
Unaffected builds: `[[ build IDs ]]`  
Estimated units in the field on affected builds, by Member State: `[[ from distribution-list.md ]]`

**General nature of the vulnerability / incident**

`[[ component, weakness class (e.g. authentication bypass, memory corruption
in <daemon>), attack vector (network / adjacent / local / physical), whether
authentication is needed, what an attacker gains. CVE ID if one exists. ]]`

**General nature of the exploit** *(vulnerability)* / **initial assessment** *(incident)*

`[[ what is being done with it in the field, as far as known; whether it is
targeted or opportunistic; what we have seen ourselves ]]`

**Corrective or mitigating measures taken by Joral**

`[[ e.g. fix in development, target build ID; affected customers notified on
<date>; reporter engaged; none yet ]]`

**Corrective or mitigating measures users can take**

`[[ the same text that goes in customer-notice.md — keep them identical:
e.g. restrict console access to the management VLAN; disable <feature>;
apply build <id> when available; power the unit down if <condition> ]]`

**Sensitivity**

`[[ as §A, or updated ]]`

---

## §C — Final report (≤ 14 d after fix available; ≤ 1 month after §B for an incident)

*Vulnerability — Art. 14(2)(c):*

1. **Description of the vulnerability, severity and impact**
   `[[ full description; CVSS vector and score; CVE ID; affected builds; what
   an attacker could and could not do ]]`
2. **Information on any malicious actor that has exploited or is exploiting it, where available**
   `[[ what we know, what the reporter or CSIRT told us, or "none available" ]]`
3. **The security update or other corrective measures made available**
   `[[ fixed build ID; date published; how it is distributed (signed A/B
   update via Joral support/integration contact); fix-note reference; any
   residual mitigation for units that cannot be updated ]]`

*Severe incident — Art. 14(4)(c):*

1. **Detailed description of the incident, severity and impact** `[[ ]]`
2. **Type of threat or root cause likely to have triggered it** `[[ ]]`
3. **Applied and ongoing mitigation measures** `[[ ]]`

---

## Filing log

| When (UTC) | What | By | Platform reference |
|---|---|---|---|
| `[[ ]]` | §A filed | `[[ ]]` | `[[ ]]` |
| `[[ ]]` | Customer notice sent to `[[ N ]]` addresses | `[[ ]]` | — |
| `[[ ]]` | §B filed | `[[ ]]` | `[[ ]]` |
| `[[ ]]` | Corrective measure available (build `[[ ]]`) | `[[ ]]` | — |
| `[[ ]]` | §C filed | `[[ ]]` | `[[ ]]` |
