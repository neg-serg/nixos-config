# Games Module / Модуль игр

Gaming configuration for Steam, Gamescope, VR, and performance optimization.

Конфигурация для игр: Steam, Gamescope, VR и оптимизация производительности.

## Structure / Структура

| File | Purpose / Назначение |
|------|---------|
| `default.nix` | Entry point with options / Точка входа с опциями |
| `launchers.nix` | Steam, Heroic, Prismlauncher |
| `performance.nix` | Gamescope presets, Gamemode, MangoHud |
| `vr.nix` | SteamVR, DeoVR launchers / Лаунчеры VR |

## Options / Опции

```nix
profiles.games = {
  enable = true;              # Enable gaming stack / Включить игры
  autoscaleDefault = false;   # Auto-scale FPS heuristics
  targetFps = 240;            # Target FPS for autoscale
  nativeBaseFps = 240;        # Baseline for autoscale
};
```

## Scripts / Скрипты

Scripts in `packages/game-scripts/`:
- `game-run` — Main launcher with CPU pinning / Лаунчер с привязкой к CPU
- `gamescope-perf` — FSR downscale preset
- `gamescope-quality` — Native resolution preset
- `gamescope-hdr` — HDR pipeline preset

## Usage / Использование

```bash
game-run %command%                    # CPU pinning only
game-run gamescope-perf -- %command%  # With FSR
MANGOHUD=1 game-run %command%         # With overlay
```
