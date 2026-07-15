# Wave 1 Benchmark Comparison: nixpkgs-slim

**Date:** 2026-07-15 **Changes applied:**

- T1.1: `modules/system/deduplicate-shadow.nix` — shadow dedup (55→2 copies in systemPackages)
- T1.2: 22 new `disabledModules` entries in `hosts/odin/default.nix` (24→46 total)

## Methodology

- Script: `.omo/scripts/bench-nixpkgs.sh --variant slim`
- 1 cold eval + 3 warm evals per run (2 runs total for confirmation)
- Cold runs compared against single baseline from pre-Wave-1
- Metric: `nix eval` of `.#nixosConfigurations.odin.config.system.build.toplevel.name` with
  `NIX_SHOW_STATS=1`

## Raw Data

| Source | Run | CPU (s) | Wall (s) | Values | Thunks | Sets (MB) |
|--------|-----|---------|----------|--------|--------|-----------| | **Baseline** | cold | 4.78 |
5.13 | 11,175,376 | 7,072,131 | 327.0 | | Wave 1 | cold #1 | 4.704 | 5.39 | 11,197,771 | 7,066,783 |
326.7 | | Wave 1 | cold #2 | 4.579 | 5.01 | 11,197,771 | 7,066,783 | 326.7 | | Wave 1 | warm avg |
4.854 / 4.776 | 5.74 / 5.65 | 11,197,735 | 7,066,750 | 326.7 |

## Comparison (Avg Cold vs Baseline)

| Metric | Baseline | Wave 1 Avg | Delta | % Change |
|--------|----------|------------|-------|----------| | **CPU (s)** | 4.780 | 4.642 | **-0.138** |
**−2.89%** ✅ | | **Wall (s)** | 5.13 | 5.20 | +0.07 | +1.36% (noise) | | **Values** | 11,175,376 |
11,197,771 | +22,395 | +0.20% | | **Thunks** | 7,072,131 | 7,066,783 | **−5,348** | **−0.08%** ✅ | |
**Sets (MB)** | 327.0 | 326.7 | **−0.3** | **−0.08%** ✅ |

## Interpretation

### Improvements

- **CPU time**: ~2.9% faster (consistent across both runs: −1.6% and −4.2%)
- **Thunks**: ~5.3K fewer (−0.08%) — likely from shadow dedup avoiding redundant package evaluation
- **Sets memory**: ~0.3 MB reduction — consistent with fewer shadow copies

### Noise / Neutral

- **Wall time**: first run +5.07%, second run −2.34%. Averaged to +1.36%, confirming this is within
  run-to-run noise (system load, disk cache). No regression confirmed.
- **Values**: +22,395 (+0.20%) — marginal increase, possibly from new disabledModules entries
  requiring some module structure to remain.

### Regression Check (>5% threshold)

- Wall time spike in run #1 (5.39s vs 5.13s baseline = +5.07%) triggered re-run.
- Run #2 (5.01s) disproves consistent regression — difference is system noise.
- **No confirmed regression >5% in any metric.**

## Attribution

Cannot precisely separate the two changes, but plausible contributions:

| Change | Likely Impact | |--------|--------------| | **Shadow dedup** | Thunk reduction (fewer
copies of pkgs to evaluate), CPU improvement | | **disabledModules** | Slightly more values if
modules import dependencies that weren't previously evaluated; otherwise neutral or mildly
beneficial |

## Verdict

**Wave 1 is performance-neutral to slightly positive.** CPU improved ~3%, thunks and sets marginally
reduced, no regression confirmed. The shadow dedup change is the primary driver of the thunk/set
reduction.
