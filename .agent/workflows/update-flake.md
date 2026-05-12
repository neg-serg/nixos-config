______________________________________________________________________

## description: Update flake inputs to latest versions

# Update Flake

## Update All Inputs

```bash
nix flake update
```

## Update Specific Input

```bash
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager
```

## Common Inputs

| Input | Description | |-------|-------------| | `nixpkgs` | Main package repository | |
`home-manager` | User config management | | `lanzaboote` | Secure boot | | `sops-nix` | Secrets
management |

## Rebuild After Update

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Rollback

If update breaks something:

1. **List generations**:

   ```bash
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   ```

1. **Switch to previous**:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

## Check Changelog

After updating nixpkgs:

```bash
nvd diff /run/current-system result
```
