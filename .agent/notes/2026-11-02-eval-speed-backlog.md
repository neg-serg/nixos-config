# Eval speed: what is left after the 2026-11-02 pass

The working state and the closed lines are in `.agent/plans/2026-11-03-nix-eval-speed.md`. This note
is the backlog: the three things that would still help, why they were not done, and what each would
cost. Everything here is a decision for the owner or a multi-week project, not a patch.

## Where the seconds are now

`nh os switch --dry` after an edit: **10.8 s** (stock Determinate 12.2 s). Of that:

- ~0.75–1.0 s is parsing `.nix` files (10 %; 7762 files, 55.46 MiB, of which 98.2 % is three copies
  of nixpkgs and only 0.96 MiB is this repo) — and **speculative parallel parsing was built, proven
  correct, and is slower end to end**; see the first section below;
- **~6.6 s is the evaluator core** — allocation, GC, symbol interning (`SymbolTable::create` 4.4 %,
  `mi_theap_alloc_new` 3.5 %, `BumpMemoryResource::do_allocate` 2.1 %);
- the rest is the module system and the 2232 derivations at ~0.34 ms each.

## 0. Parallel parsing: correct, and slower (closed 2026-11-02)

The obvious idea does not work, and the reason is structural: **there is no batch.** Evaluation is
lazy, so `parseExprFromFile` is reached one file at a time on demand — `eval-cores 16` buys exactly
nothing for a `drvPath` eval, because the fiber pool only ever serves value-to-json. A speculative
prefetcher was written instead (831 lines: scan each parsed AST for path literals, parse the files
they denote on a 4-thread pool into a cache the demand path consults first, 1024-tree lookahead
window as back-pressure): parse phase 697 → 492 ms (−29 %), 2669 of 5634 demand parses served from
the cache. Correctness held — functional suite Ok 201 / Fail 1 (the known baseline), `drvPath`
identical across eight configurations, `lazy-trees` true, daemon round trip fine.

**End to end it is slower**: 7402 → 7480 ms median, paired deltas +284/+136/+175/−10/+318 ms. Only
about a third of the parses are anticipatable, and the anticipatable ones are the cheap files; the
14 files ≥256 KiB surface immediately before they are needed. The prefetcher's bookkeeping costs
more than the parsing it saves. Patch kept unapplied at
`/tmp/pp/0006-libexpr-prefetch-parsing.patch`.

## 1. One nixpkgs instead of three (~0.25 s parse, unknown eval)

`flake.lock` carries nine nixpkgs nodes; three are actually evaluated. The extra ones are
`nixpkgs-torch` (`9f160d0`, used by `packages/torch-rocm` and `packages/vllm-rocm`) and one more
transitive copy. Dropping a copy removes ~18 MiB of parsing per eval and one fixpoint instance.

**Why not done**: `torch-rocm` and `vllm-rocm` pin that revision deliberately — the AI stack would
have to be re-validated against the main nixpkgs, and a broken ROCm torch is a worse outcome than
0.25 s.

## 2. The second nixpkgs instance in the FHS overlay (0.15–0.25 s)

`flake/lib.nix:128` does `import inputs.nixpkgs { config.allowUnfree = true; }` inside an overlay to
rebuild `buildFHSEnv` from stock nixpkgs, because the composed one was broken for Steam's RT3
runtime. A second full nixpkgs fixpoint is evaluated whenever `buildFHSEnv` is touched.

**Why not done**: the file comment records that this split from the stock package is deliberate; the
cheap replacement (bind `_prev.buildFHSEnv` plus a narrow unfree allowance) risks bringing back the
`/sbin/ldconfig` bug it was written to fix. Needs a Steam launch test to validate.

## 3. The evaluator core (the real prize, ~6.6 s)

Not a patch: GC and allocation dominate because evaluation is pointer-chasing and thunk-forcing, not
arithmetic. The concrete directions, if this host ever justifies the work:

- intern symbols with a faster path (the table is already concurrent, but `create` shows up at 4.4
  %);
- reduce allocation churn in `BumpMemoryResource` / move AST nodes out of the hot allocator;
- a persistent AST cache needs a serialiser that does not exist (21 `Expr` node types plus
  SymbolTable, StaticEnv, PosTable, DocComment map) — measured floor ~0.62 s of saving, ~7x cheaper
  deserialisation than parsing, i.e. a real project for 5.7 %.

**Why not done**: weeks of C++ in the hottest code of the tool that runs `nixos-rebuild`, with a
silent-wrong-result failure mode. The validation harness for exactly that class already exists
(`scripts/dev/nix-memo-diff.sh`, the `eval-memo` switch, the four-patch build whose functional suite
is Ok 201 / Fail 1 — measured baselines in the package comments).

## Lines that are closed, for the record

BOLT (\<1 %, `instructions:u` +0.07 %), `-O3 -march=znver5` (no change), `MIMALLOC_*` and
`GC_INITIAL_HEAP_SIZE` (worse or noise), removing packages (no safe removals; duplicates cost zero
derivations), patches 0002/0006/0007/0008 (neutral or inapplicable), a fork for parallel evaluation
(ceiling 4.5 s, realistic 6.0 s), an incremental eval server (zero locality). Numbers and reasoning
are in the plan; do not retry these without new evidence.

## 4. Symbol interning: 2x per call, invisible in wall clock (closed 2026-11-02)

`SymbolTable::create` is 4.4 % of the eval, but the shape is inverted from what it looks like: on
this tree it is **98.1 % hits**, not inserts. Counters from a real eval (counter-patched build,
identical `drvPath`): 6,900,686 calls, 6,770,510 already interned, 130,176 inserts, 33 tables (one
per thread, 96.8 % of calls on the main one), 65.6 MB hashed, mean name 9.5 B. `rdtsc` split in
situ: hash 18 % of `create`, `insert_and_visit` 82 % — so the price is the concurrent set's shared
lock plus an *exclusive* group lock taken for a lookup that never writes.

Four "obvious" fixes were measured at **0 %**: precomputing the hash (there is no double hashing),
comparing hashes before strings (already exactly one compare per hit), sharding (single table), and
reserving capacity (130k inserts). A thread-local memo in front of the concurrent set *did* work on
the hot path — **17.4 → 9.3 ns/call (−46 %)**, `create` 3.2 % → 1.4 % of cycles — and the patch
passes every gate (suite Ok 201 / Fail 1, `drvPath` byte-identical, `lazy-trees`, daemon round
trip).

**It does not move wall clock**: 28 interleaved pairs at load 1.9–4.2 give −0.21 % (SEM 0.7 %, 15/28
wins) and the two halves disagree (−1.13 %, +0.66 %). The base-vs-base noise floor on this host is
±4 % (user time 6.68–7.64 s over 12 runs), so a ~1 % effect is below what can be measured here. The
patch is kept unapplied at `/tmp/symtab/0002-symbol-memo.patch`.

Also a correction to the profile reading: `__memcmp` is not mostly interning — `create` accounts for
6.76 M of 76.6 M calls (9 %); the rest is `Bindings::lexicographicOrder` 13 M,
`std::map<std::string>` comparators 11 M, `prim_replaceStrings` 5.4 M, `SingleDerivedPath` 2.7 M.

## The pattern across all of it

BOLT (\<1 %), `-march=znver5` (0 %), a flat attribute index (modelled −0.5…−1.3 %), speculative
parallel parsing (−29 % on the parse phase, +175 ms end to end), and a symbol memo (−46 % on the
operation, −0.2 % on the eval). Every one either fails to move the number or moves it the wrong way.

The consistent explanation: **this evaluation is memory-bound, not compute-bound.** The cycles saved
in one function reappear in cache misses elsewhere. What is left is the allocator and the GC — that
is, rewriting the evaluator's memory layout, which is a project rather than a patch, and would need
a validation harness (which exists: `scripts/dev/nix-memo-diff.sh` plus the four-patch build whose
suite is Ok 201 / Fail 1).
