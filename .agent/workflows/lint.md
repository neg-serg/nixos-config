______________________________________________________________________

## description: Run linting and fix issues

# Linting

## Quick Check

```bash
just check   # Run all checks
just lint    # Run linters only
just fmt     # Format code
```

## Available Checks

| Check | Description | |-------|-------------| | `alejandra` | Nix formatter | | `deadnix` | Unused
Nix code | | `statix` | Nix linter | | `ruff` | Python linter | | `black` | Python formatter | |
`shellcheck` | Shell script linter |

## Fix Common Issues

### Nix formatting:

```bash
alejandra .
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

Disable:

```bash
just hooks-disable
```

## Package Annotations

All packages need comments:

```nix
pkgs.ripgrep  # Fast grep alternative for code search
```
