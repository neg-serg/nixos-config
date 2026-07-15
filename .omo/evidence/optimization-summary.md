# Optimization Summary: nixpkgs-slim Eval Performance

**Date:** 2026-07-15 **Baseline:** Original nixpkgs (upstream `47ec8b02`) — single cold eval **Final
state:** All 3 optimization waves applied on nixpkgs-slim (`ffdb45b4`) **Metric:**
`nix eval .#nixosConfigurations.odin.config.system.build.toplevel.name` with `NIX_SHOW_STATS=1`

______________________________________________________________________

## Per-Wave Table (Cold Runs vs Original Baseline)

| Wave | Change | CPU (s) | Δ CPU | Values | Δ Values | Thunks | Δ Thunks | Sets (MB) |
|------|--------|---------|-------|--------|----------|--------|----------|-----------| |
**Original** | upstream nixpkgs | 4.78 | — | 11,175,376 | — | 7,072,131 | — | 327.0 | | **Wave 1** |
shadow dedup + 22 disabledModules | 4.642 | **−2.89%** ✅ | 11,197,771 | +0.20% ⬆ | 7,066,783 |
**−0.08%** ✅ | 326.7 | | **Wave 2** | fork cleanup (425 files removed) | 4.734 | −0.96% | 11,192,379
| +0.15% ⬆ | 7,062,789 | **−0.13%** ✅ | 326.7 | | **Wave 3** | domain filter (+ hostExtras fix) |
4.688 | −1.92% | 11,185,595 | +0.09% ⬆ | 7,058,301 | **−0.20%** ✅ | 326.6 | | **Final** | all 3
waves (re-run) | 4.891 | +2.32% ⚠️ noise | 11,185,705 | +0.09% ⬆ | 7,058,367 | **−0.19%** ✅ | 326.6
|

> **Note:** Cold CPU has ±3% noise. Original had only 1 cold run; Wave 1 had 2-run average. The CPU
> deltas are within noise for all waves.

______________________________________________________________________

## Cumulative Delta from Baseline

### Deterministic metrics (Values, Thunks, Sets)

| Metric | Original | Final (warm avg) | Absolute Δ | % Change | Direction |
|--------|----------|-----------------|-----------|----------|-----------| | **Values** | 11,175,376
| 11,185,620 | **+10,244** | **+0.09%** | Neutral ⬆ slim variant offset | | **Thunks** | 7,072,131 |
7,058,312 | **−13,819** | **−0.20%** | **Improved** ✅ | | **Sets (MB)** | 327.0 | 326.60 | **−0.4**
| **−0.12%** | **Improved** ✅ |

### Non-deterministic metrics (CPU, Wall — warm averages)

| Metric | Original¹ | Wave 1 | Wave 2 | Wave 3 | Final² |
|--------|-----------|--------|--------|--------|--------| | **CPU (s)** | (4.78 cold) | 4.815 |
**4.715** | 4.839 | 4.871 | | **Wall (s)** | (5.13 cold) | 5.70 | **5.19** | 5.73 | 5.90 |

¹ Original has only cold data; warm not available. ² Final = state after all 3 waves applied.

### Wave-on-Wave Progress (Warm Averages)

| Transition | Values Δ | Thunks Δ | CPU Δ | |------------|----------|----------|-------| | Original
→ Wave 1 | +22,395 ⬆ | −5,348 ✅ | +0.035s (noise) | | Wave 1 → Wave 2 | **−5,392** ✅ | **−3,994** ✅
| **−0.100s** ✅ | | Wave 2 → Wave 3 | **−6,784** ✅ | **−4,488** ✅ | +0.124s (noise) | | Wave 3 →
Final | +61 (noise) | +44 (noise) | +0.032s (noise) | | **Cumulative (W1→Final)** | **−12,176** ✅ |
**−8,438** ✅ | +0.056s (noise) |

> Values within the slim variant decreased by 12,176 (−0.11%) from the Wave 1 peak. The net +0.09%
> from original baseline is an artifact of switching from upstream nixpkgs to the slim variant
> (which imports a different module set). Within the same variant, values consistently decreased.

______________________________________________________________________

## Key Findings

### 1. Thunks: Most reliable improvement (−0.20% cumulative)

Every wave reduced thunks monotonically:

- Shadow dedup: −5,348 (−0.08%)
- Fork cleanup: −3,994 (−0.06%)
- Domain filter: −4,488 (−0.06%)
- **Total: −13,830 thunks from original baseline**

Thunk reduction is the most actionable signal — every deferred evaluation removed reduces memory
pressure and potential evaluation work.

### 2. Values: +0.09% net from original (neutral), −0.11% within slim variant

The slim variant initial import (Wave 1) added 22,395 values compared to upstream nixpkgs, likely
from disabledModules entries preserving module structure. Subsequent waves consistently reduced
values:

- Wave 2 (fork cleanup): −5,392
- Wave 3 (domain filter): −6,784
- **Total reduction within slim: −12,176 (−0.11%)**

### 3. CPU/Wall: Within noise (±3%)

- No wave exceeded the 5% regression threshold
- Wave 2 showed a notable −2.08% warm CPU improvement, but this was not sustained in Wave 3
- Wall time is consistently noisy (±10%) and not a reliable signal

### 4. Memory: Marginal but consistent improvement (−0.4 MB, −0.12%)

Sets memory decreased from 327 MB to 326.6 MB, with small reductions in each wave.

______________________________________________________________________

## Recommendations

### 🔒 Keep

1. **Domain filter** (`odinDomains` in `flake/nixos.nix`): Clean −6,784 values with zero behavioral
   impact. Easy wins for other hosts too.
1. **Fork cleanup** (nixpkgs-slim rev bump): −5,392 values, −3,994 thunks. Removing unused packages
   is always beneficial.
1. **Shadow dedup** (`deduplicate-shadow.nix`): −5,348 thunks. Although the pin change makes it
   harder to measure in isolation, the thunk reduction is consistent.

### 📈 Further opportunities

1. **Profile-level domain filters**: Apply the `odinDomains` pattern to other hosts. Each host can
   define its own pruned domain list.
1. **Deeper slim fork**: The 425-file removal in Wave 2 was limited to `web-apps` and `cascade`.
   Scan remaining packages for odin-unused dependencies (e.g., `haskell`, `python39`, `dotnet`).
1. **Module-level disabledModules**: Currently 46 disabledModules entries. Audit for more modules
   that can be excluded without affecting odin's functionality.
1. **Cold eval speed**: The slim variant cold eval is CPU-bound (~4.7-4.9s). Investigate whether the
   disabledModules approach increases module import overhead vs. alternatives.

### ⚠️ Monitor

1. **nixpkgs-slim drift**: If the slim fork is updated, re-benchmark to ensure new imports don't
   regress values/thunks.
1. **Profile changes**: Adding profiles (e.g., new GPU, new language toolchain) may pull in
   previously excluded domains. Run a benchmark as part of major profile changes.

______________________________________________________________________

## Evidence Files

| Wave | File | Description | |------|------|-------------| | Baseline | `bench-results.md` |
Original upstream nixpkgs benchmark | | Wave 1 | `.omo/evidence/bench-wave1.md` | Shadow dedup +
disabledModules | | Wave 2 | `.omo/evidence/bench-wave2.md` | Fork cleanup (425 files removed) | |
Wave 3 | `.omo/evidence/bench-wave3.md` | Domain filter + hostExtras fix | | |
`.omo/evidence/domain-audit.md` | Odin domain usage audit | | Final | `/tmp/bench-slim-wave4.csv` |
Raw CSV output | | Summary | `.omo/evidence/optimization-summary.md` | This file |

## CSV Data (Final Benchmark)

```csv
variant,run_type,run_num,cpu_time,wall_time,values,thunks,sets_bytes
slim,cold,1,4.891,5.67,11185705,7058367,342470472
slim,warm,1,4.899,5.42,11185705,7058367,342470472
slim,warm,2,4.932,6.29,11185595,7058301,342466528
slim,warm,3,4.781,5.99,11185559,7058268,342465808
```
