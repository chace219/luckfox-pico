# Release compliance evidence

One directory per shipped release, named by the release identity a unit reports
in `/etc/sw-versions` — `2026.08.17`, not a git describe. Each holds:

| File | What it is |
|---|---|
| `provenance.md` | release ↔ build ID ↔ commit ↔ submodule pins, in one table |
| `sbom.md` / `sbom.csv` | the bill of materials for that build (CRA Annex I Part II §1) |
| `cve-report.md` | the findings and their dispositions at the gate (Annex I Part I §2, Part II §2) |

Written by `scripts/compliance/archive-release.sh`, then committed and tagged —
[`../release-build-runbook.md`](../release-build-runbook.md) step 6.

## Why this directory exists

`./build.sh sbom` and `./build.sh cve` write into `output/compliance/`, which is
in `.gitignore`. Until 2026-08-22 that was the only copy of either, and no
release had ever been tagged, so the fact that release `2026.08.17` was built
from commit `5a6f91d6a` lived in a filename in an ignored directory on one
workstation and nowhere else. Nothing would have reported that as missing.

The obligations that need it are ordinary ones. Annex II asks for the version
and build-ID scheme. Annex I Part II §2 asks that vulnerabilities be addressed
without delay — which starts with answering *which builds are affected*, from a
version an operator can read off a console, months after the tree has moved on.

## Nothing is archived yet

The first entry lands at the next release cut. `2026.08.17` was cut before
`sbom` was on the gate line, so no bill of materials exists at its build ID; the
runbook's "Archiving a release that was cut before this step existed" section
covers reconstructing it, and what `provenance.md` will say about the
reconstruction if you do.
