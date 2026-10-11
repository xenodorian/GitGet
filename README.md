# GitGet

A lightweight, controller-operated GitHub ROM downloader for the R36S running
ArkOS. The full requirements are in `Current Work.md`.

## Current state

Milestone 2 is built: a read-only device diagnostic.

- Download: `dist/GitGet-Diagnostic-1.0.0.zip` (checksum in the matching
  `.sha256` file).
- Install and run steps: `src/diagnostic/ports/gitget-diag/README.txt`.
- Decisions, evidence, and unverified assumptions: `docs/DECISIONS.md`.
- Progress notes: `docs/PROGRESS.md`.

Rebuild with `python3 tools/build_diagnostic.py`. Check with
`sh tests/check_diagnostic.sh`.
