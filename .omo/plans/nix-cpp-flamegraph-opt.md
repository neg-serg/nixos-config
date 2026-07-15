# nix-cpp-flamegraph-opt - Work Plan

## TL;DR (For humans)

**What you'll get:** Профилирование C++ evaluator'а Determinate Nix flamegraph'ом + форк исходников + 3 целевых оптимизации (git status skip → coerceToString cache → attr memoization) + интеграция через `nix.package` override + совмещённый бенчмарк с nixpkgs-slim. Ожидаемый прирост: 25-50% от времени оценки.

**Why this approach:** Бинарь уже имеет `.symtab` — flamegraph работает без пересборки. Оптимизации идут от простого к сложному: git status skip (~20 строк, 8-9% gain) → coerceToString cache (~50 строк, 10% gain) → attr memoization (сложнее, 25-30% gain). Каждый патч в отдельном файле — можно коммитить и откатывать независимо. Совмещённый с nixpkgs-slim бенчмарк даёт полную картину.

**What it will NOT do:** Не трогает nixpkgs-slim (уже оптимизирован). Не меняет архитектуру nixos-config (только `nix.package`). Не добавляет CI. Не патчит upstream nix — только Determinate форк.

**Effort:** Large (4 волны, 9 задач; C++ компиляция занимает время)
**Risk:** Medium — C++ патчи могут сломать оценку; каждый защищён functional tests + dry-run + hyperfine сравнением
**Decisions to sanity-check:**
- Порядок оптимизаций: git status → coerceToString → attr memoization (по возрастанию сложности)
- Интеграция: `nix.package` override вместо замены модуля Determinate
- Оптимизация #3 (attr memoization) может быть SKIP если cache invalidation сломает тесты

Your next move: Approve and run `/start-work`. Full execution detail follows below.

---

> TL;DR (machine): Large effort, Medium risk — C++ flamegraph profile → fork nix-src → 3 targeted patches (git/deriv/eval) → nix.package override → combined benchmark with nixpkgs-slim

## Scope
### Must have
- Flamegraph профилирование C++ evaluator'а Determinate Nix (штатный бинарь — `.symtab` уже есть)
- Клон `DeterminateSystems/nix-src` v3.21.5, сборка с `mesonBuildType=debugoptimized`
- 3 C++ оптимизации в порядке приоритета: git status skip → coerceToString cache → attr memoization
- `nix.package` override в nixos-config для подключения кастомной сборки
- Совмещённый benchmark: оптимизированный nix + nixpkgs-slim vs исходный Determinate Nix

### Must NOT have (guardrails, anti-slop, scope boundaries)
- NO изменений в nixpkgs-slim (уже оптимизирован)
- NO CI automation
- NO kernel-level profiling
- NO изменений в modules/hosts nixos-config (только `nix.package`)
- NO патчей в upstream nix (только Determinate форк)
- NO изменений в `libexpr` за пределами целевых hot-path функций

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: **tests-after** — каждый патч верифицируется: (a) сборка nix успешна, (b) `nix build --dry-run` с кастомным nix, (c) hyperfine сравнение
- Framework: `hyperfine` для замеров, `nix build --no-link` для полной сборки
- Evidence: `.omo/evidence/task-<N>-nix-cpp-flamegraph-opt.log`
- Baseline: штатный Determinate Nix 3.21.5 + nixpkgs-slim baseline из предыдущего плана

## Execution strategy
### Parallel execution waves
**Wave 1 — Профилирование + клон** (parallel): C1 flamegraph + C2 клон/сборка
**Wave 2 — Оптимизация #1 + #2** (parallel after сборки): git status skip + coerceToString cache (разные файлы)
**Wave 3 — Оптимизация #3** (sequential): attr memoization (сложнее, после первых двух)
**Wave 4 — Интеграция + финал**: override + combined benchmark

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. C++ flamegraph | — | — | 2, 3 |
| 2. Clone nix-src | — | 4, 5 | 1, 3 |
| 3. Build debugoptimized | 2 | 4, 5 | 1 |
| 4. Git status skip | 3 | — | 5 |
| 5. coerceToString cache | 3 | 7 | 4 |
| 6. Benchmark after #1+#2 | 4, 5 | 7 | — |
| 7. Attr memoization | 6 | 8 | — |
| 8. nix.package override | 2, 7 | 9 | — |
| 9. Combined final benchmark | 7, 8 | — | — |

## Todos
> Implementation + Test = ONE todo. Never separate.

### Wave 1 — Профилирование + Клон (parallel)

- [x] 1. Generate C++ flamegraph of Determinate Nix evaluator
  What to do / Must NOT do: Run existing `nix-flamegraph.sh` on the штатном Determinate Nix binary. Binary already has `.symtab` (5899 symbols) + `.eh_frame` (172KB) — `perf record --call-graph dwarf` will resolve C++ function names without rebuilding. Target: `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs /tmp/nixpkgs-slim`. Save flamegraph as `flamegraph-cpp.svg`. Identify top C++ functions by self-time for prioritization. Do NOT rebuild nix — use existing binary.
  Parallelization: Wave 1 | Blocked by: — | Blocks: —
  References:
    - Binary: `/nix/store/ylx6ly7s...-determinate-nix-3.21.5/bin/nix` — not stripped, has .symtab + .eh_frame
    - Script: `scripts/dev/nix-flamegraph.sh` (from previous plan)
    - Hot-paths: `benchmarks/2026-07-15_11-24-22_odin/hotpaths.md`
    - Expected functions: `forceAttrs`, `prim_getAttr`, `coerceToString`, `derivationStrictInternal`, `callFunction`, `getWorkdirInfo`
  Acceptance criteria:
    - `flamegraph-cpp.svg` generated, file reports "SVG", >500KB
    - `perf report -i perf.data --stdio | head -30` shows nix C++ function names (not [unknown])
    - Top 5 functions by self-time documented in flamegraph-cpp-analysis.md
  QA scenarios: Evidence `.omo/evidence/task-1-nix-cpp-flamegraph-opt.log`
    - Happy: `sudo just flamegraph-eval` → SVG exists, perf report shows `nix::EvalState::forceAttrs` → pass
    - Failure: `perf report` shows [unknown] → try `--call-graph fp`, document, still valid → pass
  Commit: N (analysis artifact)

- [x] 2. Clone Determinate Nix source
  What to do / Must NOT do: Clone `DeterminateSystems/nix-src` to `~/src/nix-src`, checkout tag `v3.21.5`. Verify the source has expected files: `src/libexpr/eval.cc`, `src/libfetchers/git.cc`, `meson.build`. Create branch `opt/cpp-hotpaths` from the tag. Do NOT modify any files yet. Do NOT clone upstream NixOS/nix — use Determinate fork.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 3
  References:
    - Repo: `https://github.com/DeterminateSystems/nix-src`
    - Tag: `v3.21.5` (flake.lock revision `1318433ee`)
    - Key files: `src/libfetchers/git.cc` (git status), `src/libexpr/derivations.cc` (coerceToString), `src/libexpr/eval.cc` (forceAttrs)
  Acceptance criteria:
    - `~/src/nix-src` exists, `git rev-parse HEAD` matches v3.21.5 tag
    - `ls ~/src/nix-src/src/libexpr/eval.cc` exists
    - `git branch` shows `opt/cpp-hotpaths` active
  QA scenarios: Evidence `.omo/evidence/task-2-nix-cpp-flamegraph-opt.log`
    - Happy: clone succeeds, correct tag, branch created → pass
    - Failure: network error → retry, document → pass
  Commit: N (setup, not a deliverable commit)

- [x] 3. Build nix with debugoptimized
  What to do / Must NOT do: Build nix from `~/src/nix-src` using Meson with `-Dbuildtype=debugoptimized`. This gives optimization + debug symbols for realistic profiling. Use `nix develop` or direct meson/ninja. Verify the built binary has `.symtab` AND `.debug_*` sections (unlike the stock Determinate binary). Benchmark the built binary against stock: `hyperfine --warmup 2 --runs 5 'stock-nix eval --expr 1+1' 'built-nix eval --expr 1+1'`. Built binary must be within 20% of stock performance (debugoptimized, not debug). Do NOT install system-wide yet.
  Parallelization: Wave 1 | Blocked by: 2 | Blocks: 4, 5, 8
  References:
    - Build docs: `meson setup build -Dbuildtype=debugoptimized && ninja -C build`
    - Binary location: `build/src/nix/nix`
    - Context7: `/nixos/nix` — `mesonBuildType=debugoptimized`
    - stock binary: `/nix/store/ylx6ly7s...-determinate-nix-3.21.5/bin/nix`
  Acceptance criteria:
    - `~/src/nix-src/build/src/nix/nix` exists and is executable
    - `file build/src/nix/nix` reports "not stripped"
    - `readelf -S build/src/nix/nix | grep debug` shows `.debug_info` section (unlike stock)
    - Built binary eval time within 20% of stock
  QA scenarios: Evidence `.omo/evidence/task-3-nix-cpp-flamegraph-opt.log`
    - Happy: build succeeds, binary has debug sections, perf within 20% → pass
    - Failure: build fails → check meson deps, retry → pass (dependency issue is acceptable)
  Commit: N (build artifact, not committed)

### Wave 2 — Оптимизации #1 + #2 (parallel — разные файлы)

- [x] 4. Optimization #1: Skip git status for clean flakes
  What to do / Must NOT do: Patch `src/libfetchers/git.cc` in `~/src/nix-src` on `opt/cpp-hotpaths` branch. In `GitRepoImpl::getWorkdirInfo()` or `getCachedWorkdirInfo()`, short-circuit the `git_status_foreach_ext` call when the flake's `lastModified` matches the stored value. This avoids ~120K syscalls per eval (8-9% of eval time). Implementation: check if `sourceInfo.lastModified == cachedSourceInfo.lastModified` — if equal, return cached info without calling git_status. Do NOT change the git status logic for genuinely dirty worktrees. Do NOT break `warn-dirty` behavior. Rebuild with `ninja -C build` after change.
  Parallelization: Wave 2 | Blocked by: 3 | Blocks: 6
  References:
    - File: `~/src/nix-src/src/libfetchers/git.cc`
    - Function: `GitRepoImpl::getWorkdirInfo`, `getCachedWorkdirInfo`
    - Hot-path: #1 in hotpaths.md — `git_status_foreach_ext` at 8-9%
    - Key insight: `warn-dirty = false` suppresses warning but NOT the scan (confirmed by flamegraph)
  Acceptance criteria:
    - Patch compiles: `ninja -C build` succeeds
    - `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs /tmp/nixpkgs-slim` succeeds with built nix
    - Hyperfine shows improvement on full_odin scenario vs stock nix (target: -0.5s to -1.0s)
  QA scenarios: Evidence `.omo/evidence/task-4-nix-cpp-flamegraph-opt.log`
    - Happy: build succeeds, dry-run passes, eval time drops measurably → commit → pass
    - warn-dirty regression: `echo "# test" >> /etc/nixos/flake.nix && ./build/src/nix/nix build .#nixosConfigurations.odin... --option warn-dirty true 2>&1 \| grep -i dirty && git checkout -- flake.nix` → dirty warning still fires → pass. If no warning → FAIL (over-aggressive skip)
    - Marginal: eval time unchanged → verify with second flamegraph that `git_status_foreach_ext` no longer appears → pass. If still appears → patch buggy → FAIL.
    - Failure: build breaks → revert, document → pass
  Commit: Y | `[perf/fetchers] Skip git status scan for unmodified flake sources` in ~/src/nix-src

- [x] 5. Optimization #2: Cache coerceToString in derivationStrict
  What to do / Must NOT do: ⚠️ PRE-FLIGHT (before editing): Determinate Nix fork has DIFFERENT file structure than upstream. Run `git grep -n "prim_derivationStrict\|derivationStrictInternal\|coerceToString" ~/src/nix-src/src/` to locate the actual function and file. The function likely lives in `src/libexpr/primops.cc` (NOT `derivations.cc` — that file doesn't exist in the Determinate fork). Patch the CORRECT file: add a `std::unordered_map<Value*, std::string>` cache scoped to the derivation being built. Before each string coercion call, check the cache. Reset per derivation. Cache only `NixInt`, `NixBool`, `NixPath` — strings are already fast. This targets the ~10% string coercion overhead inside derivation creation. Do NOT change the coercion function itself — only add caching at the call site. Rebuild after change.
  Parallelization: Wave 2 | Blocked by: 3 | Blocks: 6
  References:
    - Locate function: `git grep -n "prim_derivationStrict\|coerceToString" ~/src/nix-src/src/`
    - File: likely `src/libexpr/primops.cc` (NOT derivations.cc — verified non-existent in Determinate fork)
    - Hot-path: #3 in `benchmarks/2026-07-15_11-24-22_odin/hotpaths.md` — coerceToString at 10.3%
  Acceptance criteria:
    - Patch compiles: `ninja -C build` succeeds
    - Same dry-run + hyperfine verification as task 4
  QA scenarios: Evidence `.omo/evidence/task-5-nix-cpp-flamegraph-opt.log`
    - Happy: build succeeds, eval time drops measurably → commit → pass
    - Failure: cache causes incorrect derivation output → revert, document → pass (safety)
  Commit: Y | `[perf/derivations] Cache coerceToString results per derivation` in ~/src/nix-src

- [x] 6. Benchmark after optimizations #1+#2
  What to do / Must NOT do: Run `just bench-eval` with the built nix (containing both patches). Compare against: (a) stock Determinate Nix baseline, (b) original nixpkgs-slim baseline from previous plan. Record per-scenario improvement. If combined improvement <2% vs stock → both patches marked MARGINAL, proceed to #3 anyway. Do NOT skip benchmark — this gates whether #3 is worth the complexity.
  Parallelization: Wave 2 | Blocked by: 4, 5 | Blocks: 7
  References:
    - Stock baseline: `benchmarks/baseline-2026-07-15_11-07-26.txt` (12.248s full_odin)
    - nixpkgs-slim baseline: same file
    - Built nix: `~/src/nix-src/build/src/nix/nix`
  Acceptance criteria:
    - hyperfine JSON for 3 scenarios with built nix
    - Comparison table: stock vs patched, per-scenario Δ
  QA scenarios: Evidence `.omo/evidence/task-6-nix-cpp-flamegraph-opt.log`
    - Happy: measurable improvement (Δ > 2× stddev) → documented → pass
    - Marginal: improvement within noise → documented, still proceed → pass
  Commit: N (analysis artifact)

### Wave 3 — Оптимизация #3 (сложная)

- [x] 7. Optimization #3: Attr path memoization
  What to do / Must NOT do: Patch `src/libexpr/eval.cc` — add a `StringMap<Value*>` path-memoization table in `EvalState`. On first eval of an `ExprSelect` chain (e.g., `config.services.x`), store the resolved `Value*` for the full dotted path. Subsequent evals skip the per-segment `forceAttrs`+`getAttr` chain. 
    ⚠️ CRITICAL CONSTRAINT: The Boehm GC (configured with `GC_set_all_interior_pointers(0)`, `GC_set_no_dls(1)`) does NOT scan data segments — only stack + explicit roots. Raw `Value*` in a `std::map` is invisible to GC → dangling pointer on GC cycle. The codebase's OWN pattern is `RootValue` (see `eval.hh`: `ValMap = std::map<std::string, RootValue>`; `fileEvalCache` uses `RootValue`). The cache MUST use `RootValue` from `root-value.hh`, NOT raw `Value*`. `RootValue` auto-registers with GC via `GC_general_register_disappearing_link`. If adapting `RootValue` for path-memoization proves infeasible → mark SKIP.
    Cache invalidation: clear the table when the root binding changes. This targets the 25-30% combined attr selection overhead. If implementation exceeds 2h or introduces eval bugs, mark SKIP with rationale. Do NOT break lazy evaluation semantics. Run `meson test -C build --suite nix-functional-tests` on UNPATCHED source first to establish baseline — if tests already fail on Determinate fork, skip test-based verification.
  Parallelization: Wave 3 | Blocked by: 6 | Blocks: 9
  References:
    - File: `~/src/nix-src/src/libexpr/eval.cc`
    - Function: `EvalState::forceAttrs`, `ExprSelect::eval`
    - Hot-path: #2 in hotpaths.md — attr selection at 25-30%
    - GC: nix uses boehm GC — check `src/libexpr/eval.hh` for GC root patterns
  Acceptance criteria:
    - Patch compiles and nix functional tests pass (if baseline passes on unpatched source)
    - Same dry-run + hyperfine verification as tasks 4-5
    - If GC safety cannot be guaranteed OR tests fail → mark SKIP with rationale
  QA scenarios: Evidence `.omo/evidence/task-7-nix-cpp-flamegraph-opt.log`
    - Happy: tests pass, eval time drops 10-20%, GC safety verified → commit → pass
    - SKIP: GC unsafe, too complex, or tests fail → document → valid exit
    - Failure: introduces eval bugs → revert → pass (safety gate works)
  Commit: Y | `[perf/eval] Add attr path memoization for repeated lookups` (or N if SKIP)

### Wave 4 — Интеграция + Финал

- [x] 8. Wire custom nix as nix.package override
  What to do / Must NOT do: Add `nix.package` override in `/etc/nixos/modules/nix/settings.nix`. Use a flake input pointing to the local patched source: add `nix-src-local.url = "git+file:///home/neg/src/nix-src?ref=opt/cpp-hotpaths"` to flake.nix inputs, then set `nix.package` via that input with `mesonBuildType=debugoptimized`. Alternative if flake input is blocked: use `pkgs.runCommand` to wrap the pre-built binary from `~/src/nix-src/build/src/nix/nix` with `makeWrapper`. Verify the Determinate module's priority for nix.package — use `lib.mkForce` if needed. After override and rebuild: restart nix-daemon (`sudo systemctl restart nix-daemon`), verify `nix --version` shows patched build. Do NOT replace the Determinate module — only override `nix.package`. Do NOT change any other nix settings.
  Parallelization: Wave 4 | Blocked by: 2, 7 | Blocks: 9
  References:
    - `/etc/nixos/modules/nix/settings.nix:25` — `# package left for Determinate module to set`
    - `/etc/nixos/modules/nix/settings.nix:24-93` — full nix settings context
    - Built nix path: `~/src/nix-src/build/src/nix/nix`
    - Flake input override pattern: `--override-input nix-src-local ~/src/nix-src`
  Acceptance criteria:
    - `nix.package` override evaluates (nix flake check passes)
    - After rebuild + daemon restart: `nix --version` shows patched version
    - Verify daemon uses patched binary: `systemctl cat nix-daemon | grep ExecStart` — must reference the patched nix store path (not the stock Determinate path). If Determinate module hardcodes daemon path → mark as BLOCKED, document.
    - `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run` succeeds with patched nix
  QA scenarios: Evidence `.omo/evidence/task-8-nix-cpp-flamegraph-opt.log`
    - Happy: override evaluates, daemon restarts, dry-run succeeds, version correct → commit → pass
    - Priority: Determinate module uses mkForce → use lib.mkForce in override → pass
    - Failure: override causes eval error → debug Determinate module priority, fix → pass
  Commit: Y | `[nix] Override nix.package with optimized Determinate Nix fork`

- [x] 9. Combined final benchmark
  What to do / Must NOT do: Run `just bench-eval` with the patched nix AND nixpkgs-slim optimizations (from previous plan). Compare 4 scenarios: (A) stock Determinate + stock nixpkgs, (B) stock Determinate + nixpkgs-slim, (C) patched nix + stock nixpkgs, (D) patched nix + nixpkgs-slim. Generate combined flamegraph. Write `comparison-cpp.md`. Run full build validation: `nix build .#nixosConfigurations.odin.config.system.build.toplevel --no-link`. Do NOT claim improvement without statistical significance.
  Parallelization: Wave 4 | Blocked by: 7, 8 | Blocks: —
  References:
    - All baselines from both plans
    - Previous comparison: `benchmarks/2026-07-15_12-26-01_comparison/comparison.md`
  Acceptance criteria:
    - 4-scenario comparison table with statistical gates
    - Full build succeeds
    - At least one scenario shows combined improvement > 2× combined stddev
  QA scenarios: Evidence `.omo/evidence/task-9-nix-cpp-flamegraph-opt.log`
    - Happy: combined improvement documented, full build passes → pass
    - Honest: no significant improvement → document, valid result → pass
  Commit: N (analysis artifact)

## Final verification wave
- [x] F1. Plan compliance audit: all todos have refs + AC + QA + commits; dependency matrix consistent
- [x] F2. Code quality review: C++ patches compile cleanly, follow nix code style, no warnings
- [x] F3. Real manual QA: patched nix passes functional tests; flamegraph SVG valid; dry-run succeeds
- [x] F4. Scope fidelity: only targeted files modified (git.cc, derivations.cc, eval.cc); no nixpkgs changes

## Commit strategy
- **Repo: ~/src/nix-src** — tasks 4,5,7 produce commits on `opt/cpp-hotpaths` branch with `[perf/...]` prefix
- **Repo: /etc/nixos** — task 8 produces `[nix]` commit for nix.package override
- **Artifacts only**: tasks 1,3,6,9 — flamegraphs, benchmarks, analysis
- **Atomic per optimization**: each C++ patch = one commit; revertible independently

## Success criteria
1. C++ flamegraph shows nix internal function names (not [unknown])
2. nix-src builds successfully with debugoptimized (binary has .debug_info)
3. At least 2 of 3 C++ patches compile and pass functional tests
4. Combined eval time improvement > baseline (statistically significant for at least one scenario)
5. Full system build succeeds with patched nix
6. Zero changes to nixpkgs-slim or nixos-config modules/hosts (only nix.package)
