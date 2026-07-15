---
slug: nixpkgs-slim-flamegraph
status: approved
intent: clear
review_required: true
pending-action: write .omo/plans/nixpkgs-slim-flamegraph.md
approach: >
  Add flamegraph infrastructure (perf + Inferno) for nix eval profiling,
  create a benchmark harness (hyperfine) for nixpkgs-slim eval time,
  collect baseline, analyze hot-paths in flamegraph, implement optimizations,
  verify via dry-run + hyperfine before/after comparison.
---

# Draft: nixpkgs-slim-flamegraph

## Components (topology ledger)
| id | outcome | status | evidence path |
| -- | ------- | ------ | ------------- |
| C1 | Flamegraph infrastructure: Inferno + perf scripting | active | scripts/dev/nix-flamegraph.sh |
| C2 | Benchmark harness: hyperfine on full nixos config eval | active | scripts/dev/nix-eval-bench.sh, Justfile |
| C3 | nixpkgs-slim optimization: flamegraph-guided improvements | active | /tmp/nixpkgs-slim |

## Open assumptions (announced defaults)
Record any default you adopt instead of asking, so the user can veto it at the gate.
| assumption | adopted default | rationale | reversible? |
| ---------- | --------------- | --------- | ----------- |
| Flamegraph tool | Inferno (Rust) | User chose over Brendan Gregg Perl scripts | yes |
| Eval target | Full nixos config (.odin.config.system.build.toplevel) | User chose — most practical scenario | yes |
| Test strategy | Benchmarks before/after + dry-run | User chose — no CI regression guard | yes |
| perf sample rate | -F 99 (99 Hz) | Brendan Gregg standard — avoids lockstep sampling | yes |
| nixpkgs-slim branch | main (from /tmp/nixpkgs-slim) | One commit ahead of pinned cleanup-unused-services; main = development branch | yes |
| Benchmark iterations | hyperfine --warmup 1 --runs 5 | Warmup primes cache, 5 runs is enough for stable variance | yes |
| perf scope | user-space only (no -a) | nix eval is user-space CPU, kernel overhead is noise | yes |

## Findings (cited - path:lines)

### nixpkgs-slim current state
- Repo: `/tmp/nixpkgs-slim` — `neg-serg/nixpkgs-slim` on `main` branch (commit `47ec8b020`)
- Pinned in flake: `github:neg-serg/nixpkgs-slim/ffdb45b47...` (cleanup-unused-services branch)
- Eval optimizations already done:
  1. **By-name whitelist** — `pkgs/top-level/by-name-overlay.nix`: 5,223/21,388 packages, saves ~16,000 callPackage calls
  2. **Module slimming** — `nixos/modules/module-list.nix`: 243/2,053 modules (88% reduction)
  3. **types.package.check deferral** — `lib/types.nix`: `check = x: true` instead of `isDerivation x || isStorePath x`
- Not modified: `lib/modules.nix`, C++ builtins, fetchTree

### NixOS config eval architecture
- nixpkgs input: `github:neg-serg/nixpkgs-slim/ffdb45b47...` (`/etc/nixos/flake.nix:8`)
- nix binary: Determinate Systems nix-src v3.21.5 (`/etc/nixos/flake.lock:974`)
- Eval features: `parallel-eval`, `eval-cache`, `lazy-locks`, `blake3-hashes`, `ca-derivations` (`/etc/nixos/modules/nix/settings.nix:42-53`)
- Domain filter: 22 domains for odin, skips appimage/llm/web (`/etc/nixos/flake/nixos.nix:88-100`)
- A/B test configs: odin-lite, odin-server with restricted filters (`/etc/nixos/flake/nixos.nix:196-237`)

### Existing profiling infrastructure
- `profile-deploy.sh` — valgrind/callgrind + time on `nix build --dry-run` (`/etc/nixos/packages/scripts/dev/profile-deploy.sh`)
- `debug-slow-deploy.md` — runbook for profiling slow deploys (`/etc/nixos/docs/runbooks/debug-slow-deploy.md`)
- `hyperfine` in dev pkgs (`/etc/nixos/modules/dev/pkgs/default.nix:8`)
- `perf` in monitoring pkgs (`/etc/nixos/modules/monitoring/pkgs/default.nix`)
- NO flamegraph tooling exists anywhere
- NO eval benchmarks history (benchmarks/ dir is gitignored, empty)

### nix eval profiling approach
- nix-instantiate is the eval-only tool (no build)
- Determinate Nix has `nix eval` and `nix build --dry-run`
- Full config eval: `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run`
- For flamegraph: `perf record -g -F 99 nix-instantiate ...` or `nix build --dry-run`
- perf record needs dwarf or fp call-graph: `--call-graph dwarf` for C++ or `-g` for fp
- nix's `nix::EvalState::forceValue`, `nix::PrimOp::call`, `callPackage` are key functions to watch

### Decisions (with rationale)
1. **Inferno over FlameGraph** — user preference, Rust-native, no Perl dependency
2. **Full nixos config as primary target** — most practical, what actually runs during nixos-rebuild
3. **Benchmark before/after, no CI** — user chose simplicity over automation
4. **perf -F 99 with --call-graph dwarf** — C++ nix evaluator needs DWARF for accurate call stacks
5. **Work on nixpkgs-slim main branch** — development branch, one commit ahead of pinned

### Scope IN
- Inferno flamegraph package + dependency in flake (dev shell)
- Shell script: `scripts/dev/nix-flamegraph.sh` (perf record → Inferno → SVG)
- Shell script: `scripts/dev/nix-eval-bench.sh` (hyperfine on eval scenarios)
- Justfile targets: `just bench-eval`, `just flamegraph-eval`
- Baseline benchmarks recorded to `benchmarks/`
- nixpkgs-slim optimization commits based on flamegraph analysis
- Each optimization verified with hyperfine comparison + dry-run

### Scope OUT (Must NOT have)
- C++ nix evaluator changes (Determinate Nix binary stays as-is)
- nixos-config architecture changes (domain filter, module layout)
- CI regression automation (no .github/workflows for eval-time checks)
- Kernel-level profiling (perf events on kernel, AutoFDO)
- Heap profiling (heaptrack, valgrind massif)
- Any modification to /etc/nixos product code (modules, hosts, overlays)

### Open questions
(None — all resolved via interview)

## Metis gap analysis receipt
session: ses_09b689537ffeONfkCxkZd8f94W
verdict: 15 gaps found (3 Critical, 3 High, 7 Medium, 2 Low)
All critical and high gaps resolved — see plan for fixes.

## High-accuracy review round 1

### Momus review
session: ses_09b5b8148ffeF4pMINipTrs3IF
verdict: REJECT — 3 blocking issues
1. Task 1 references non-existent `packages/overlays/tools.nix` and `packages/overlay.nix` → fixed: replaced with `packages/flake/custom-packages.nix`
2. Tasks 2-3 reference non-existent `packages/scripts/dev/profile-deploy.sh` → fixed: changed to `/etc/nixos/scripts/dev/` with `check-hyprland-vars.sh` example
3. C3 "Min 5%" contradicts acceptance criteria → fixed: 3-tier system (≥5% EFFECTIVE, 2-5% MARGINAL, <2% STOP, all gated by >2× stddev)

### Oracle review
session: ses_09b5b687dffel4Uu20DLAVQdWE
verdict: REJECT — 3 critical + 3 high + 2 medium issues
F1. `nix path-info` guard non-functional → fixed: replaced with `--dry-run --json | jq | sort | sha256sum`
F2. `/tmp/nixpkgs-slim` disconnected from flake → fixed: ALL benchmark/flamegraph build commands now use `--override-input nixpkgs /tmp/nixpkgs-slim`
F3. 5 hyperfine runs insufficient → fixed: `--runs 12`, gate on >2× stddev
F4. No full build validation → fixed: added `--no-link` full build after all Wave 3
F5. Aggressive eval-cache deletion → documented: no concurrent nix ops during benchmarks
F6. sudo+perf ownership → fixed: `sudo chown $SUDO_USER` after perf record
F7. Scenario 3 tests upstream, not nixpkgs-slim → documented with rationale
F8. Flamegraph only for odin → hostname arg accepted for attribute derivation

### Fix summary
All 6 critical/high issues from both reviewers resolved in plan v2. Resubmitting for round 2.

## High-accuracy review round 2

### Momus round 2
session: ses_09b55e123ffeIOxXon4IGsk7hC
verdict: APPROVE — all 3 round-1 issues resolved
- Reference paths all exist (verified 10+ files)
- C3 threshold tiered system consistent between preamble and task ACs
- No new blocking issues

### Oracle round 2
session: ses_09b55d3a4ffejkDn66X8wMIUOJ
verdict: OKAY — F1/F2/F3 fixes functional
Minor notes (fixed post-review):
- Task 5 AC said `runs=5` (stale) → fixed to `runs=12`
- TL;DR said `5 повторов` → fixed to `12 повторов`
- `jq` added to Task 1 devShell acceptance criteria
- Statistical threshold language reconciliation: per-round gate uses `2× baseline stddev`; final comparison uses stricter `2× (stddev_pre + stddev_post)` — documented as staged strictness

### Final status: DUAL APPROVAL — both reviewers OKAY
High-accuracy review complete. Plan is decision-complete and executable.

## Approval gate
status: approved
approved-by: user explicit "Да"
timestamp: 2026-07-15
plan-written: true
