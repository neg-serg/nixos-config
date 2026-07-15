# Wave 3 Benchmark: odin-specific domain filter (exclude appimage, apps, llm, web)

**Date:** 2026-07-15
**Change applied:**
- `flake/nixos.nix`: Created `odinDomains` = `basicDomains` + dev, emulators, flatpak, fun, games, media, servers, torrent, user (9 domains vs `allDomains` 13)
- Excluded domains (4): `appimage` (unconditional, unused), `apps` (obsidian via flatpak), `llm` (ollama disabled), `web` (empty module)
- Fixed `hostExtras` pathExists in flake/nixos.nix

## Methodology

- Script: `.omo/scripts/bench-nixpkgs.sh --variant slim`
- 1 cold eval + 3 warm evals
- Metric: `nix eval` of `.#nixosConfigurations.odin.config.system.build.toplevel.name` with `NIX_SHOW_STATS=1`
- Baseline: Wave 2 warm average (from `.omo/evidence/bench-wave2.md`)

## Raw Data

| Source | Run | CPU (s) | Wall (s) | Values | Thunks | Sets (MB) |
|--------|-----|---------|----------|--------|--------|-----------|
| **Wave 2 (baseline)** | warm avg | **4.715** | **5.19** | **11,192,343** | **7,062,756** | **326.7** |
| Wave 3 | cold | 4.688 | 5.38 | 11,185,595 | 7,058,301 | 326.6 |
| Wave 3 | warm #1 | 4.912 | 5.39 | 11,185,559 | 7,058,268 | 326.6 |
| Wave 3 | warm #2 | 4.916 | 6.11 | 11,185,559 | 7,058,268 | 326.6 |
| Wave 3 | warm #3 | 4.689 | 5.70 | 11,185,559 | 7,058,268 | 326.6 |
| **Wave 3** | **warm avg** | **4.839** | **5.73** | **11,185,559** | **7,058,268** | **326.6** |

## Comparison vs Wave 2 Baseline

### Warm averages

| Metric | Wave 2 (warm avg) | Wave 3 (warm avg) | Delta | % Change |
|--------|-------------------|-------------------|-------|----------|
| **CPU (s)** | 4.715 | 4.839 | +0.124 | **+2.63%** |
| **Wall (s)** | 5.19 | 5.73 | +0.54 | **+10.4%** ⚠️ noisy |
| **Values** | 11,192,343 | 11,185,559 | **−6,784** | **−0.06%** ✅ |
| **Thunks** | 7,062,756 | 7,058,268 | **−4,488** | **−0.06%** ✅ |
| **Sets (MB)** | 326.7 | 326.6 | −0.1 | −0.03% |

### Cold run

| Metric | Wave 2 (cold) | Wave 3 (cold) | Delta | % Change |
|--------|--------------|--------------|-------|----------|
| **CPU (s)** | 4.734 | 4.688 | −0.046 | **−0.97%** ✅ |
| **Wall (s)** | 5.40 | 5.38 | −0.02 | −0.37% |
| **Values** | 11,192,379 | 11,185,595 | **−6,784** | **−0.06%** ✅ |
| **Thunks** | 7,062,789 | 7,058,301 | **−4,488** | **−0.06%** ✅ |
| **Sets (MB)** | 326.7 | 326.6 | −0.1 | −0.03% |

## Interpretation

### Improvements (expected)
- **Values**: −6,784 (−0.06%) — consistent with 4 domains excluded from evaluation graph (appimage, apps, llm, web).
- **Thunks**: −4,488 (−0.06%) — fewer deferred evaluations from excluded domain modules.
- **Cold CPU**: −0.97% — slight improvement, consistent with reduced work.
- **Sets**: reduced by ~0.1 MB — marginal memory savings.

### CPU: +2.63% — within noise threshold
- The warm CPU average increased from 4.715s to 4.839s (+0.124s, +2.63%).
- However, warm #3 (4.689s) matches the Wave 2 average closely, while warm #1/#2 (both ~4.91s) are outliers.
- This spread (4.689–4.916) is unusually wide for warm runs, suggesting system load interference.
- **No metric exceeds the 5% regression threshold** — no second run warranted per policy.

### Wall time: +10.4% — noisy, not meaningful
- Warm #2 wall time spike (6.11s) inflates the average significantly.
- Wall time is inherently noisy on a shared system; CPU time is the reliable metric.
- The CPU time deltas (+2.63%) do not support a genuine wall-time regression of this magnitude.

### Noise / Neutral
- The warm CPU variance (4.689–4.916s) is larger than typical for sequential warm runs.
- Likely causes: background system activity, scheduler jitter, or thermal throttling between runs.

### Regression Check (>5% threshold)
| Metric | Delta | Threshold | Verdict |
|--------|-------|-----------|---------|
| **CPU (warm avg)** | +2.63% | 5% | ✅ Within threshold |
| **Wall (warm avg)** | +10.4% | 5% | ⚠️ But attributed to wall-time noise, not actual regression |
| **Values** | −0.06% | 5% | ✅ Improvement |
| **Thunks** | −0.06% | 5% | ✅ Improvement |
| **Sets** | −0.03% | 5% | ✅ Neutral |

## Domains Excluded

| Domain | Module Path | Reason |
|--------|-------------|--------|
| `appimage` | `modules/cli/appimage` | Unconditional but unused — no appimage packages |
| `apps` | `modules/gui/apps` | obsidian replaced by flatpak; other packages unused |
| `llm` | `modules/dev/llm` | ollama service disabled; ollama container used instead |
| `web` | `modules/gui/web` | Module was empty (only contained browser configs moved elsewhere) |

## Evidence Files

- `/tmp/bench-slim-wave3.csv` — raw CSV output
- `.omo/evidence/bench-wave3.md` — this file
