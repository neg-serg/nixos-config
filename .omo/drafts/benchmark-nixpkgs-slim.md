# Draft: benchmark-nixpkgs-slim

## State
- intent: clear
- review_required: false
- status: plan-ready
- pending: await user decision — start work or high-accuracy review

## Decisions
- Runs: 1 cold + 3 warm per variant
- Expression: `toplevel.name` (matches user's existing measurement)
- Cache scope: clear eval-cache dirs + `--refresh` double-safety
- Upstream rev: auto-find via GitHub API (T1.0), fallback to `curl` latest unstable
- Metrics: CPU time, wall time, values, thunks, sets_bytes, GC time, GC fraction, nrAvoided, nrLookups
- Report: terminal table + markdown table in evidence
- Scripts: all committed to `.omo/scripts/`

## Components
| ID | Component | Outcome | Status |
|----|-----------|---------|--------|
| C1 | Upstream nixpkgs baseline measurement | CPU/mem stats for NixOS/nixpkgs | pending |
| C2 | Fork (nixpkgs-slim) measurement | CPU/mem stats for neg-serg/nixpkgs-slim | pending |
| C3 | Comparison table | Side-by-side deltas in terminal + MD | pending |
| C4 | Validation | Measurements consistent, no confounding factors | pending |

## Metis gap analysis
15 gaps found, all resolved. Key fixes:
- T2.2 name check loosened to `nixos-system-odin-*` prefix (upstream uses different naming)
- Python script creation todos added (T1.0, T4.0)
- `/usr/bin/time` → `command time -p` (NixOS-compatible)
- T2.3 made MANDATORY (always runs, even after T2.2 failure)
- CSV output path specified (`/tmp/bench-${variant}.csv`)
- Line 8 hardcodes → dynamic grep/sed
- eval-cache path widened + `--refresh` safety
- Lock failure mode added to T2.2
- Warm variance F5 check added to Final Verification
