# Python CLI Template / Шаблон Python CLI

Lightweight scaffold for a Python CLI with a Nix devShell.

Лёгкий шаблон для Python CLI с Nix devShell.

## What You Get / Что включено

- Python 3.12 toolchain in `nix develop`
- Ruff + Black for lint/format / Ruff + Black для линтинга
- Pytest for tests / Pytest для тестов

## Usage / Использование

```bash
# Initialize / Инициализация
nix flake init -t <this-flake>#python-cli

# Enter dev shell / Войти в devShell
nix develop
```

Add your package code under `src/` and tests under `tests/`.

Добавьте код пакета в `src/` и тесты в `tests/`.
