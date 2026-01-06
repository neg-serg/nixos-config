# Модуль игр

Конфигурация для игр: Steam, Gamescope, VR и оптимизация производительности.

## Структура

| Файл | Назначение | |------|------------| | `default.nix` | Точка входа с опциями | |
`launchers.nix` | Steam, Heroic, Prismlauncher | | `performance.nix` | Gamescope presets, Gamemode,
MangoHud | | `vr.nix` | Лаунчеры VR (SteamVR, DeoVR) |

## Опции

```nix
profiles.games = {
  enable = true;              # Включить игры
  autoscaleDefault = false;   # Авто-скейлинг FPS
  targetFps = 240;            # Целевой FPS
  nativeBaseFps = 240;        # Базовый FPS
};
```

## Скрипты

Скрипты в `packages/game-scripts/`:

- `game-run` — Лаунчер с привязкой к CPU
- `gamescope-perf` — Пресет FSR даунскейла
- `gamescope-quality` — Пресет нативного разрешения
- `gamescope-hdr` — Пресет HDR

## Использование

```bash
game-run %command%                    # Только привязка CPU
game-run gamescope-perf -- %command%  # С FSR
MANGOHUD=1 game-run %command%         # С оверлеем
```
