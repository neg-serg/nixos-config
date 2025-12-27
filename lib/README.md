# Lib / Библиотека

Custom Nix library functions.

Пользовательские функции библиотеки Nix.

## Provides / Предоставляет

Core helpers used across the configuration:

| Function | Purpose / Назначение |
|----------|---------------------|
| `mkWhen` | Conditional merging / Условное слияние |
| `mkUnless` | Inverse conditional / Обратное условие |
| `mkXdgText` | XDG file creation / XDG файлы |
| `mkLocalBin` | Script installation / Установка скриптов |
| `mkHomeFiles` | Home directory files / Файлы home |
| `mkEnsureRealDir` | Directory creation / Создание директории |

## Files / Файлы

- `neg.nix` — Main helper library / Основная библиотека
- `xdg-helpers.nix` — XDG-related functions / XDG функции
- `opts.nix` — Option helpers / Хелперы опций

## Usage / Использование

```nix
config.lib.neg.mkWhen condition { ... }
config.lib.neg.mkLocalBin "script-name" "script content"
```
