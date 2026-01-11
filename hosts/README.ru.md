# Хосты

Конфигурации для конкретных машин.

## Доступные хосты

| Хост | Описание | |------|----------| | `telfir` | Основная рабочая станция |

## Структура

Каждая директория хоста содержит:

- `default.nix` — Точка входа
- `hardware.nix` — Конфигурация оборудования
- `networking.nix` — Настройки сети
- `services.nix` — Сервисы хоста

## Добавление хоста

1. Создать `hosts/new-host/default.nix`
1. Добавить в `flake.nix` в `nixosConfigurations`
1. Собрать: `sudo nixos-rebuild switch --flake .#new-host`
