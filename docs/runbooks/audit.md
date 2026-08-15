# Repeatable Repo Audit

Recurring maintenance audit of `/etc/nixos` — catches cruft, stale docs, dead options and latent
eval bugs before they bite. Run it periodically (or before a big refactor), then triage findings
into the improvement plan.

The previous full run: `.pi/audit-2026-07-21.md` (99 findings, 18 critical). The process below is
what produced it; it is designed to be re-run as-is.

## When to run

- Every few months, or after a large change wave (the repo accumulates `[meta/cleanup]`-style cruft
  between cleanups).
- Before touching architecture (flake inputs, module layout, overlay chain).

## Process

### 1. Snapshot & plan

- Record the current commit and system generation: `git rev-parse HEAD`,
  `readlink /nix/var/nix/profiles/system`.
- Create a report file: `.pi/audit-YYYY-MM-DD.md` (agent workspace, gitignored) or
  `docs/audit/YYYY-MM-DD.md` if you want it versioned. Copy the previous report's structure.

### 2. Fan out 4 parallel zone audits (subagents)

Launch four background agents, each with a self-contained prompt. Each returns a structured markdown
report with file paths and line numbers; instruct them to be factual and not invent issues.

**Zone 1 — flake & inputs:**

> Read /etc/nixos/flake.nix, flake/ (nixos.nix, checks.nix, lib.nix, devshells/, apps.nix,
> per-system.nix) and grep the tree for `inputs.<name>` / `inputs.self` usage per input. Report:
> inputs table (used? where? prune candidates), lock-vs-declaration mismatches, dead
> code/duplication between flake files, devshell duplication, checks.nix coverage gaps (no-op
> checks, untested paths). Cite file:line.

**Zone 2 — packages:**

> Read /etc/nixos/packages/ (overlay.nix, overlays/, flake/custom-packages.nix,
> lib/package-checks.nix) and every package default.nix. Report: missing meta fields, overlay wiring
> inconsistencies (callPkg/callPackage styles, shadowed overrides — check merge order!), dirs not
> wired into any overlay, floating sources (master/branch revs), duplication between overlay files,
> local-bin hygiene (permissions, dead branches).

**Zone 3 — modules:**

> Read /etc/nixos/modules/README.md, modules/default.nix, all modules/features/\*.nix, and walk the
> tree. Cross-reference every `features.*` flag (defined → consumed). Report: unused/undefined
> flags, naming inconsistencies, dead code, readDir vs manual import conventions, doc drift
> (README/AGENTS vs reality), boilerplate (feature-gate patterns).

**Zone 4 — scripts & docs staleness:**

> Check /etc/nixos/treefmt.toml, .gitignore, pyproject.toml, Justfile, scripts/, docs/, README.md,
> OPTIONS.md, \*AGENTS.md. Report: stale exclude/ignore paths (paths that no longer exist), broken
> links, claims contradicting reality (flake.nix vs flake/nixos.nix, modules.nix vs default.nix,
> GitHub Actions without .github/, EN/RU doc pairs, "generated (not tracked)" for tracked files).

### 3. Verify before acting

Subagent claims are starting points, not truth. Spot-check every finding you plan to fix:

- Existence/absence: `ls`/`test -e` the referenced path.
- Eval-level: `nix eval --impure --expr '...'` (overlay chain, config attrs) — see
  `docs/howto/agent-recipes.md` for the eval patterns.
- Whole-tree gate: `nix flake check -L`, `just lint`, `nix fmt` (idempotent).
- For behavior changes: rebuild the affected package (`nix build`) before committing.

### 4. Triage & track

- Sort findings into the plan buckets: **A** (bugs — fix first), **B** (hygiene), **C** (structure),
  **D** (process/security).
- Update the report file with the triage; mark findings fixed as you go.
- Re-run the full gates after each commit (the pre-commit hook runs `just lint`; run
  `nix flake check -L` once per batch).

### 5. Close the loop

- Regenerate the docs that the audit touched: `just codebase`, `just docs-modules`,
  `just unbound-hosts` (if host DNS data changed).
- Update `OPTIONS.md`/`modules/README.md` only for genuinely new human knowledge.
- Note remaining open items in the report for the next run — an audit that only fixes things and
  never records what's left is not repeatable.

## Reference: the 4-zone audit was the basis of

- The A/B/C/D refactoring plan (blocks A–D).
- The `.pi/audit-2026-07-21.md` findings status table (what was fixed by the cleanup waves).
