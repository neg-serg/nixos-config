# Библиотека

Пользовательские функции библиотеки Nix.

## Предоставляет

Основные хелперы, используемые в конфигурации:

| Функция | Назначение | |---------|------------| | `mkWhen` | Условное слияние | | `mkUnless` |
Обратное условие | | `mkXdgText` | XDG файлы | | `mkLocalBin` | Установка скриптов | | `mkHomeFiles`
| Файлы home | | `mkEnsureRealDir` | Создание директории |

## Файлы

- `neg.nix` — Основная библиотека
- `xdg-helpers.nix` — XDG функции
- `opts.nix` — Хелперы опций

## Использование

```nix
config.lib.neg.mkWhen condition { ... }
config.lib.neg.mkLocalBin "script-name" "script content"
```
