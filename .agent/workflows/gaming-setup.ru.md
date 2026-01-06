---
description: Настройка игр со Steam и Gamescope
---

# Настройка игр

## Включение игр

В конфигурации хоста:

```nix
profiles.games.enable = true;
```

## Опции запуска Steam

### Базовый (привязка CPU):

```
game-run %command%
```

### С Gamescope FSR:

```
game-run gamescope-perf -- %command%
```

### С оверлеем MangoHud:

```
MANGOHUD=1 game-run %command%
```

### Полная настройка:

```
MANGOHUD=1 game-run gamescope-perf -- %command%
```

## Доступные пресеты

| Скрипт | Назначение |
|--------|------------|
| `game-run` | Привязка CPU к V-Cache (3D CCD) |
| `gamescope-perf` | FSR (производительность) |
| `gamescope-quality` | Нативное разрешение |
| `gamescope-hdr` | HDR пайплайн |

## Переменные окружения

| Переменная | Описание |
|------------|----------|
| `GAME_PIN_CPUSET` | Переопределить ядра |
| `MANGOHUD=1` | Включить MangoHud |
| `GAME_RUN_USE_GAMEMODE=0` | Отключить gamemode |

## Устранение проблем

Проверить привязку CPU:

```bash
cat /proc/self/status | grep Cpus_allowed_list
```
