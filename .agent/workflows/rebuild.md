---
description: Rebuild NixOS configuration / Пересборка конфигурации NixOS
---

# Rebuild NixOS / Пересборка NixOS

## Quick Command / Быстрая команда

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Steps / Шаги

1. **Check configuration** / Проверка конфигурации:
   ```bash
   just check
   ```

2. **Build without switching** / Сборка без переключения:
   ```bash
   nixos-rebuild build --flake .#telfir
   ```

3. **Switch to new generation** / Переключение на новое поколение:
   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Options / Опции

| Flag | Description / Описание |
|------|------------------------|
| `--flake .#host` | Use flake for host / Использовать flake |
| `--show-trace` | Show error trace / Показать трейс ошибок |
| `--dry-run` | Preview changes / Предпросмотр изменений |
| `--upgrade` | Update flake inputs / Обновить inputs |

## Troubleshooting / Устранение проблем

If build fails / Если сборка упала:
```bash
just lint      # Check for errors / Проверить ошибки
just check     # Run all checks / Все проверки
```
