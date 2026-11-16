______________________________________________________________________

## description: Run linting and fix issues

# Linting

## Quick Check

```bash
just check   # Run all checks
just lint    # Run linters only
just fmt     # Format code
```

## Parallelism

`just lint` is `scripts/dev/lint.sh`: the gates run concurrently and their output is replayed in a
fixed order, so a green run still reads top-to-bottom. Four knobs, all environment variables:

- `LINT_JOBS` — gates in flight (default `nproc`);
- `PMAP_JOBS` — files per gate for the checkers that fan out (default `LINT_JOBS/2`, clamped to
  2..16);
- `LINT_TIMING=1` — append each gate's wall time to the report, in table order. Use it to find the
  slow gate instead of guessing; `shellcheck` is normally the longest pole (~1.3 s, most of a green
  run), because it re-parses every sourced file for each of the 86 scripts;
- `LINT_COLOR=always|never` — force the colour decision. The default is decided once per run, from
  the suite's own stdout: coloured on a terminal, plain into a pipe or a file, and off whenever
  `NO_COLOR` is set. An explicit `LINT_COLOR=always` wins over `NO_COLOR`; a gate's tools are told
  the same thing with their own flags (`ruff --color`, `taplo --colors`, `selene --color`,
  `shellcheck --color`), because their output is captured to a file and replayed afterwards. `black`
  colours only its `--diff` and `statix` always emits SGR, so those two ignore the knob.

A failure is reported per gate and does not cancel the others; the summary names the failed gates
and the exit status is 1. To reproduce one gate in isolation or force a serial run:

```bash
LINT_JOBS=1 PMAP_JOBS=1 bash scripts/dev/lint.sh   # one gate, one file
bash scripts/dev/check-all-syntax.sh               # a single gate
```

## Available Checks

| Check | Description | |-------|-------------| | `nixfmt` | Nix formatter | | `deadnix` | Unused
Nix code | | `statix` | Nix linter | | `ruff` | Python linter | | `black` | Python formatter | |
`shellcheck` | Shell script linter |

## Fix Common Issues

### Nix formatting:

```bash
nixfmt .
```

### Python formatting:

```bash
black --line-length 79 file.py
```

### Shell script issues:

- Add `shellcheck disable` comments for false positives
- Quote variables: `"$var"`
- Use `[[ ]]` instead of `[ ]`

## Pre-commit Hooks

Enable:

```bash
just hooks-enable
```

## Package Annotations

All packages need comments:

```nix
pkgs.ripgrep  # Fast grep alternative for code search
```
