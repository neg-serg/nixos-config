---
description: Run linting and fix issues / Запуск линтера и исправление проблем
---

# Linting / Линтинг

## Quick Check / Быстрая проверка

```bash
just check   # Run all checks / Все проверки
just lint    # Run linters only / Только линтеры
just fmt     # Format code / Форматирование
```

## Available Checks / Доступные проверки

| Check | Description / Описание |
|-------|----------------------|
| `alejandra` | Nix formatter |
| `deadnix` | Unused Nix code |
| `statix` | Nix linter |
| `ruff` | Python linter |
| `black` | Python formatter |
| `shellcheck` | Shell script linter |

## Fix Common Issues / Исправление частых проблем

### Nix formatting / Форматирование Nix:
```bash
alejandra .
```

### Python formatting / Форматирование Python:
```bash
black --line-length 79 file.py
```

### Shell script issues / Проблемы shell:
- Add `shellcheck disable` comments for false positives
- Quote variables: `"$var"`
- Use `[[ ]]` instead of `[ ]`

## Pre-commit Hooks / Pre-commit хуки

Enable / Включить:
```bash
just hooks-enable
```

Disable / Отключить:
```bash
just hooks-disable
```

## Package Annotations / Аннотации пакетов

All packages need comments / Все пакеты нужны с комментариями:
```nix
pkgs.ripgrep  # Fast grep alternative for code search
```
