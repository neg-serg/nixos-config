______________________________________________________________________

## description: Codebase cleanse — run checkers, fix findings, verify, commit (ported from omp cleanse)

______________________________________________________________________

# Codebase Cleanse

Systematically find and fix lint/type/test failures across the repo, like omp's `cleanse` command:
discover checkers -> run them -> fix findings -> verify -> commit.

## Steps

1. **Discover checkers** — the repo's own gates:

   - `just fmt` (format), `just lint` (statix, deadnix, package annotations, osh -n, shellcheck)
   - `just check` (nix flake check) — heavy; run before commit, not for every fix
   - language-specific: cargo fmt/clippy, rustfmt, python compileall, hyprland vars, qml syntax

1. **Baseline**: run the fast ones first (`just fmt`, `just lint`) and record the failure list
   (file:line, message). Do not start fixing before the full list is known.

1. **Fix by category**, not file-by-file: same error class first (e.g. all package annotations, all
   osh syntax), then re-run the checker after each category.

1. **Do not touch unrelated code**: fixes stay within the failing construct (AGENTS.md: minimal
   diffs, no drive-by refactors). Mention unrelated issues separately.

1. **Verify**: re-run every checker until clean; then `just check` before the commit.

1. **Commit** with a scoped message: `[cli] Fix lint findings` /
   `[dev/pkgs] Clean up nix formatting`.

## Notes

- Interactive picker from omp is replaced by the todo list: every discovered failure becomes a
  tracked item (todo contract: enumerate ALL, never summarize).
- If a checker itself is broken (not the code), fix the checker or the recipe — not the code.
