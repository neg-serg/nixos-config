# Games Module

Gaming configuration for Steam, Gamescope, VR, and performance optimization.

## Structure

| File | Purpose |
|------|---------|
| `default.nix` | Entry point with options (`profiles.games.*`) |
| `launchers.nix` | Steam, Heroic, Prismlauncher |
| `performance.nix` | Gamescope presets, Gamemode, MangoHud |
| `vr.nix` | SteamVR, DeoVR launchers |

## Options

```nix
profiles.games = {
  enable = true;              # Enable gaming stack
  autoscaleDefault = false;   # Auto-scale FPS heuristics
  targetFps = 240;            # Target FPS for autoscale
  nativeBaseFps = 240;        # Baseline for autoscale
};
```

## Scripts

Scripts consolidated in `packages/game-scripts/`:
- `game-run` — Main launcher with CPU pinning
- `gamescope-perf` — FSR downscale preset
- `gamescope-quality` — Native resolution preset
- `gamescope-hdr` — HDR pipeline preset

## Usage

Steam launch options:
```bash
game-run %command%                    # CPU pinning only
game-run gamescope-perf -- %command%  # With FSR
MANGOHUD=1 game-run %command%         # With overlay
```
