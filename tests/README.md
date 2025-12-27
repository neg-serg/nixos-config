# Tests

Test suites for configuration validation.

## Running Tests

```bash
just check       # Run all checks
just lint        # Run linters only
nix flake check  # Flake-level checks
```

## Test Types

- Nix evaluation tests
- Linting (alejandra, deadnix, statix)
- Python linting (ruff, black)
- Shell linting (shellcheck)
