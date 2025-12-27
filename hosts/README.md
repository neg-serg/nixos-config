# Hosts / Хосты

Machine-specific configurations.

Конфигурации для конкретных машин.

## Available Hosts / Доступные хосты

| Host | Description / Описание |
|------|----------------------|
| `telfir` | Primary workstation / Основная рабочая станция |
| `telfir-vm` | VM testing configuration / VM для тестирования |

## Structure / Структура

Each host directory contains:
- `default.nix` — Entry point / Точка входа
- `hardware.nix` — Hardware configuration / Конфигурация оборудования
- `networking.nix` — Network settings / Настройки сети
- `services.nix` — Host-specific services / Сервисы хоста

## Adding a Host / Добавление хоста

1. Create `hosts/new-host/default.nix`
2. Add to `flake.nix` in `nixosConfigurations`
3. Build: `sudo nixos-rebuild switch --flake .#new-host`
