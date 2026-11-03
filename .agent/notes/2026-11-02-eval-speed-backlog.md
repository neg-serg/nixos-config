# Eval speed: what is left after the 2026-11-02 pass

The working state and the closed lines are in `.agent/plans/2026-11-03-nix-eval-speed.md`. This note
is the backlog: the three things that would still help, why they were not done, and what each would
cost. Everything here is a decision for the owner or a multi-week project, not a patch.

## Where the seconds are now

`nh os switch --dry` after an edit: **10.8 s** (stock Determinate 12.2 s). Of that:

- ~0.75–1.0 s is parsing `.nix` files (10 %; 7762 files, 55.46 MiB, of which 98.2 % is three copies
  of nixpkgs and only 0.96 MiB is this repo);
- **~6.6 s is the evaluator core** — allocation, GC, symbol interning (`SymbolTable::create` 4.4 %,
  `mi_theap_alloc_new` 3.5 %, `BumpMemoryResource::do_allocate` 2.1 %);
- the rest is the module system and the 2232 derivations at ~0.34 ms each.

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
