______________________________________________________________________

## description: Configure gaming with Steam and Gamescope / Настройка игр со Steam и Gamescope

# Gaming Setup / Настройка игр

## Enable Gaming / Включение игр

In your host configuration / В конфигурации хоста:

```nix
profiles.games.enable = true;
```

## Steam Launch Options / Опции запуска Steam

### Basic (CPU pinning) / Базовый (привязка CPU):

```
game-run %command%
```

### With Gamescope FSR / С Gamescope FSR:

```
game-run gamescope-perf -- %command%
```

### With MangoHud overlay / С оверлеем MangoHud:

```
MANGOHUD=1 game-run %command%
```

### Full setup / Полная настройка:

```
MANGOHUD=1 game-run gamescope-perf -- %command%
```

## Available Presets / Доступные пресеты

| Script | Purpose / Назначение | |--------|---------------------| | `game-run` | CPU pinning to
V-Cache CCD | | `gamescope-perf` | FSR downscale for performance | | `gamescope-quality` | Native
resolution | | `gamescope-hdr` | HDR pipeline |

## Environment Variables / Переменные окружения

| Variable | Description / Описание | |----------|----------------------| | `GAME_PIN_CPUSET` |
Override CPU cores / Переопределить ядра | | `MANGOHUD=1` | Enable MangoHud / Включить MangoHud | |
`GAME_RUN_USE_GAMEMODE=0` | Disable gamemode |

## Troubleshooting / Устранение проблем

Check CPU pinning / Проверить привязку CPU:

```bash
cat /proc/self/status | grep Cpus_allowed_list
```
