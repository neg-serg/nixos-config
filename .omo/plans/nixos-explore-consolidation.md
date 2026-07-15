# Plan: nixos-explore pretty printing + consolidation

## Goal

1. Improve `nixos-explore list` output with proper alignment, colors, and visual hierarchy
2. Merge all nixos-related bash dev scripts into `nixos-explore` as subcommands, remove standalone scripts

## TODOs

1. [ ] Rewrite `nixos-explore list` Python formatter — dynamic column alignment, colored on/off, section headers, clean null/list rendering
   - Acceptance: `./scripts/dev/nixos-explore list` outputs properly aligned, colorized feature list with `[section]` headers
   - Manual-QA: run `./scripts/dev/nixos-explore list` and verify visually: values aligned, `on` green, `off` red, sections grouped

2. [ ] Merge `check-flake-inputs.sh` → `nixos-explore check-inputs` subcommand
   - Acceptance: `./scripts/dev/nixos-explore check-inputs` produces same output as old `./scripts/dev/check-flake-inputs.sh`
   - Manual-QA: run both old and new, diff outputs

3. [ ] Merge `check-impurity-paths.sh` → `nixos-explore check-impurity` subcommand
   - Acceptance: identical behaviour
   - Manual-QA: run both, diff outputs

4. [ ] Merge `gen-options.sh` → `nixos-explore gen-options` subcommand
   - Acceptance: identical behaviour
   - Manual-QA: run both, diff outputs

5. [ ] Merge `kernel-localmodconfig.sh` → `nixos-explore kernel-config` subcommand
   - Acceptance: identical behaviour
   - Manual-QA: run both with `--help`, diff outputs; spot-check with `--only-loaded`

6. [ ] Merge `check-package-refs.sh` → `nixos-explore top-pkgs` subcommand
   - Acceptance: identical output
   - Manual-QA: run both, diff outputs

7. [ ] Merge `diff-preview.sh` → augment existing `nixos-explore diff` subcommand
   - Acceptance: `nixos-explore diff <flag> <value>` runs nvd diff
   - Manual-QA: run `nixos-explore diff gui.enable false` (or a safe flag), verify nvd output

8. [ ] Add thin wrapper subcommands for Python scripts: `flat-imports` → `generate-flat-imports.py`, `module-graph` → `module-graph.py`
   - Acceptance: `./scripts/dev/nixos-explore flat-imports` runs the Python script; same for `module-graph`
   - Manual-QA: run both subcommands, verify Python script executes

9. [ ] Remove 6 merged standalone bash scripts from `scripts/dev/`
   - Files: `check-flake-inputs.sh`, `check-impurity-paths.sh`, `gen-options.sh`, `kernel-localmodconfig.sh`, `check-package-refs.sh`, `diff-preview.sh`
   - Acceptance: scripts deleted, `nixos-explore` subcommands still work

10. [ ] Update `nixos-explore help` to list all new subcommands
    - Acceptance: `./scripts/dev/nixos-explore help` shows all subcommands

## Final Verification Wave

F1. [ ] Run shellcheck on final `nixos-explore`
F2. [ ] Run `./scripts/dev/nixos-explore help` — all subcommands listed
F3. [ ] Run `./scripts/dev/nixos-explore list` — pretty output verified
F4. [ ] Run `./scripts/dev/nixos-explore check-inputs` — works
F5. [ ] Run `./scripts/dev/nixos-explore top-pkgs` — works
