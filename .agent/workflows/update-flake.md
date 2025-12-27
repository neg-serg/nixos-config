______________________________________________________________________

## description: Update flake inputs to latest versions / Обновление flake inputs

# Update Flake / Обновление Flake

## Update All Inputs / Обновить все inputs

```bash
nix flake update
```

## Update Specific Input / Обновить конкретный input

```bash
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager
```

## Common Inputs / Частые inputs

| Input | Description / Описание | |-------|----------------------| | `nixpkgs` | Main package
repository | | `home-manager` | User config management | | `nvf` | Neovim flake | | `lanzaboote` |
Secure boot | | `sops-nix` | Secrets management |

## Rebuild After Update / Пересборка после обновления

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Rollback / Откат

If update breaks something / Если что-то сломалось:

1. **List generations** / Список поколений:

   ```bash
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   ```

1. **Switch to previous** / Переключиться на предыдущее:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

## Check Changelog / Проверить изменения

After updating nixpkgs / После обновления nixpkgs:

```bash
nvd diff /run/current-system result
```
