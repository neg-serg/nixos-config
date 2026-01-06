______________________________________________________________________

## description: Запуск линтера и исправление проблем

# Линтинг

## Быстрая проверка

```bash
just check   # Все проверки
just lint    # Только линтеры
just fmt     # Форматирование
```

## Доступные проверки

| Проверка | Описание | |----------|----------| | `alejandra` | Nix formatter | | `deadnix` | Unused
Nix code | | `statix` | Nix linter | | `ruff` | Python linter | | `black` | Python formatter | |
`shellcheck` | Shell script linter |

## Исправление частых проблем

### Форматирование Nix:

```bash
alejandra .
```

### Форматирование Python:

```bash
black --line-length 79 file.py
```

### Проблемы shell:

- Добавьте `shellcheck disable` комментарии для ложных срабатываний
- Кавычки: `"$var"`
- Используйте `[[ ]]` вместо `[ ]`

## Pre-commit хуки

Включить:

```bash
just hooks-enable
```

Отключить:

```bash
just hooks-disable
```

## Аннотации пакетов

Все пакеты нужны с комментариями:

```nix
pkgs.ripgrep  # Быстрый grep для поиска кода
```
