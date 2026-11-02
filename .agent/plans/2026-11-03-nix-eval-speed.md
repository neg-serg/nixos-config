# NixOS eval under 2 s (2026-11-03)

Goal: `nix eval .#nixosConfigurations.trantor.config.system.build.toplevel.drvPath` answers in **≤ 2
s** when the tree has not meaningfully changed. Anything slower than that turns `nh os switch` and
every agent rollout into a coffee break.

## Baseline, measured today

| Case                            | Time   |
| ------------------------------- | ------ |
| cold (first run of the session) | 20.4 s |
| warm, run 2                     | 11.0 s |
| warm, run 3                     | 10.1 s |

Tree: 1990 tracked files, **567 `.nix`**, **135 local packages** in `packages/`, `nixpkgs` pinned by
`flake.lock`, flake type `git+file` (dirty working tree).

Two facts that decide the whole plan:

1. **The flake is a dirty git tree almost always.** Nix fingerprints the source (a copy of ~2000
   files) before it can even hit its eval cache, so "unchanged" in practice means *committed* — a
   dirty tree re-copies and re-fingerprints every call. Any target must say which case it holds for.
1. **10 s is evaluation, not copying.** A 2000-file copy costs tens of milliseconds, so ~9.5 s of
   that number is `evalModules` plus lazy `pkgs` work; that is what has to come down.

### First probes (run 2026-11-03, dirty tree, warm)

| Probe                                                          | Time                                        |
| -------------------------------------------------------------- | ------------------------------------------- |
| `config.system.nixos.label` (flake + module system, no `pkgs`) | **1.29 s**                                  |
| `system.build.toplevel.drvPath`                                | **10.21 s**                                 |
| same with `--option eval-cache false`                          | **10.13 s**                                 |
| same with `documentation.enable = false` (via `extendModules`) | **14.21 s** vs 14.24 s baseline — no effect |

Read this before believing any hypothesis below:

- **The module system is not the problem.** Flake fetch + `evalModules` for the whole configuration
  is 1.3 s, already inside the 2 s target.
- **~8.9 s is `pkgs`**: instantiation, the overlay set, and forcing the toplevel's build graph. That
  is where the target has to be won.
- **The eval cache is saving nothing** (10.21 vs 10.13) — a dirty git tree changes the fingerprint
  on every call, so nothing is ever a cache hit. This single fact explains why "nothing changed"
  still costs 10 s, and it makes T4 the cheapest structural fix of the lot.

## T0 — replace the evaluator before rewriting the config (found 2026-11-03)

`~/src/nix-optimized` (github:ElXreno/nix-optimized) is a Nix rebuilt with **profile-guided
optimisation plus BOLT**, carrying **evaluation speedups as patches** (`patches/<version>/`),
published to a cachix binary cache. That attacks the layer my probes actually point at: the 8.9 s is
the evaluator's own work in `pkgs`, and no amount of config surgery changes how fast Nix evaluates —
only how much it has to evaluate.

Why this is the right first move, given the numbers:

- The config side is already lean: modules are 1.29 s and disabling documentation changed
  **nothing** (14.24 → 14.21 s on the same tree, measured today through `extendModules`). The
  remaining cost is evaluator throughput.
- PGO+BOLT on Nix itself is typically a 2-4x win on eval-heavy workloads; the project also disables
  the GC's conservative settings that hurt evaluation.
- It is a *package swap*, not a rewrite: `nix.package`, one substituter, one trusted key.

Sketch (to be validated, not applied blind):

```nix
{
  inputs.nix-optimized.url = "github:ElXreno/nix-optimized";
  # ...
  nixpkgs.overlays = [ ]; # nothing needed
  nix.package = nix-optimized.packages.${system}.nix-optimized;
  nix.settings = {
    substituters = [ "https://elxreno.cachix.org" ];
    trusted-public-keys = [ "elxreno.cachix.org-1:ozSPSY5S3/TpbcXi+/DdtSj1JlK3CPz3G+F92yRBXDQ=" ];
  };
}
```

Risks and what to check before trusting it:

- **This host runs determinate-nix**, not the plain NixOS `nix` module. Two moving parts (`nix`
  client and `nix-daemon`) must come from the same build, and determinate's own settings store must
  not fight `nix.package`; check `systemd.services.nix-daemon.environment` and the determinate
  module override.
- A new daemon means a restart, and every running build must survive it (or be drained first).
- `patches/<version>/` only exists for some releases; `nix-optimized-plain` (PGO only) is the
  fallback.
- Trust boundary: a new substituter and its key are added to the system. That is a supply-chain
  decision, not a performance one — record it in the commit.
- Verify the same `drvPath` before and after the swap on an unchanged tree, and `just check` green.

If T0 lands, the config-side investigations below become the second-order cleanup rather than the
plan.

## Method (do not skip)

1. Split the number before touching anything, with three probes on the *same* tree state:
   - `nix eval --raw .#nixosConfigurations.trantor.config.system.nixos.label` — flake + module
     system, no `pkgs` build graph;
   - the baseline command above — adds `pkgs` instantiation and the toplevel;
   - `nix eval --option eval-cache false …` — how much the eval cache is already saving.
1. Profile the real thing: `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/stats.json nix eval …`, then
   read the function-call histogram (`nix-util`'s flamegraph tools, or just the top entries in the
   JSON). Guessing which subsystem is slow here has a bad hit rate.
1. Time with `hyperfine --warmup 1 --runs 5 '<command>'`, and **always** record whether the tree was
   dirty and whether it was the first eval after a change.
1. Fix one thing, re-measure, keep the diff only if the number moved and `just check` still passes
   and the resulting `drvPath` is unchanged for the same tree.

## Investigations, ordered by expected win

**T1 — documentation and other non-evaluable branches.** `system.build.toplevel` drags
`documentation.*` (the manual, `nixos-help`, option docs) into the build graph; for evaluation those
paths still walk every option's `description`. Measure with `documentation.enable = false` in a
throwaway eval (`--argstr` or a temporary override) and compare. In configurations this size this is
often the single largest win, and for eval-only gates it costs nothing real. Decide whether agents
should evaluate a doc-free attribute instead of `toplevel.drvPath` (e.g. a `config.system.build`
subset) — that keeps docs for humans and gives agents a fast gate.

**T2 — eager flake outputs.** Check whether evaluating one `nixosConfigurations.trantor…` attr pulls
`checks`, `devShells`, `packages` or `overlays` into existence (`flake/checks.nix` is imported from
the flake outputs; `flake/lib.nix` may force `self.packages` eagerly). Probe:
`nix eval .#checks --dry-run` timing vs `.#nixosConfigurations`. Attrpaths are lazy, but an `import`
at the outputs top level is not — and this repo builds a `neg` namespace from overlays.

**T3 — the 135-package overlay (now the prime suspect, given the probes).** `packages/overlay.nix` →
`packages/overlays/*.nix` → `callPkg (pkg "<name>")`. If the aggregation `import`s each package file
eagerly, every eval parses 135 extra files. Deferring with path-valued `callPackage` (Nix parses a
path only when the attribute is forced) should cost nothing at eval time. Verify by counting how
many `packages/**/default.nix` are read during an eval
(`strace -f -e trace=openat nix eval … | rg 'packages/' | wc -l`).

**T4 — eval cache reality check.** `~/.cache/nix/eval-cache-v*` only helps when the flake's
fingerprint is stable — i.e. a clean tree at a fixed revision. Two levers: (a) agents commit early
and work in small commits so most evals run on a clean tree; (b) never point the cache at a path
flake (`builtins.getFlake "/etc/nixos"` uses the *path* fetcher, copies the tree, and misses the
cache — that is also what trips over stray sockets). Standardise on `.#…` refs in every recipe,
`Justfile` and script.

**T5 — `neg.importDir` and module count.** *Deprioritised by the probes*: the whole module system is
1.29 s, so `importDir` and `trantorDomains` filtering together are a fraction of that. Only revisit
if probe 1 grows past ~2 s on its own.

**T6 — the leanest possible entry point.** `nix eval` is leaner than `nixos-rebuild`/`nh`, which add
linting, flake update checks and `--option` plumbing. Give agents a single fast path
(`nix eval --raw .#…drvPath`) and keep `nh os switch` for humans; measure both to see how much the
wrappers cost on top.

## Guardrails

- A faster eval must produce the **same `drvPath`** for the same tree; record it before and after
  each change (`nix eval --raw .#…toplevel.drvPath`), so "fast" cannot mean "evaluated less".
- `just check`, `just lint` and `lint-guards` stay green.
- Anything that disables a feature (docs, checks) for speed must be a *separate attribute or flag*,
  never a silent default: a human switching the system still gets manuals and checks.
- No `--impure`, no `--no-eval-cache`, no `builtins.getFlake` on a path.

## Definition of done

1. `hyperfine` report showing ≤ 2 s warm on a **clean** tree, and the dirty-tree number documented
   next to it (it will be worse; say by how much).
1. The three probes from "Method" recorded in this file, so the next person sees where the time
   went.
1. Agent recipes (`Justfile`, runbooks, AGENTS quick commands) point at the fast path.
1. `drvPath` equality and green checks proven in the same commit.
