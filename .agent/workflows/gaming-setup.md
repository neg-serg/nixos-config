---
description: Configure gaming with Steam and Gamescope
---

# Gaming Setup

## Enable Gaming

In your host configuration:

```nix
profiles.games.enable = true;
```

## Steam Launch Options

### Basic (CPU pinning):

```
game-run %command%
```

### With Gamescope FSR:

```
game-run gamescope-perf -- %command%
```

### With MangoHud overlay:

```
MANGOHUD=1 game-run %command%
```

### Full setup:

```
MANGOHUD=1 game-run gamescope-perf -- %command%
```

## Available Presets

| Script | Purpose |
|--------|---------|
| `game-run` | CPU pinning to V-Cache CCD |
| `gamescope-perf` | FSR downscale for performance |
| `gamescope-quality` | Native resolution |
| `gamescope-hdr` | HDR pipeline |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GAME_PIN_CPUSET` | Override CPU cores |
| `MANGOHUD=1` | Enable MangoHud |
| `GAME_RUN_USE_GAMEMODE=0` | Disable gamemode |

## Troubleshooting

Check CPU pinning:

```bash
cat /proc/self/status | grep Cpus_allowed_list
```
