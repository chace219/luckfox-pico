# Security notice to affected users — Art. 14(8)

*Send to every contact on `distribution-list.md` whose units are on an
affected build — and, where the risk warrants it, to all users. Send it no
later than the 72-hour notification; earlier if there is a mitigation they can
apply now. If we do not inform users in a timely way, the coordinating CSIRT
may do it for us, in its own words.*

*Plain email, from security@joralllc.com, signed by a named person. One
notice per case; updates reuse the same subject with "UPDATE" prefixed.
The mitigation text must be identical to what we filed in §B of the report.*

---

**Subject:** `[[ Security notice JORAL-A14-YYYY-NNN ]]` — `[[ product ]]` — action `[[ required / recommended / none yet ]]`

Dear `[[ customer / integration contact ]]`,

Joral is writing to inform you of a security `[[ vulnerability / incident ]]`
affecting the `[[ SATISense™ Industrial Edge Platform (IE-460) / 10BASE-T1S
Media Gateway ]]`. Our records indicate that you have `[[ N ]]` unit(s) on an
affected firmware build. We are required by EU law to tell you, and we would
tell you anyway.

**What is affected**

| Field | Entry |
|---|---|
| Product | `[[ ]]` |
| Affected firmware builds | `[[ build IDs ]]` |
| Not affected | `[[ build IDs, or "builds from <id> onwards" ]]` |
| Your units, as far as we know | `[[ serial numbers, if recorded ]]` |

To check a unit's build: it is shown in the web-console header as `fw <id>`,
by `[[ intelligence_edge_opcua / media-gateway ]] --version`, and in the
startup log.

**What the issue is**

`[[ Two or three plain sentences. What an attacker with what access could do.
No exploit detail. Say whether it is being actively exploited — the
regulation applies because it is, and the customer deserves to know. ]]`

**What we ask you to do now**

*Numbered, concrete, in the order that reduces risk fastest. If there is
nothing they can do yet, say exactly that: "There is no action you can take at
this time; a corrective update is expected by `[[ date ]]`." Example:*

1. Confirm the unit's management interface is reachable only from your
   engineering/management VLAN and not from the machine network or any routed
   segment.
2. Disable `[[ feature ]]` in Settings → `[[ page ]]` until the update is
   applied.
3. Check `[[ log / audit log ]]` for `[[ indicator ]]`; if present, contact us
   at the address below before doing anything else.

**What Joral is doing**

`[[ A corrective firmware update (build ‹id›) is ‹in development / available
from ‹date››. It is supplied free of charge through your Joral support or
integration contact and is installed through the unit's signed update path.
We will send an UPDATE to this notice when it is available. ]]`

**Contact**

security@joralllc.com — reference `[[ case ID ]]` in the subject. If you have
observed anything on your units that you believe is related, please tell us;
it helps us and it helps other users.

`[[ Name ]]`  
`[[ Title ]]`, Joral LLC  
`[[ date ]]`

---

## Optional machine-readable block

*Art. 14(8) says "where appropriate in a structured, machine-readable format".
For a customer with an asset-management system, append this. It is not a
CSAF advisory — that comes when we issue the first real one — but every field
in it is one we already hold.*

```json
{
  "notice_id": "[[ JORAL-A14-YYYY-NNN ]]",
  "issued": "[[ YYYY-MM-DDTHH:MM:SSZ ]]",
  "vendor": "Joral LLC",
  "product": "[[ IE-460 | media-gateway ]]",
  "affected_builds": ["[[ build-id ]]"],
  "fixed_builds": ["[[ build-id ]]"],
  "actively_exploited": [[ true | false ]],
  "cve": ["[[ CVE-YYYY-NNNNN ]]"],
  "severity": "[[ critical | high | medium | low ]]",
  "action_required": [[ true | false ]],
  "contact": "security@joralllc.com"
}
```

## Before sending — the duty officer checks

- [ ] Mitigation text is word-for-word what §B of the report says.
- [ ] No exploit detail, no reporter's name, no internal case notes.
- [ ] Every recipient is on `distribution-list.md` with an affected build,
      or the notice is deliberately going to all users and PM has agreed.
- [ ] Sent from security@joralllc.com, not a personal address, so replies
      land where the deputy can see them.
- [ ] Time of sending entered in the filing log of `early-warning.md`.
