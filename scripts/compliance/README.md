# Compliance tooling

Two generators, one release procedure. Both describe **the image this tree
builds**, and both derive their component list from the same Buildroot
`.config`, so they cannot describe different images.

| | What it answers | Command |
|---|---|---|
| [`gen-sbom.sh`](gen-sbom.sh) | What is *in* the image? | `./build.sh sbom` |
| [`cve-check.py`](cve-check.py) | What is *known to be wrong* with what is in it? | `./build.sh cve` |

Regulation (EU) 2024/2847 (Cyber Resilience Act): Annex I Part II §1 (SBOM),
Annex I Part I §2 ("without known exploitable vulnerabilities"), Annex I Part II
§2 (address vulnerabilities in components without delay).

Outputs land in `output/compliance/`, stamped with the SDK build ID
(`git describe`) so a report can be matched to a deployed unit — the same
identifier the daemons report via `--version` and the consoles show.

## Release procedure

Run both **after** the image is built and **before** it is shipped or tagged:

```sh
./build.sh sbom --reuse      # --reuse skips legal-info's slow source re-verify
./build.sh cve               # exit status is the gate
```

`./build.sh cve` exits:

- **0** — no unaccepted findings. Keep the report with the technical file.
- **1** — blocking findings. Either fix the component or record a dated decision
  in [`cve-triage.csv`](cve-triage.csv) (see below).
- **2** — the check could not be completed (no advisory data for a component
  whose identity we *do* know, malformed triage file). Deliberately distinct
  from 1 so CI can tell "we found problems" from "we learned nothing" — a check
  that silently degrades to a pass is worse than no check.

The first run of the day costs ~8 minutes without an API key (NVD allows 5
requests per 30s; the checker paces itself under that). Answers are cached per
CPE under `output/compliance/cve-cache/`, so re-runs are instant until the cache
ages past `--max-age-days` (7). Set `NVD_API_KEY` (free, from
<https://nvd.nist.gov/developers/request-an-api-key>) for a ~8x speedup, and use
`--offline` on a build machine with no outbound access — it will use the cache
and fail loudly rather than silently skip anything.

## Tests

```sh
scripts/compliance/test-cve-check.py     # 39 checks, no network
```

The gate's value is failing when it should and only when it should, so the tests
drive the real script over fixture advisory data (`--offline` reads only the
cache, which makes the cache the test seam) and cover the ways a checker can
lie: a missing CPE reading as clean, an expired decision still suppressing, a
malformed triage row being ignored rather than rejected, absent advisory data
degrading into a pass, report-only findings leaking into the gate. Each of those
was confirmed to fail against a checker mutated back to the wrong behaviour, so
they guard the contract rather than merely passing.

## Triage

A finding stops blocking only via a row in [`cve-triage.csv`](cve-triage.csv)
carrying a decision (`not-affected` / `accepted-risk` /
`fixed-pending-release`), a justification someone else can check, an owner, and a
**`REVIEW_BY` date**. When that date passes the row stops suppressing and the
gate fails again.

That expiry is the point. An allowlist without one turns "accepted for now" into
"forgotten", which is the exact failure the CRA's "without delay" wording is
aimed at. The checker also rejects a malformed row rather than ignoring it, so a
half-filled entry can never quietly hide a finding.

Buildroot's own `<PKG>_IGNORE_CVES` declarations are honoured separately — those
are upstream's determination that a CVE does not apply to the version they
package. They appear in the report under **Suppressed** with `buildroot upstream`
as the owner, so ours and theirs are never confused.

## Component identity

Advisory matching needs a CPE, not a package name. We do not maintain a name→CPE
table: Buildroot already has one (`<PKG>_CPE_ID_VENDOR/PRODUCT`), and
`make show-info` resolves it against the version actually built. 73 of this
image's 130 target packages carry one.

[`cpe-extra.csv`](cpe-extra.csv) covers the rest, and does three jobs:

1. **Declares a CPE** Buildroot lacks (verify it first — a *wrong* CPE reports a
   component as clean, which is worse than the gap it closes; `cve-check.py
   --suggest-cpe` prints candidates from the NVD CPE dictionary).
2. **Declares a component absent from NVD** (`CPE=NONE`) — our own daemons and
   consoles have no NVD presence at all, so leaving them in the unchecked bucket
   would report a fact as a gap.
3. **Adds a component Buildroot cannot see.** The kernel, U-Boot and the
   Rockchip media SDK are not Buildroot packages but are unquestionably in the
   image.

Components with no CPE from either source are reported as **NOT CHECKED**, by
name, in the report's Coverage section. They are never counted as clean.

### Report-only components

`MODE=report-only` in `cpe-extra.csv` means findings are counted and listed but
never block. It is set for the vendor kernel and U-Boot, because per-CVE triage
is not how those get fixed: 5.10.160 matches ~5100 NVD records, almost all in
subsystems this SoC configuration does not build, and the remedy is moving the
vendor base to a newer stable rather than dispositioning five thousand records
against a version we do not control. The count stays in the report so the
decision to treat them differently is visible instead of implicit.

## Why not Buildroot's own CVE checker

`support/scripts/pkg-stats` in Buildroot 2023.02 reads NVD's JSON 1.1 data
feeds, which NIST retired — those URLs answer **403** now, so it cannot produce
CVE data in this tree at all. `cve-check.py` uses the NVD 2.0 REST API and lets
NVD resolve version ranges server-side, which is the part that is easiest to get
subtly wrong by hand.
