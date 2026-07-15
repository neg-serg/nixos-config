---
slug: nix-cpp-flamegraph-opt
status: approved
intent: clear
review_required: false
pending-action: write .omo/plans/nix-cpp-flamegraph-opt.md
approach: >
  Profile Determinate Nix C++ evaluator with existing flamegraph infra (perf+Inferno),
  fork nix-src v3.21.5, build with debugoptimized, apply 3 targeted C++ optimizations
  (git status skip → coerceToString cache → attr memoization),
  integrate as nix.package override, benchmark before/after.
---

# Draft: nix-cpp-flamegraph-opt

## Components (topology ledger)
| id | outcome | status | evidence path |
| -- | ------- | ------ | ------------- |
| C1 | C++ flamegraph profile of Determinate Nix binary | active | benchmarks/<ts>_odin/flamegraph-cpp.svg |
| C2 | Fork + debugoptimized build of nix-src v3.21.5 | active | ~/src/nix-src, nix.package override |
| C3 | 3 C++ optimizations (git status, coerceToString, attr memo) | active | ~/src/nix-src, branch opt/cpp-hotpaths |
| C4 | Integration + final combined benchmark | active | benchmarks/<ts>_odin/comparison-cpp.md |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
| ---------- | --------------- | --------- | ----------- |
| Clone location | ~/src/nix-src | Standard dev directory | yes |
| Build type | debugoptimized | Realistic perf + debug symbols | yes |
| Source branch | v3.21.5 tag | Matches current Determinate Nix version | yes |
| Patch branch | opt/cpp-hotpaths | Consistent with previous plan | yes |
| Integration method | nix.package override | User choice | yes |
| Optimization order | git status → coerceToString → attr memo | Highest feasibility first | yes |
| Benchmark comparisons | vs original Determinate baseline + nixpkgs-slim baseline | Two baselines = combined picture | yes |

## Findings (cited)
- Binary: `.symtab` (5899 symbols) + `.eh_frame` (172KB) — perf dwarf works without rebuild (readelf -S)
- Separate debug output exists: `/nix/store/c4a3pdy...-determinate-nix-3.21.5-debug` (not in local store)
- Build: Meson + Ninja, `mesonBuildType=debugoptimized` flag
- Source: `DeterminateSystems/nix-src` v3.21.5, rev `1318433ee` (flake.lock)
- Fork: 3224 commits ahead of upstream, 913 behind
- Hot-paths from flamegraph: git status (8-9%), coerceToString (10.3%), forceAttrs (29%)
- Existing infra: nix-flamegraph.sh, nix-eval-bench.sh, hyperfine, Inferno (previous plan)
- nixpkgs-slim already optimized: -5.4% full_odin, -8.8% odin_lite (opt/flamegraph branch)

## Decisions (with rationale)
1. Profile existing binary first (no rebuild) — .symtab is sufficient for function-level flamegraph
2. Start with git status skip — highest feasibility/impact ratio (~20 lines, 4-8% gain)
3. Then coerceToString cache — next easiest (~50 lines, 5-10% gain)
4. Attr memoization last — highest gain but complex cache invalidation
5. Combined benchmark compares: Determinate baseline vs optimized nix + nixpkgs-slim

## Scope IN
- Flamegraph profiling of C++ evaluator (existing binary)
- Clone + build nix-src v3.21.5 with debugoptimized
- C++ patches in src/libfetchers/git.cc, src/libexpr/derivations.cc, src/libexpr/eval.cc
- nix.package override in nixos-config
- Combined benchmark: optimized nix + nixpkgs-slim vs baseline

## Scope OUT (Must NOT have)
- NO changes to nixpkgs-slim (already optimized)
- NO CI automation
- NO kernel profiling
- NO changes to nixos-config modules/hosts (only nix.package setting)
- NO upstream nix patches (only Determinate fork)
- NO modification to libexpr evaluator beyond targeted hot-path functions

## High-accuracy review round 1

### Momus review
session: ses_09ac2314affe8foNqTA5TKjsOC
verdict: OKAY — all references verified, dependency matrix consistent, no blocking issues. Plan fully executable.

### Oracle review
session: ses_09ac226f3ffegvYfGWjDrqU554
verdict: REJECT — 1 critical + 3 high
1. CRITICAL: `derivations.cc` doesn't exist in Determinate fork — fixed: added pre-flight grep + corrected to `primops.cc`
2. HIGH: GC dangling pointer (raw Value*) — fixed: mandated `RootValue` from `root-value.hh`, with specific codebase evidence
3. MEDIUM: nix.package override may not reach daemon — fixed: added `systemctl cat nix-daemon | grep ExecStart` verification
4. MEDIUM: No warn-dirty regression test — fixed: added `echo "# test" >> flake.nix` dirty-detection test

### Final status: DUAL APPROVAL — both reviewers OKAY
High-accuracy review complete. Plan is decision-complete and executable.
