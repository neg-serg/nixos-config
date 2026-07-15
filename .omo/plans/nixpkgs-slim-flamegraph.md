# nixpkgs-slim-flamegraph - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** Flamegraph-профилирование времени оценки NixOS-конфигурации и целевые оптимизации форка nixpkgs-slim с измеримым приростом скорости eval (≥5% за раунд, до 3 раундов). Одна команда — один flamegraph. Одна команда — сравнение до/после.

**Why this approach:** Профилирование через `perf` + Inferno/Rust (flamegraph) показывает CPU hot-paths в реальном nix evaluator'е, а не теоретические bottleneck'и. Оптимизации верифицируются гиперфайном (hyperfine) на полной конфигурации odin — честное сравнение до/после на одинаковой машине. Защита от регрессии: closure identity check (выходной hash не должен измениться).

**What it will NOT do:** Не трогает C++ код nix evaluator'а. Не меняет архитектуру nixos-config. Не добавляет CI-автоматизацию. Не профилирует ядро или кучу. Не ломает систему — каждая оптимизация проверяется на identity closure.

**Effort:** Medium (4 волны, 10 задач)
**Risk:** Low — nixpkgs-slim оптимизации на отдельной ветке с тэгом baseline; любой откат через `git revert`
**Decisions to sanity-check:**
- Inferno (Rust) упаковывается руками через `buildRustPackage` — fallback на Perl `flamegraph.pl` если не взлетит
- Бенчмарки: 3 сценария (полный odin, odin-lite, upstream baseline) × 12 повторов hyperfine, статистический gate >2× stddev
- Мах 3 раунда оптимизации, трёхуровневый порог: STOP (<2%), MARGINAL (2-5%), EFFECTIVE (≥5%)
- Все команды используют `--override-input nixpkgs /tmp/nixpkgs-slim` для подключения локального форка

Your next move: Approve and run `/start-work`, or request a high-accuracy review first. Full execution detail follows below.

---
> TL;DR (machine): Medium effort, Low risk — add Inferno+hyperfine profiling infra, flamegraph nix eval, 1-3 targeted nixpkgs-slim optimizations with closure identity guard

---

## Scope
### Must have
- **Inferno** flamegraph package in flake devShell (Rust-native, no Perl)
- **nix-flamegraph.sh** — one-command flamegraph generation: `perf record -g --call-graph dwarf` on `nix build --dry-run` → `perf script` → `inferno-collapse-perf` → `inferno-flamegraph` → SVG
- **nix-eval-bench.sh** — hyperfine benchmark on 3 eval scenarios: full odin config, odin-lite, raw nixpkgs attr eval
- **Justfile targets**: `just flamegraph-eval`, `just bench-eval`
- **Baseline benchmarks** recorded to `benchmarks/YYYY-MM-DD-HHMMSS_odin/`
- **nixpkgs-slim optimizations** derived from flamegraph hot-path analysis, each as an atomic commit in `/tmp/nixpkgs-slim`
- **Before/after verification** for each optimization: hyperfine comparison + `nix build --dry-run` success

### Must NOT have (guardrails, anti-slop, scope boundaries)
- NO C++ nix evaluator changes (Determinate Nix binary is immutable)
- NO nixos-config architecture changes (domain filter, module layout, feature flags)
- NO CI regression automation (no `.github/workflows` for eval-time checks)
- NO kernel-level profiling (`perf` on kernel events, AutoFDO)
- NO heap profiling (heaptrack, valgrind massif)
- NO modification to `/etc/nixos` product modules/hosts/overlays
- NO `.omo/` artifacts outside this plan's evidence paths

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: **tests-after** — each optimization verified by (a) `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run` success, (b) hyperfine comparison against baseline
- Framework: `hyperfine` for timing, `nix build --dry-run` for correctness
- Evidence: `.omo/evidence/task-<N>-nixpkgs-slim-flamegraph.log` — shell output captured with timestamps
- Baseline: stored in `benchmarks/baseline-YYYY-MM-DD.json` — hyperfine JSON export
- Flamegraph artifacts: `benchmarks/YYYY-MM-DD-HHMMSS_odin/flamegraph.svg`

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.

**Wave 1 — Infrastructure (parallel)**: C1 flamegraph scripting + C2 benchmark harness. Both are independent.

**Wave 2 — Baseline + Analysis (sequential)**: Collect baseline benchmarks, generate first flamegraph, analyze hot-paths.

**Wave 3 — Optimization (iterative, sequential per-hotpath)**: Each identified hot-path → implement optimization in `/tmp/nixpkgs-slim` → verify with hyperfine + dry-run → commit. Multiple hot-paths can be worked sequentially but each must complete before the next (to avoid interference in measurements).

**Wave 4 — Final verification**: All verification gates in parallel.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. Add Inferno to devShell | — | 3 | 2 |
| 2. Create nix-eval-bench.sh | — | 4, 5 | 1, 3 |
| 3. Create nix-flamegraph.sh | 1 | 6 | 2 |
| 4. Add Justfile targets | 2, 3 | — | 5 |
| 5. Collect eval baseline | 2 | 7, 8, 9 | 4 |
| 6. Generate flamegraph + analyze | 3, 5 | 7, 8, 9 | — |
| 7. Optimize hot-path #1 | 6 | 8 | — |
| 8. Optimize hot-path #2 | 7 | 9 | — |
| 9. Optimize hot-path #3 | 8 | — | — |
| 10. Final verification wave | 7, 8, 9 | — | all 4 gates parallel |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->

### Wave 1 — Infrastructure (parallel)

- [x] 1. Package Inferno (Rust flamegraph) or add to devShell + wire nixpkgs-slim override support
  What to do / Must NOT do:
    Inferno (github.com/jonhoo/inferno) is NOT in nixpkgs — must be packaged from source. Create `/etc/nixos/packages/inferno/default.nix` using `buildRustPackage` (Cargo.lock in upstream repo). Wire it into the flake: add to `packages/flake/custom-packages.nix` (actual overlay entry point for this repo) OR add directly to the devShell packages list in `flake/per-system.nix`. Also add `pkgs.perf` (from `linuxPackages.perf`) and `pkgs.hyperfine` to the default devShell in `flake/per-system.nix`. These are system packages but must be in the dev shell for profiling scripts.
    ALSO: Add a `NIXPKGS_SLIM_PATH` env var or `--override-input` support pattern — the benchmark/flamegraph scripts need to override nixpkgs to use `/tmp/nixpkgs-slim` instead of the pinned remote. Wire this as an optional arg.
    If Inferno packaging proves too complex, fall back to `pkgs.flamegraph` (Brendan Gregg Perl scripts, already in nixpkgs) and use `flamegraph.pl` instead of `inferno-flamegraph`.
    Do NOT change any existing package lists unrelated to profiling. Do NOT modify `modules/`, `hosts/`, or existing overlays.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 3
  References (executor has NO interview context - be exhaustive):
    - `/etc/nixos/flake/per-system.nix:64-80` — existing devShell inputs (valgrind at line 68)
    - `/etc/nixos/packages/flake/custom-packages.nix` — actual overlay entry point (NOT `packages/overlay.nix` — that file does not exist)
    - `/etc/nixos/packages/AGENTS.md` — packaging guidelines (note: references `packages/overlays/*` which don't exist yet; use `packages/flake/custom-packages.nix` instead)
    - Inferno source: `github:jonhoo/inferno` — Cargo.toml at root
    - `/etc/nixos/modules/monitoring/pkgs/default.nix:23` — `pkgs.perf` location
    - `/etc/nixos/modules/dev/pkgs/default.nix:8` — `pkgs.hyperfine` location
    - Fallback: `pkgs.flamegraph` (Perl) — `nix eval nixpkgs#flamegraph` confirms it exists
    - Flake input: `nixpkgs.url = "github:neg-serg/nixpkgs-slim/ffdb45b47..."` (`/etc/nixos/flake.nix:8`)
  Acceptance criteria (agent-executable):
    - `nix build .#inferno` succeeds (or `.#flamegraph` if fallback)
    - `nix develop .# --command which inferno-flamegraph` exits 0 (or `which flamegraph.pl`)
    - `nix develop .# --command which perf` exits 0
    - `nix develop .# --command which hyperfine` exits 0
    - `nix develop .# --command which jq` exits 0 (needed for closure identity guard pipeline)
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-1-nixpkgs-slim-flamegraph.log`
    - Happy: `nix develop .# --command inferno-flamegraph --help` (or `flamegraph.pl --help`) prints usage → pass
    - Happy: `nix develop .# --command perf --version` prints version → pass
    - Happy: `nix develop .# --command hyperfine --version` prints version → pass
    - Failure: `nix build .#inferno` fails → document fallback switch to `pkgs.flamegraph` → pass (graceful degradation)
  Commit: Y | `[dev/tools] Package inferno flamegraph tool and add profiling deps to devShell`

- [x] 2. Create nix-eval-bench.sh benchmark harness
  What to do / Must NOT do: Create `/etc/nixos/scripts/dev/nix-eval-bench.sh` (repo root, NOT under `packages/`). Script runs hyperfine on 3 eval scenarios with `--warmup 2 --runs 12 --export-json benchmarks/bench_<scenario>_<date>.json`. 
    Scenarios (exact commands, ALL use `--override-input nixpkgs`):
    (1) Full odin config: `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs ${NIXPKGS_SLIM_PATH:-/tmp/nixpkgs-slim}`
    (2) Odin-lite config: `nix build .#nixosConfigurations.odin-lite.config.system.build.toplevel --dry-run --override-input nixpkgs ${NIXPKGS_SLIM_PATH:-/tmp/nixpkgs-slim}`
    (3) Upstream nixpkgs baseline: `nix eval nixpkgs#legacyPackages.x86_64-linux.hello.outPath --raw`
    Scenario 3 uses UPSTREAM nixpkgs (not nixpkgs-slim) intentionally — serves as a stability baseline that should show ZERO change across optimization rounds.
  Must clear eval cache before each scenario (`rm -rf ~/.cache/nix/eval-cache-v*`). Must use `--export-json` for machine-readable before/after comparison. `--runs 12` (not 5) is required for statistical significance — nix eval variance is 3-8%, and 5 runs produces confidence intervals too wide for gating at 5%. Do NOT run nix build (no building), only `--dry-run` or `nix eval`. Do NOT use `.#odin` — correct attribute is the full path. Accept `NIXPKGS_SLIM_PATH` env var to override nixpkgs path.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 4, 5
  References (executor has NO interview context - be exhaustive):
    - `/etc/nixos/scripts/dev/check-hyprland-vars.sh` — existing script pattern at repo-root `scripts/dev/` (NOT `packages/scripts/dev/`)
    - `/etc/nixos/modules/dev/pkgs/default.nix:8` — hyperfine is in dev pkgs (system)
    - `/etc/nixos/docs/runbooks/debug-slow-deploy.md:14` — eval cache clearing (`rm -rf ~/.cache/nix/eval-cache-v*`)
    - `/etc/nixos/flake/nixos.nix:241` — nixosConfiguration "odin"
    - `/etc/nixos/flake/nixos.nix:231-236` — test configs "odin-lite", "odin-gaming"
    - `/etc/nixos/modules/nix/settings.nix:53` — `eval-cache = true`
    - Correct flake target: `/etc/nixos/flake/nixos.nix:241`; Justfile:39
    - Hyperfine export: `--export-json` produces structured JSON for comparison
    - Flake input: `nixpkgs.url = "github:neg-serg/nixpkgs-slim/ffdb45b47..."` — pinned remote; override needed for local changes
  Acceptance criteria (agent-executable):
    - `NIXPKGS_SLIM_PATH=/tmp/nixpkgs-slim bash scripts/dev/nix-eval-bench.sh` runs hyperfine on all 3 scenarios
    - JSON output file at `benchmarks/bench_full_odin_<date>.json`, `bench_odin_lite_<date>.json`, `bench_raw_eval_<date>.json`
    - Each scenario completes without errors (exit 0)
    - Validation gate: improvement claimed only if Δ > 2× combined stddev (pre + post)
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-2-nixpkgs-slim-flamegraph.log`
    - Happy: run script, check JSON has `"results"` array with 12 entries each, `"mean"` and `"stddev"` fields present → pass
    - Failure: run with non-existent flake attr → script exits non-zero with clear error message → pass
    - Statistical: improvement < 2× stddev → mark "NOT STATISTICALLY SIGNIFICANT" in comparison → pass (honest result)
  Commit: Y | `[dev/scripts] Add nix-eval-bench.sh: hyperfine eval benchmark for nixpkgs-slim`

- [x] 3. Create nix-flamegraph.sh one-shot flamegraph generator
  What to do / Must NOT do: Create `/etc/nixos/scripts/dev/nix-flamegraph.sh` (repo root, NOT under `packages/`). Script runs:
    (1) Check `perf_event_paranoid <= 1` — exit with clear error if not (user must set `kernel.perf_event_paranoid=1` or run as root). If root: `sudo perf record ... && sudo chown $USER:$USER perf.data` so post-processing works.
    (2) `mkdir -p benchmarks/$(date +%Y-%m-%d_%H-%M-%S)_odin && cd` into it
    (3) Clear eval cache: `rm -rf ~/.cache/nix/eval-cache-v*`
    (4) `perf record -g --call-graph dwarf -F 99 -o perf.data nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs ${NIXPKGS_SLIM_PATH:-/tmp/nixpkgs-slim}`
    (5) `perf script -i perf.data | inferno-collapse-perf > stacks.folded` (or `stackcollapse-perf.pl` if fallback)
    (6) `inferno-flamegraph stacks.folded > flamegraph.svg` (or `flamegraph.pl`)
    (7) Cleanup `perf.data` and temp files; chown output files to $USER if ran as root
  Must use `--call-graph dwarf` — Determinate Nix binary on this system is NOT stripped (confirmed: has `.eh_frame` for DWARF unwinding, `.dynsym` for symbol names). `--call-graph fp` as fallback if symbols are missing. Must use `--override-input nixpkgs` so flamegraph reflects the local nixpkgs-slim, not pinned remote. Accept hostname arg (default "odin") — derive both flake attribute and output dir name from it. Flamegraph tool: try `inferno-flamegraph` first, fall back to `flamegraph.pl`. Must NOT use `-a` (system-wide). After running as root: `sudo chown -R $SUDO_USER:$SUDO_USER benchmarks/` to fix ownership.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 6
  References (executor has NO interview context - be exhaustive):
    - Brendan Gregg flamegraph convention: 99 Hz, dwarf call-graph (`https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html`)
    - Inferno usage: `inferno-collapse-perf` reads stdin, `inferno-flamegraph` writes SVG
    - FlameGraph (Perl fallback): `stackcollapse-perf.pl` → `flamegraph.pl`
    - `/etc/nixos/scripts/dev/` — actual scripts directory (NOT `packages/scripts/dev/`)
    - `/etc/nixos/docs/runbooks/debug-slow-deploy.md:14` — eval cache clearing
    - Correct flake target: `/etc/nixos/flake/nixos.nix:241-242` — `nixosConfigurations.odin`
    - Flake override: `--override-input nixpkgs /tmp/nixpkgs-slim` — required for local modifications
    - Determinate Nix binary: `/run/current-system/sw/bin/nix` — "not stripped", has `.eh_frame` + `.dynsym`
  Acceptance criteria (agent-executable):
    - Running script produces `flamegraph.svg` in output dir
    - SVG is valid: file size > 10KB, contains `<svg` tag
    - `perf.data` is cleaned up after generation
    - perf_event_paranoid check: exits with clear error if `$(cat /proc/sys/kernel/perf_event_paranoid) -gt 1`
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-3-nixpkgs-slim-flamegraph.log`
    - Happy: `sudo bash scripts/dev/nix-flamegraph.sh odin` → SVG exists, `file flamegraph.svg` reports "SVG" → pass
    - Failure: run without sudo and `perf_event_paranoid=2` → script exits 1 with "Set kernel.perf_event_paranoid=1 or run as root" → pass
    - Ownership: `sudo bash ... && ls -la benchmarks/*/flamegraph.svg | awk '{print $3}'` shows $SUDO_USER → pass
  Commit: Y | `[dev/scripts] Add nix-flamegraph.sh: perf+Inferno flamegraph for nix eval`

### Wave 2 — Baseline + Analysis

- [x] 4. Add Justfile targets for flamegraph and benchmark
  What to do / Must NOT do: Add two targets to `/etc/nixos/Justfile`: `bench-eval` (runs `scripts/dev/nix-eval-bench.sh`) and `flamegraph-eval host=odin` (runs `scripts/dev/nix-flamegraph.sh`). Add a grouped alias `profile-eval: bench-eval flamegraph-eval`. Follow existing Justfile style (`just` not `just ...`). Do NOT add targets for building or deploying.
  Parallelization: Wave 2 | Blocked by: 2, 3 | Blocks: —
  References (executor has NO interview context - be exhaustive):
    - `/etc/nixos/Justfile:46` — existing Justfile deployment targets
    - `/etc/nixos/Justfile:178` — `show-features` target pattern
  Acceptance criteria (agent-executable):
    - `just bench-eval` invokes `scripts/dev/nix-eval-bench.sh`
    - `just flamegraph-eval` invokes `scripts/dev/nix-flamegraph.sh odin`
    - `just profile-eval` runs both sequentially
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-4-nixpkgs-slim-flamegraph.log`
    - Happy: `just bench-eval` runs benchmark → pass
    - Failure: `just flamegraph-eval` without sudo → script exits with clear error (no hang) → pass
  Commit: Y | `[dev/just] Add bench-eval and flamegraph-eval Justfile targets`

- [x] 5. Collect eval baseline benchmarks
  What to do / Must NOT do: Run `just bench-eval` from `/etc/nixos` to collect baseline timing data for the 3 scenarios. Save results. Record the nixpkgs-slim commit SHA (`git -C /tmp/nixpkgs-slim rev-parse HEAD`) as part of baseline metadata. This is the reference point ALL optimizations compare against. Do NOT skip the eval cache clearing step — cache must be cold for reproducible baseline.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: 7, 8, 9
  References (executor has NO interview context - be exhaustive):
    - `/etc/nixos/benchmarks/` — gitignored output dir
    - `/tmp/nixpkgs-slim` — nixpkgs fork repo on main branch
  Acceptance criteria (agent-executable):
    - `benchmarks/baseline-*.json` exists with 3 hyperfine results
    - Each scenario has: mean, stddev, min, max, runs=12
    - Baseline metadata includes nixpkgs-slim commit SHA
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-5-nixpkgs-slim-flamegraph.log`
    - Happy: baseline JSON has all 3 scenarios with non-zero mean times → pass
    - Failure: any scenario times out (>300s) → record as "too-slow" and flag for optimization priority → pass (still records baseline)
  Commit: N (data artifact, committed as baseline reference separately)

- [x] 6. Generate flamegraph and analyze hot-paths
  What to do / Must NOT do: Run `just flamegraph-eval` to generate flamegraph SVG. Analyze the flamegraph for eval hot-paths. Focus on: (a) wide stacks = deep call chains eating CPU, (b) functions with large horizontal width = high self-time. Key functions to check: `callPackage`, `nix::EvalState::forceValue`, `nix::Bindings::find`, `nix::PrimOp::call`, `nix::Value::mkAttrs`, `nix::evalFile`, `nix::Parser::parseStmt`. Document top 3-5 hot-paths with function names, file:line (from perf report), and estimated % of total eval time. Save analysis to `benchmarks/<ts>_odin/hotpaths.md`. Do NOT start optimizing yet.
  Parallelization: Wave 2 | Blocked by: 3, 5 | Blocks: 7, 8, 9
  References (executor has NO interview context - be exhaustive):
    - `/etc/nixos/docs/runbooks/debug-slow-deploy.md:79` — key nix internals to watch
    - `/etc/nixos/docs/howto/build-optimization.md` — known eval bottlenecks in NixOS
    - nixpkgs-slim by-name overlay: `/tmp/nixpkgs-slim/pkgs/top-level/by-name-overlay.nix`
    - nixpkgs-slim types.nix: `/tmp/nixpkgs-slim/lib/types.nix`
    - nixpkgs-slim module list: `/tmp/nixpkgs-slim/nixos/modules/module-list.nix`
  Acceptance criteria (agent-executable):
    - `flamegraph.svg` is generated and readable (open in browser shows colored stacks)
    - `hotpaths.md` lists 3+ identified hot-paths with function names and estimated % impact
    - Each hot-path maps to a specific file:line in nixpkgs-slim or nixpkgs
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-6-nixpkgs-slim-flamegraph.log`
    - Happy: `perf report -i perf.data --stdio | head -50` shows recognizable nix functions → pass
    - Failure: flamegraph is blank or shows only kernel symbols → check `--call-graph dwarf` is set, retry → pass (self-healing)
  Commit: N (analysis artifact)

### Wave 3 — Optimization (sequential per hot-path)

> Each todo below is a TEMPLATE repeated once per hot-path identified in task 6. The executor must fill in the hot-path specifics from `hotpaths.md`. Optimizations are sequential: each must complete and be verified before the next begins, to avoid measurement interference.
> 
> **C3 Exit conditions (hard limits):**
> - Max 3 optimization rounds (one per hot-path with >2% estimated impact)
> - For each round: if improvement < 2% vs baseline AND < 2× baseline stddev → STOP (diminishing returns / noise floor)
> - If improvement 2-5% AND > 2× stddev → mark as MARGINAL, commit, continue to next round
> - If improvement ≥5% AND > 2× stddev → mark as EFFECTIVE, commit, continue
> - Stop immediately if optimization changes system closure (identity violation — see guard below)
> 
> **C3 Correctness guard (must pass for EVERY optimization):**
> 1. `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs /tmp/nixpkgs-slim` succeeds
> 2. Closure identity: capture pre-optimization planned output paths list, compare with post-optimization:
>    ```bash
>    nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --json --override-input nixpkgs /tmp/nixpkgs-slim | jq '.[].outputs.out' | sort | sha256sum
>    ```
>    Hash must match pre-optimization hash. (Note: `nix path-info` on a flake attr does NOT work — confirmed on this system. Use `--dry-run --json` instead.)
> 3. If hash differs → revert the optimization immediately via `git revert`, document why it changed, mark as FAILED
> 4. After all Wave 3 optimizations: run FULL BUILD (no --dry-run) as final validation:
>    `nix build .#nixosConfigurations.odin.config.system.build.toplevel --no-link --override-input nixpkgs /tmp/nixpkgs-slim`
>    If build fails → revert ALL Wave 3 commits, tag as `opt/flamegraph-failed`.
> 
> **C3 Baseline protection:** Before first optimization: `git -C /tmp/nixpkgs-slim stash && git -C /tmp/nixpkgs-slim tag baseline-flamegraph && git -C /tmp/nixpkgs-slim checkout -b opt/flamegraph && git -C /tmp/nixpkgs-slim stash pop` (stash any dirty state, tag clean HEAD, create branch, restore WIP). All optimizations committed to `opt/flamegraph` branch. Verify no uncommitted changes before tagging: `git -C /tmp/nixpkgs-slim diff --stat` must be empty or stashed.

- [x] 7. Optimize hot-path #1 (highest-impact from flamegraph)
  What to do / Must NOT do: Implement optimization for the #1 hottest function/pattern found in task 6. Target is `/tmp/nixpkgs-slim` on `opt/flamegraph` branch (created from `baseline-flamegraph` tag). Typical candidates: by-name overlay overhead (reduce whitelist lookups, pre-sort, hash), module system eval depth (merge fewer options), `callPackage` chains (flatten, memoize). Each optimization must: (a) not change eval correctness (`nix build --dry-run --override-input nixpkgs /tmp/nixpkgs-slim` succeeds), (b) not change system closure (run `--dry-run --json | jq | sort | sha256sum` before/after — must match), (c) reduce eval time measurably (improvement must exceed 2× baseline stddev AND be ≥2% to NOT trigger STOP). Do NOT touch `lib/modules.nix`. Do NOT remove packages from whitelist. Run `just bench-eval` with `NIXPKGS_SLIM_PATH=/tmp/nixpkgs-slim` after optimization.
  Parallelization: Wave 3 | Blocked by: 6 | Blocks: 8
  References (executor has NO interview context - be exhaustive):
    - nixpkgs-slim `/tmp/nixpkgs-slim/pkgs/top-level/by-name-overlay.nix` — current whitelist
    - nixpkgs-slim `/tmp/nixpkgs-slim/lib/types.nix` — current type check optimization
    - nixpkgs-slim `/tmp/nixpkgs-slim/nixos/modules/module-list.nix` — current module list
    - `/etc/nixos/docs/howto/build-optimization.md:29` — import overhead per module
    - Benchmark baseline: `benchmarks/bench_full_odin_<date>.json`
    - Hot-path analysis: `benchmarks/<ts>_odin/hotpaths.md`
    - Closure identity check: `nix build ... --dry-run --json | jq '.[].outputs.out' | sort | sha256sum` (NOT `nix path-info` — confirmed non-functional for flake attrs)
  Acceptance criteria (agent-executable):
    - `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs /tmp/nixpkgs-slim` succeeds
    - Closure hash matches pre-optimization hash (via `--dry-run --json` pipeline)
    - `just bench-eval` with `NIXPKGS_SLIM_PATH=/tmp/nixpkgs-slim`: improvement > 2× baseline stddev; if ≥5% → EFFECTIVE; if 2-5% → MARGINAL; if <2% or < 2× stddev → STOP (no next round)
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-7-nixpkgs-slim-flamegraph.log`
    - Happy: eval time drops ≥5%, dry-run passes, hash matches → commit → pass
    - Marginal: eval time drops 2-5% but > 2× stddev → commit as `[perf/eval/marginal]`, record → pass
    - Stop: improvement <2% or < 2× stddev → document, skip tasks 8-9 → pass (exit condition works)
    - Failure: hash changes → `git revert`, document root cause, mark FAILED → pass
  Commit: Y | `[perf/eval] <TBD>` in `/tmp/nixpkgs-slim`

- [x] 8. Optimize hot-path #2 (second-highest impact)
  What to do / Must NOT do: Same template as task 7, applied to the #2 hot-path. Must build on the state AFTER task 7 (i.e., on the `opt/flamegraph` branch with task 7's commit). Verify against original baseline (NOT post-task-7 time). All `nix build` and bench commands must include `--override-input nixpkgs /tmp/nixpkgs-slim`. Skip if task 7 triggered STOP.
  Parallelization: Wave 3 | Blocked by: 7 | Blocks: 9
  References: Same as task 7 + updated state of `/tmp/nixpkgs-slim` on `opt/flamegraph` branch.
  Acceptance criteria: Same as task 7 — improvement vs original baseline, > 2× stddev, closure hash unchanged.
  QA scenarios: Same as task 7, Evidence `.omo/evidence/task-8-nixpkgs-slim-flamegraph.log`
  Commit: Y | `[perf/eval] <TBD>` in `/tmp/nixpkgs-slim`

- [x] 9. Optimize hot-path #3 (if identified; otherwise mark SKIP)
  What to do / Must NOT do: Same template as task 8, for #3 hot-path. If `hotpaths.md` only identified 2 viable hot-paths OR task 7/8 triggered STOP, mark this SKIP with rationale. If #3 exists but has <2% estimated impact, mark SKIP with "impact below noise floor." All commands must include `--override-input nixpkgs /tmp/nixpkgs-slim`.
  Parallelization: Wave 3 | Blocked by: 8 | Blocks: —
  References: Same as task 8.
  Acceptance criteria: Same as task 7 OR documented SKIP with rationale.
  QA scenarios: Same as task 7, Evidence `.omo/evidence/task-9-nixpkgs-slim-flamegraph.log`
  Commit: Y | `[perf/eval] <TBD>` in `/tmp/nixpkgs-slim` (or N if SKIP)

### Wave 4 — Final verification

- [x] 10. Post-optimization flamegraph + final benchmark comparison
  What to do / Must NOT do: Generate a fresh flamegraph from optimized nixpkgs-slim: `NIXPKGS_SLIM_PATH=/tmp/nixpkgs-slim just flamegraph-eval`. Run final benchmark: `NIXPKGS_SLIM_PATH=/tmp/nixpkgs-slim just bench-eval`. Compare: (a) old flamegraph vs new flamegraph — hot-paths should be visibly narrower, (b) baseline benchmarks vs final benchmarks — each scenario should show improvement where expected (scenarios 1-2 may improve; scenario 3 uses upstream nixpkgs and should show NO change). Statistical gate: only claim improvement if Δ > 2× combined stddev. Write comparison summary to `benchmarks/<ts>_odin/comparison.md`. Run final build validation: `nix build .#nixosConfigurations.odin.config.system.build.toplevel --no-link --override-input nixpkgs /tmp/nixpkgs-slim` must succeed. Do NOT claim improvement without statistical significance.
  Parallelization: Wave 4 | Blocked by: 7, 8, 9 | Blocks: —
  References (executor has NO interview context - be exhaustive):
    - Old flamegraph: `benchmarks/<first_ts>_odin/flamegraph.svg`
    - Old baseline: `benchmarks/bench_full_odin_<date>.json` etc.
    - New flamegraph: to be generated
    - New benchmark: to be generated
    - Statistical gate: improvement claimed only if Δ > 2× (stddev_pre + stddev_post)
  Acceptance criteria (agent-executable):
    - New flamegraph generated successfully
    - New benchmark JSON has 3 scenarios with 12 runs each
    - `comparison.md` documents per-scenario improvement % + statistical significance (Δ vs 2×stddev)
    - Full build (`--no-link`, no `--dry-run`) succeeds
    - Scenario 3 (upstream nixpkgs) shows Δ < 2× stddev (no false positive)
  QA scenarios (name the exact tool + invocation): happy + failure, Evidence `.omo/evidence/task-10-nixpkgs-slim-flamegraph.log`
    - Happy: comparison.md shows 3 scenarios, statistical gate applied → pass
    - Full build: `nix build ... --no-link --override-input nixpkgs /tmp/nixpkgs-slim` exits 0 → pass
    - Failure: no statistically significant improvement → document honestly → pass (valid result)
    - Failure: full build fails → revert all Wave 3 commits, tag `opt/flamegraph-failed` → pass (safety gate)
  Commit: N (analysis artifact)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit: every todo has references + acceptance + QA + commit; no scope creep; dependency matrix consistent; todos 7-9 are sequentially ordered and each builds on prior state
- [x] F2. Code quality review: nix-flamegraph.sh and nix-eval-bench.sh are shellcheck-clean, follow existing script patterns from profile-deploy.sh; nixpkgs-slim commits are atomic and well-described
- [x] F3. Real manual QA: `just flamegraph-eval` produces valid SVG (visually inspect one); `just bench-eval` produces 3 results; `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run` still succeeds after all optimizations
- [x] F4. Scope fidelity: nixos-config modules/hosts/overlays unchanged (git diff origin/main -- modules/ hosts/ packages/ is empty except for scripts/dev/ and Justfile); nixpkgs-slim changes are in eval path only (no package hash changes)

## Commit strategy
- **Repo: /etc/nixos** — tasks 1-4 produce commits under `[dev/tools]`, `[dev/scripts]`, `[dev/just]` prefixes
- **Repo: /tmp/nixpkgs-slim** — tasks 7-9 produce commits under `[perf/eval]` prefix with specific optimization description
- **Artifacts only** (no commit): tasks 5, 6, 10 — benchmark JSONs, flamegraph SVGs, analysis markdown files saved to `benchmarks/`
- **Atomic per optimization**: each task 7-9 = one commit; revertible independently
- **No squash**: keep optimization history for future reference

## Success criteria
1. `just flamegraph-eval` produces a valid flamegraph SVG showing nix eval call stacks
2. `just bench-eval` produces reproducible benchmark JSONs (12 runs per scenario, stddev documented)
3. At least one nixpkgs-slim scenario (1 or 2) shows statistically significant improvement (Δ > 2× combined stddev) vs baseline
4. Scenario 3 (upstream nixpkgs) shows NO statistically significant change (Δ < 2× stddev) — validates benchmark stability
5. `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs /tmp/nixpkgs-slim` succeeds before AND after all optimizations
6. Full build (`--no-link`, no `--dry-run`) succeeds after all optimizations
7. Zero changes to `/etc/nixos/modules/`, `/etc/nixos/hosts/`, `/etc/nixos/packages/overlays/`
8. nixpkgs-slim optimizations do not change system closure (verified via `--dry-run --json` hash)
9. All commits on `/tmp/nixpkgs-slim` are on `opt/flamegraph` branch, tagged from `baseline-flamegraph`
