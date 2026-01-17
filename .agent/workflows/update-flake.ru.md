______________________________________________________________________

## description: Обновление flake inputs

# Обновление Flake

## Обновить все inputs

```bash
nix flake update
```

## Обновить конкретный input

```bash
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager
```

## Частые inputs

| Input | Описание | |-------|----------| | `nixpkgs` | Main package repository | | `home-manager` | User config management |
| `lanzaboote` | Secure boot | | `sops-nix` |
Secrets management |

## Пересборка после обновления

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Откат

Если что-то сломалось:

1. **Список поколений**:

   ```bash
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   ```

1. **Переключиться на предыдущее**:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

## Проверить изменения

После обновления nixpkgs:

```bash
nvd diff /run/current-system result
```
