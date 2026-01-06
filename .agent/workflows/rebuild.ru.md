---
description: Пересборка конфигурации NixOS
---

# Пересборка NixOS

## Быстрая команда

```bash
sudo nixos-rebuild switch --flake .#telfir
```

## Шаги

1. **Проверка конфигурации**:

   ```bash
   just check
   ```

1. **Сборка без переключения**:

   ```bash
   nixos-rebuild build --flake .#telfir
   ```

1. **Переключение на новое поколение**:

   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Опции

| Флаг | Описание |
|------|----------|
| `--flake .#host` | Использовать flake |
| `--show-trace` | Показать трейс ошибок |
| `--dry-run` | Предпросмотр изменений |
| `--upgrade` | Обновить inputs |

## Устранение проблем

Если сборка упала:

```bash
just lint      # Проверить ошибки
just check     # Все проверки
```
