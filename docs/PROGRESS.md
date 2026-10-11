# Progress notes

## 2026-10-11: Milestone 2 (environment report utility)

Added a read-only ArkOS diagnostic package.

- Launcher: `src/diagnostic/ports/GitGet Diagnostic.sh` (POSIX sh).
- User instructions: `src/diagnostic/ports/gitget-diag/README.txt`.
- Build: `python3 tools/build_diagnostic.py` writes
  `dist/GitGet-Diagnostic-1.0.0.zip` and its `.sha256`.
- PC-side check: `sh tests/check_diagnostic.sh`.
- Evidence and open assumptions: `docs/DECISIONS.md`.

Status: not yet run on a physical R36S. Next step is to run it on the device,
upload `GitGet_Device_Report.txt`, then do Milestone 3 (architecture decision)
from that evidence.
