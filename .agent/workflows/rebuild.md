______________________________________________________________________

## description: Rebuild NixOS configuration

# Rebuild NixOS

## Quick Command

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Steps

1. **Check configuration**:

   ```bash
   just check
   ```

1. **Build without switching**:

   ```bash
   nixos-rebuild build --flake .#telfir
   ```

1. **Switch to new generation**:

   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Options

| Flag | Description | |------|-------------| | `--flake .#host` | Use flake for host | |
`--show-trace` | Show error trace | | `--dry-run` | Preview changes | | `--upgrade` | Update flake
inputs |

## Troubleshooting

If build fails:

```bash
just lint      # Check for errors
just check     # Run all checks
```
