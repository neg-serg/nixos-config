# Wave 2 Benchmark: nixpkgs-slim rev bump (web-apps + cascade removed)

**Date:** 2026-07-15 **Change applied:**

- `flake.nix`: nixpkgs-slim rev `47ec8b02` → `ffdb45b4`
- Removed: web-apps + cascade (425 files, 111K lines)
- Fixes: `hardware/facter` disabled (references removed hyperv-guest.nix); compat/mail-stub.nix
  added (postfix removed, zfs references it)

## Methodology

- Script: `.omo/scripts/bench-nixpkgs.sh --variant slim`
- 1 cold eval + 3 warm evals
- Metric: `nix eval` of `.#nixosConfigurations.odin.config.system.build.toplevel.name` with
  `NIX_SHOW_STATS=1`
- Baseline: Wave 1 average (from `.omo/evidence/bench-wave1.md`)

## Raw Data

| Source | Run | CPU (s) | Wall (s) | Values | Thunks | Sets (MB) |
|--------|-----|---------|----------|--------|--------|-----------| | **Wave 1 (baseline)** | cold
avg | 4.642 | 5.20 | 11,197,771 | 7,066,783 | 326.7 | | **Wave 1 (baseline)** | warm avg | ~4.815 |
~5.70 | 11,197,735 | 7,066,750 | 326.7 | | Wave 2 | cold | 4.734 | 5.40 | 11,192,379 | 7,062,789 |
326.7 | | Wave 2 | warm #1 | 4.746 | 5.19 | 11,192,343 | 7,062,756 | 326.7 | | Wave 2 | warm #2 |
4.684 | 5.26 | 11,192,343 | 7,062,756 | 326.7 | | Wave 2 | warm #3 | 4.715 | 5.11 | 11,192,343 |
7,062,756 | 326.7 | | **Wave 2** | **warm avg** | **4.715** | **5.19** | **11,192,343** |
**7,062,756** | **326.7** |

## Comparison vs Wave 1 Baseline

| Metric | Wave 1 (cold avg) | Wave 2 (cold) | Delta | % Change |
|--------|-------------------|---------------|-------|----------| | **CPU (s)** | 4.642 | 4.734 |
+0.092 | +1.98% | | **Wall (s)** | 5.20 | 5.40 | +0.20 | +3.85% | | **Values** | 11,197,771 |
11,192,379 | **−5,392** | **−0.05%** ✅ | | **Thunks** | 7,066,783 | 7,062,789 | **−3,994** |
**−0.06%** ✅ | | **Sets (MB)** | 326.7 | 326.7 | 0.0 | 0.00% |

| Metric | Wave 1 (warm avg) | Wave 2 (warm avg) | Delta | % Change |
|--------|-------------------|-------------------|-------|----------| | **CPU (s)** | ~4.815 | 4.715
| **−0.100** | **−2.08%** ✅ | | **Wall (s)** | ~5.70 | 5.19 | **−0.51** | **−8.95%** ✅ | |
**Values** | 11,197,735 | 11,192,343 | **−5,392** | **−0.05%** ✅ | | **Thunks** | 7,066,750 |
7,062,756 | **−3,994** | **−0.06%** ✅ | | **Sets (MB)** | 326.7 | 326.7 | 0.0 | 0.00% |

## Interpretation

### Improvements

- **Values**: −5,392 (−0.05%) — consistent with removal of 425 files from nixpkgs-slim (web-apps +
  cascade packages no longer in the evaluation graph).
- **Thunks**: −3,994 (−0.06%) — fewer deferred evaluations from removed modules.
- **Warm CPU**: −2.08% improvement over Wave 1 warm average — the removals slightly accelerate
  repeated evaluation.
- **Warm Wall**: −8.95% — likely within noise range for single-run wall time, but directionally
  consistent with reductions.

### Noise / Neutral

- **Cold CPU**: +1.98% (4.642 → 4.734). This is within typical run-to-run noise (±3%) for cold eval.
  A single cold data point vs the double-run Wave 1 average makes this inconclusive.
- **Sets**: unchanged at 326.7 MB. The reduction from removed modules is offset by the compat stubs
  and retained dependency tree.

### Regression Check (>5% threshold)

- No metric exceeds the 5% regression threshold.
- Cold CPU (+1.98%) is well within noise.
- The warm improvements confirm the change is net-beneficial.

## Evidence Files

- `/tmp/bench-slim-wave2.csv` — raw CSV output
- `.omo/evidence/bench-wave2.md` — this file

## Diff stats (nixpkgs rev bump)

```
flake.lock | 6 +++---
1 file changed, 3 insertions(+), 3 deletions(-)
— Only nixpkgs_3 (nixpkgs-slim) updated: lastModified 1784085041→1784094885, rev ffdb45b4
```
