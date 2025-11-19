# Python CLI Template

Lightweight scaffold for a Python CLI with a Nix devShell.

## What you get

- Python 3.12 toolchain in `nix develop`
- Ruff + Black for lint/format
- Pytest for tests

## Usage

- Initialize: `nix flake init -t <this-flake>#python-cli`
- Enter dev shell: `nix develop`
- Add your package code under `src/` and tests under `tests/`.
