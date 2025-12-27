# Shell App Template

Quick-start scaffold for a small Bash CLI packaged via `writeShellApplication`.

## Usage

```bash
# Initialize
nix flake init -t <this-flake>#shell-app

# Dev shell
nix develop

# Build package
nix build  # produces ./result/bin/mytool
```

## Notes

- Add runtime dependencies to `runtimeInputs` in `flake.nix`
- Keep scripts POSIX-compatible for `shellcheck`
