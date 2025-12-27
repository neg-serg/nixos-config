# Packages / Пакеты

Custom packages and overlays for the configuration.

Пользовательские пакеты и оверлеи для конфигурации.

## Structure / Структура

| Directory | Purpose / Назначение |
|-----------|---------------------|
| `overlay.nix` | Main overlay entry / Точка входа оверлея |
| `overlays/` | Overlay helpers (functions, tools, media, dev) |
| `game-scripts/` | Gaming launchers and CPU pinning |
| `rofi-config/` | Rofi themes and wrappers |
| `local-bin/` | User scripts for `~/.local/bin` |
| `flight-gtk-theme/` | GTK theme package |

## Usage / Использование

Packages are available via `pkgs.<name>` or `pkgs.neg.<name>`:

```nix
environment.systemPackages = [ pkgs.flight-gtk-theme ];
```

## Adding Packages / Добавление пакетов

1. Create `packages/my-package/default.nix`
2. Add to `packages/overlay.nix`
3. Reference via `pkgs.my-package`
