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
fixed order, so a green run still reads top-to-bottom. Two knobs, both environment variables:

- `LINT_JOBS` — gates in flight (default `nproc`);
- `PMAP_JOBS` — files per gate for the checkers that fan out (default `LINT_JOBS/4`, clamped to
  2..16).

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
