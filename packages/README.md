# Packages

Custom packages and overlays for the configuration.

## Structure

| Directory | Purpose | |---------------------|---------------------------------------| |
`overlay.nix` | Main overlay entry | | `overlays/` | Overlay helpers (functions, tools, media, dev)
| | `game-scripts/` | Gaming launchers and CPU pinning | | `rofi-config/` | Rofi themes and wrappers
| | `local-bin/` | User scripts for `~/.local/bin` | | `flight-gtk-theme/` | GTK theme package |

## Usage

Packages are available via `pkgs.<name>` or `pkgs.neg.<name>`:

```nix
environment.systemPackages = [ pkgs.flight-gtk-theme ];
```

## Adding Packages

1. Create `packages/my-package/default.nix`
1. Add to `packages/overlay.nix`
1. Reference via `pkgs.my-package`
