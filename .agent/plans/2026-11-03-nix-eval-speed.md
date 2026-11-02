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

## What the profiler says (2026-11-03, flamegraph, 2371 samples @199 Hz)

`nix eval --eval-profiler flamegraph --eval-profile-file /tmp/eval.folded` on the toplevel eval,
self-time of 12.9 s profiled cpuTime:

| Share    | Where                                                                                                                                                                                                |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **47 %** | nixpkgs derivation machinery — `pkgs/stdenv/generic/make-derivation.nix` (`buildInputs++optionals` 5.3 %, `getDev`/`__spliced` 10.4 %, `makeMesonFlags`/`makeCMakeFlags` 3.9 %, `isAttrs env` 2.4 %) |
| 12 %     | `lib/modules.nix` (`applyModuleArgs` 2.2 %)                                                                                                                                                          |
| 7.3 %    | `callPackage`/`makeOverridable`                                                                                                                                                                      |
| 5.3 %    | `functionArgs`/`isFunction`                                                                                                                                                                          |
| 2.3 %    | the overlay fixpoint itself (`lib/fixed-points.nix:333`)                                                                                                                                             |

**≥ 2232 distinct derivations are instantiated**, and `derivationStrict` is on the stack in 90 % of
samples. That is the real budget: ~2.7 ms per derivation, no matter how the repo is organised.

Answering the questions the plan asked:

- Modules are 12 %, `pkgs` is ~47 % self-time plus the Python/Haskell/fetchurl builders behind it.
- **Yes, unused local packages are parsed**: 110 of 122 `packages/*/default.nix` are read even when
  the evaluation never forces them, plus 167 directory opens for source hashing.
- `readFile` is 0.13 % (irrelevant). `import` is 12.4 % inclusive but 0.38 % self.
- The overlay is evaluated once, but **three nixpkgs revisions are live** and `flake/lib.nix:128`
  does `import inputs.nixpkgs { … }` inside an overlay — a second full instance whenever
  `pkgs.buildFHSEnv` is touched.

**Repo-side ceiling: ~0.6–0.8 s (5 %)** from the three safe fixes (direct `import` instead of
`callPackage` for the hot local packages; de-overlapping the `files/` source roots, which are
re-listed up to 8x; binding `buildFHSEnv` to `_prev` instead of a fresh nixpkgs). Everything else is
nixpkgs' own per-derivation cost — which is exactly why **T0 (a faster evaluator) is the only path
to 2 s**, and why a "light gate" attribute that evaluates fewer derivations is the complement to it.

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

## Attribution: the graph is irreducible (2026-11-03)

Inclusive stacks (15,964 samples, `--eval-profiler-frequency 997`) plus per-area counting with
closure membership:

| Finding                                                     | Number                                                                                                                       |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| instantiated derivations that exist in the toplevel closure | **5,185 of 5,248 names = 98.8 %**                                                                                            |
| `config.system.build.toplevel`                              | 61.8 % inclusive                                                                                                             |
| └ the `etc` entry loop (`etc.nix:56`)                       | 60.9 %, and inside it **47.9 %** is one chain: the `dbus-1` etc source → `dbus-consolidated` → `system-path` → every package |
| activation-time assertions (`top-level.nix:78`)             | 33.4 % (apparmor profiles 8.6 %, nix-maid 3.1 %, 32-bit graphics 3.1 %, searxng 1.8 %)                                       |
| documentation / checks / specialisation                     | **0.00 %** each                                                                                                              |

Mechanism: nixpkgs `services/system/dbus.nix:153-156` sets
`services.dbus.packages = [ dbusPackage config.system.path ]` and `modules/user/dbus.nix:41` makes
the `dbus-1` etc entry that consolidated config, so forcing one `environment.etc` entry forces
`config.system.path` and with it all ~716 packages. Unavoidable — `system.path` is a toplevel input.

**Consequence: a "light gate" that evaluates fewer attributes cannot be both correct and much faster
(≤3 %).** The one avoidable artefact found: `pkgs.tmd-top` pulls a python3.12 doc/test closure
(sphinx, furo, pytest, pandas — 63 names, ~0.25 s) that never reaches the closure; not fixable from
eval-side code without overriding that package's python env.

## Where the seconds actually came from (2026-11-03, end of the day)

| Lever                                              | Number                                                                                                                                                         |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| tier-A gate (`config.system.nixos.label`)          | **0.46–0.9 s** cold, 65–79 ms on a hit                                                                                                                         |
| tier-B gate, plain `--raw`                         | 9.0 s                                                                                                                                                          |
| tier-B gate, `builtins.parallel` + `eval-cores 16` | **3.7 s** (2.42×), byte-identical answer                                                                                                                       |
| nine eval patches on upstream 2.35.3               | −14 %, tests green (193 functional), drvPath unchanged                                                                                                         |
| PGO+BOLT nix-optimized binary                      | −20 % (4.6–5.5 s vs 5.7–6.0 s), but no `lazy-trees`                                                                                                            |
| fork for parallelism                               | ceiling 4.5 s, realistic 6.0 s — **not worth it**                                                                                                              |
| incremental eval server                            | **zero locality**: a one-option module edit still costs the full 9 s, and the flake source path is not stable even for identical bytes — not worth 2–3 k lines |

Two findings that closed lines of work: `eval-cores` is a **no-op** for `nix eval --raw …` (the
executor shuts down with zero work items; only three call sites fan out), and Determinate's
`lazy-trees` does **not** rescue untracked-but-referenced paths — it only saves the per-edit tree
copy (`nix hash path /etc/nixos` = 0.9–1.2 s).

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

## Validating the data structures we are tempted to change (2026-11-03)

The speedups that remain are in the evaluator's own structures, and there the failure class is a
**silently different `drvPath`**: the build succeeds and the artifact is not what the config says.
So the question is not "is it faster" but "can a wrong answer get through".

### Patch 0006 (`derivationStrict` memoised by a masked-derivation hash) — reviewed line by line

The key hashes `name`, `platform`, `builder`, `args` (with count and lengths), `env` (count, keys,
values), output *names* plus count, `inputSrcs`, `inputDrvs` (path, count, output names) and
`structuredAttrs` (`unparse()` JSON). It returns `nullopt` — i.e. no memoisation — for fixed-output
derivations and for any `inputDrvs` entry with a non-empty `childMap`, and the memo is only
consulted when `repair == NoRepair`.

Verdict: **the key is complete for the `Derivation` fields that exist in 2.35.3**, so an equal key
implies an equal derivation implies an equal store path. The risk is not today's fields, it is the
next ones: the key is hand-written next to the struct it mirrors, so a new `Derivation` field added
upstream (or a change in what `unparse()` emits) would silently stop being covered. Two smaller
observations: the memo hit skips `writeDerivation` entirely (safe only because the first
instantiation in the same process wrote the file), and `structuredAttrs` keying depends on
`unparse()` being deterministic (a false *miss* if it is not — cost, not correctness).

### What the field does about this class (external evidence, 2026-11-03)

Three techniques, ranked by confidence per hour, each with prior art rather than our invention:

| Technique                                                                                                                                                   | Effort    | Evidence it is real practice                                                                                                           |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **one-field mutation corpus** — mutate each masked-derivation field in isolation and require the key to change (or the derivation to be provably identical) | ~1 day    | ccache's suite re-runs after every single-input edit and asserts `cache_miss 1`                                                        |
| **differential validation** — a `--no-memo` switch, corpus run twice, diff the drv JSON and the store path                                                  | 2–4 h     | ccache compiles a reference object outside the cache and compares; Nix itself ships `--no-eval-cache`; sccache ships `SCCACHE_RECACHE` |
| **key-coverage assertion** — hash through a wrapper that records visited fields and aborts if any are unvisited                                             | ~half day | inference, nearest analogue is ccache's `cache-debug` dump of exactly what was hashed                                                  |

The failure stories that justify the paranoia:
[bazelbuild/bazel#4558](https://github.com/bazelbuild/bazel/issues/4558), "remote/correctness: Bazel
doesn't track system libraries" — still open, and the cleanest statement of the class (an input that
affects the output but not the key); sccache documents cases where it "silently produce[s] stale
results"; ccache's direct mode misses new header files in rare cases, and its `hash_dir` section
records a wrong-object bug fixed by adding the missing field to the key — exactly our class.

**Citation note (2026-11-03).** `bazel.build` is unreachable from this host's sandbox and the first
version of this section quoted an `--action_env` whitelist sentence that could not be re-verified
afterwards: `site/en/remote/caching.md` at tag 9.0.0 does not contain it, and the attempt to fetch
`site/en/configure/environment.md` timed out. The claim is therefore dropped rather than repeated;
what is verified is the issue title and state above (fetched through the GitHub API) and the
sccache/ccache statements, which come from files in their own repositories. Quoting a doc one could
not re-read is the failure this plan is supposed to prevent.

One finding directly relevant to our own gate: Nix's eval cache ignores files that are not in the
git index ([NixOS/nix#12102](https://github.com/NixOS/nix/pull/12102)) — the same trap our tier-B
key was built to avoid by hashing untracked content explicitly.

Residual risk that no technique removes: all of them cover only *enumerable* fields, so a new
`Derivation` field stays invisible until a human adds it. This buys review discipline, not proof.

### What Nix's own suite can and cannot catch (read from the pinned 2.35.3 sources)

| Layer                                                      | Size                                                                                                                                                           | What it asserts                                                                                                                                                                                      |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| unit (`src/lib*-tests`, gtest)                             | 47+43+20+8+3 files                                                                                                                                             | C++ object equality. The **only** `drvPath` assertion is `nix_api_expr.cc:112-125`, and it checks a name suffix plus `isValidPath` — a wrong-but-self-consistent path passes                         |
| lang golden (`tests/functional/lang.sh`)                   | 468 cases, 6.7 s with our binary                                                                                                                               | exact values, and because it runs under `NIX_REMOTE=dummy://` with `NIX_STORE_DIR=/nix/store`, **store paths are deterministic and assertable as literals** (`lang/eval-okay-derivation-legacy.exp`) |
| shell functional                                           | 155 scripts, 193 cases                                                                                                                                         | mostly run-and-grep; real equality only where a test compares two derivations (`impure-derivations.sh:16-19`)                                                                                        |
| eval-cache (`tests/functional/flakes/eval-cache.sh:41-50`) | —                                                                                                                                                              | only that errors and stack overflows are *not* cached; never cached-vs-recomputed, so it cannot catch a bad memo key                                                                                 |
| fuzzing                                                    | **none** (no libFuzzer/AFL, no fuzz dir)                                                                                                                       | RapidCheck properties only (`libexpr-tests/value/context.cc:123`, `derived-path.cc`)                                                                                                                 |
| sanitizers                                                 | packaging has `withASan`/`withUBSan`/`withTSan` (`packaging/components.nix:219-240,305-325`); CI runs ASan+UBSan with GC off (`ci/gha/tests/default.nix:9-57`) | TSan is packaged but unused — the gap that matters if the maps ever go concurrent                                                                                                                    |

Three gaps follow, each closable in a few lines: no `drvPath` literal for `derivationStrict`; the
eval cache is never diffed against a recomputation; and there is no memo-on/off A/B anywhere.

### The three tests that would catch a bad key, cheapest first

1. **Key-completeness unit test** (`src/libexpr/tests`, a day of work): build one `Derivation`, take
   the key, then mutate exactly one field at a time — name, platform, builder, one arg, one env key,
   one env value, one output name, output count, one `inputSrcs` path, one `inputDrvs` output name —
   and assert the key changes every time; plus assert `nullopt` for fixed-output and `childMap`
   cases. This is the only test that fails when a future field is forgotten, i.e. the one that
   catches the real hazard. A `Derivation`-field visitor (or a `static_assert`-style field count)
   makes it self-checking: the test fails to compile when the struct grows.
1. **Corpus differential** (hours): for a set of real configurations, compare the `drvPath` of every
   derivation reachable from `system.build.toplevel` (`nix derivation show -r` gives 28,811 for this
   host) between the patched and the unpatched binary. A wrong memo hit shows up as a mismatched
   path for one of them. Already partially done — the toplevel path matched — but that compares one
   value, not the closure.
1. **Store-write regression** (hours): instantiate the same derivation twice in one process (two
   `builtins.derivation` calls with identical attrs) and assert the `.drv` exists in the store and
   both values are equal — this pins the `writeDerivation`-skipped-on-hit behaviour, which is the
   one place where "faster" could mean "not done".

What none of these can prove: that the *masking* is semantically intended (that two derivations
which differ only in a field deliberately excluded from the key really do produce the same outputs).
That remains a design decision, and the patch's own guard — refusing fixed-output and `childMap`
cases — is the honest form of it.

## `lazy-trees`, for the future (2026-11-03, not implemented)

Determinate's `lazy-trees` is a **plain bool setting**, not an experimental feature
(`src/libexpr/include/nix/expr/eval-settings.hh:481`, default false), read in three places
(`paths.cc:84,105`, `nix/flake-prefetch-inputs.cc:55`); the machinery is `EvalState::devirtualize()`
plus ~22 call sites in 10 files. Upstream 2.35 already mounts inputs lazily; what Determinate adds
is *virtual* store paths.

What it actually buys on this host: **0.9–1.2 s per evaluation**, i.e. the per-tree-state copy
(`nix hash path /etc/nixos`). It does **not** change the client/daemon protocol (`PROTOCOL_VERSION`
identical, no daemon-side setting), and — measured twice — it does **not** rescue untracked-but-
referenced paths: Determinate refuses them exactly like stock Nix. The precondition for evaluating
this flake is `git add -N` on referenced paths, full stop.

So the trade is: our patched Nix (`nix-eval-patched`, 2.35.3+12) keeps the nine evaluation speedups
and loses the tree-copy shortcut; Determinate keeps the shortcut and cannot take the patches. If
someone later wants both, the options are, in order of cost:

1. **Rebuild Determinate's source with PGO/BOLT only** (no patch rebase): the compiler flags do not
   touch the code, so `lazy-trees` survives by construction. Reuses `~/src/nix-optimized`'s PGO
   machinery; expected −20 % on the evaluator, no semantic risk, but it must be redone whenever
   Determinate bumps a version. Five of the nine patches apply cleanly to their tree
   (`0001/0003/0004/0005/0009`); `0002`, `0006`, `0007` conflict structurally because Determinate
   replaced `addTempRoot()` with a batched `addTempRoots()` and writes derivations through an
   `AsyncPathWriter` overload (`derivations.cc:169`), and `0008` applies with fuzz onto a path their
   hot loop bypasses, so it would do nothing.
1. **Backport `devirtualize` to upstream** — ~250–300 lines across 12 files — then apply all nine
   patches verbatim. Medium risk, and it buys only the copy saving.
1. **Rebase `0002/0006/0007` onto Determinate's APIs** — the honest estimate is 2–3 days of C++,
   with the worst failure mode being a silently wrong `drvPath`, because `0006` memoises the hot
   path. This is the only route that gets both features *and* the patches, and it is why the
   differential harness in `scripts/dev/nix-memo-diff.sh` and the `eval-memo` switch exist: they
   make that rebase verifiable rather than hopeful.

Nothing here is required for the current setup: `just eval-gate` and the pins already give 35 ms
hits and 3.7 s cold without touching the evaluator.

## Where the host stands (2026-11-02, after adopting route 1)

`nix.package` is now `packages/nix-det-pgo`: Determinate 3.23.3's own source, PGO-trained, with the
five patches its tree accepts (`0001/0003/0004/0005/0009`). Verified on the running system:
`nix (Determinate Nix 3.23.3) 2.35.3+5`, `lazy-trees = true`, `nix-daemon` active, `nix build`
round-trips through it, and the toplevel `drvPath` equals the stock binary's.

| Measurement                         | Stock Determinate    | PGO + 5 patches                         |
| ----------------------------------- | -------------------- | --------------------------------------- |
| toplevel eval, interleaved 3 rounds | 8.73 / 8.24 / 8.21 s | **7.60 / 7.05 / 7.63 s** (−13 % median) |
| `just eval-gate --drv`, cold        | 3.7–3.9 s            | **3.24 s**                              |
| `just eval-gate --drv`, hit         | 35–38 ms             | 46 ms                                   |
| `just eval-gate` (tier A), cold     | ~0.9 s               | **0.49 s**                              |

`doCheck` is off for this package and the reason is recorded in it: Determinate's suite gates on
`nix-*-tests-run` inputs and one of them (IPv6 zone-id URL parsing) fails on their tree regardless
of our patches. Acceptance is by behaviour instead — identical `drvPath`, plus a six-case
differential battery (any/all, structuredAttrs drvPath, `nix hash path`, fromJSON, path
canonicalisation, flake metadata) that compares this build against stock byte for byte.

The four patches still missing are `0002`, `0006`, `0007` (and `0008`, which cannot help: it targets
a `writeDerivation` path Determinate bypasses via `AsyncPathWriter`). Getting them means rebasing
onto Determinate's APIs — `addTempRoots()`, `devirtualize()`, `writeDerivation(*asyncPathWriter, …)`
— one at a time, easiest first, with the memo harness as the acceptance test for `0006`. A backport
of `lazy-trees` to upstream was measured and rejected: 446 changed lines in 12 files that *replace*
an existing mechanism (`ensureLazyPathCopied` at `paths.cc:25` upstream) rather than add to it, so
every store path escaping without devirtualising becomes a bug class.

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
