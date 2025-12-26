# Shell App Template / Шаблон Shell приложения

Quick-start scaffold for a small Bash CLI packaged via `writeShellApplication`.

Быстрый старт для небольшого Bash CLI, упакованного через `writeShellApplication`.

## Usage / Использование

```bash
# Initialize / Инициализация
nix flake init -t <this-flake>#shell-app

# Dev shell / Среда разработки
nix develop

# Build package / Сборка
nix build  # produces ./result/bin/mytool
```

## Notes / Заметки

- Add runtime dependencies to `runtimeInputs` in `flake.nix`
- Добавляйте зависимости в `runtimeInputs` в `flake.nix`
- Keep scripts POSIX-compatible for `shellcheck`
- Сохраняйте POSIX-совместимость для `shellcheck`
