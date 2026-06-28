# salt

Salt states + chezmoi dotfiles for CachyOS (Arch-based) workstation.

**Authoritative guidelines:** `AGENTS.md` — read first before making any changes.

## Quick start

- `just apply` — full system apply
- `just apply <state>` — single state
- `just group <group>` — state group (core, desktop, ai, network, packages, services)
- `just test` — dry run
- `just lint` — run all linters
- `pytest tests/ -q` — run test suite

## Project layout

```
states/       Salt .sls files + Jinja macros
dotfiles/     Chezmoi source directory
scripts/      Utility scripts
tests/        Pytest test suite
docs/         Documentation
.specify/     Feature specs (speckit)
```

## Key policies

- English only for all documentation
- gopass-backed secrets via `tg_secret()` / `gopass_secret()` macros
- systemd user services for daemons
- No GitHub CI/workflows unless explicitly requested
