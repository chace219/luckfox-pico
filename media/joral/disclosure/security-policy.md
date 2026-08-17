# Security Policy — Joral LLC

*Publish at `https://joralllc.com/security-policy` — the URL
`/.well-known/security.txt` names in its `Policy:` field.*

Joral takes the security of its products seriously and welcomes coordinated
disclosure of vulnerabilities.

This is the public, product-neutral version of the policy that ships in each
product tree as `SECURITY.md`. The commitments are identical; only the
product-specific detail differs, and each product's own file carries it.

## Reporting a vulnerability

Email **security@joralllc.com**.

Please include:

- **the product** and, if you have access to a unit, **the firmware build
  identifier**:

  | Product | Where the build identifier is shown |
  |---|---|
  | SATISense™ Industrial Edge Platform (IE-460) | web-console header (`fw <id>`), `intelligence_edge_opcua --version`, startup log |
  | 10BASE-T1S Media Gateway | web-console status header (`fw <id>`), `media-gateway --version`, startup log |

- a description of the issue and its impact;
- steps to reproduce, a proof of concept, or a packet capture if you can
  provide one;
- how you would like to be credited, if at all.

**Never include passwords, API keys, private keys or other secrets in a
report.** If you need to share sensitive material, say so in your first mail
and we will agree on a secure channel.

## What to expect

- We confirm receipt of your report.
- We assess the issue, keep you informed of progress, and coordinate a
  disclosure date with you before publishing.
- Security fixes are announced with plain-language fix notes stating the
  affected builds (by build identifier), the impact, and the corrective
  update. Updates are supplied free of charge through your Joral support or
  integration contact.
- We credit reporters in the fix notes unless they prefer otherwise.

## Scope

**In scope** — the firmware of the products listed above: the product daemons
(`intelligence_edge_opcua`, `media-gateway`, `plca-config`), the embedded web
consoles, the on-device AI components, and the platform components shipped in
the firmware image. The software bill of materials produced by each release
build lists those components.

**Out of scope** — Joral's corporate website and infrastructure, and physical
attacks requiring disassembly of the unit.

## Deployment context

These products are designed for **isolated or segmented machine-control
networks**, as stated in each user manual's deployment assumptions. Reports
that assume deployment on an open or internet-reachable network are still
welcome, but severity is assessed against the documented deployment model.

## Regulatory note

Joral is preparing these products against Regulation (EU) 2024/2847, the Cyber
Resilience Act. Vulnerability and incident reporting obligations apply from
**11 September 2026**; this address and policy are how a report reaches us.
