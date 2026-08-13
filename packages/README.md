# Packages

Custom packages and overlays for the configuration.

## Structure

| Directory | Purpose | |-----------|---------| | `overlay.nix` | Main overlay entry | | `overlays/`
| Overlay helpers (functions, tools, media, gui, aur-ported) | | `local-bin/` | User scripts for
`~/.local/bin` | | `game/` | Rust gaming launcher (CPU pinning, gamescope presets) |

## Usage

Packages are available via `pkgs.<name>` or `pkgs.neg.<name>`:

```nix
environment.systemPackages = [ pkgs.flight-gtk-theme ];
```

## Adding Packages

1. Create `packages/my-package/default.nix`
1. Add to `packages/overlay.nix`
1. Reference via `pkgs.my-package`
