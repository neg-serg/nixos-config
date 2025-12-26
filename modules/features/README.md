# Features Module / Модуль фич

Feature flags for conditional system configuration.

Флаги функций для условной конфигурации системы.

## Usage / Использование

```nix
features = {
  gui.enable = true;      # Enable GUI / Включить GUI
  dev.enable = true;      # Enable dev tools / Разработка
  cli.enable = true;      # Enable CLI / Командная строка
  games.enable = true;    # Enable gaming / Игры
};
```

## Purpose / Назначение

Allows selective enabling of system components based on host role.

Позволяет выборочно включать компоненты системы в зависимости от роли хоста.
