# Tests / Тесты

Test suites for configuration validation.

Тесты для валидации конфигурации.

## Running Tests / Запуск тестов

```bash
just check    # Run all checks / Все проверки
just lint     # Run linters only / Только линтеры
nix flake check  # Flake-level checks / Проверки flake
```

## Test Types / Типы тестов

- Nix evaluation tests / Тесты eval Nix
- Linting (alejandra, deadnix, statix) / Линтинг
- Python linting (ruff, black) / Python линтинг
- Shell linting (shellcheck) / Shell линтинг
