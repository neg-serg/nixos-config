# Hyprland Plugin (hy3)

This note pulls together every moving part related to the `hy3` plugin so we can keep it aligned
with the Hyprland compositor without hopping across multiple files.

## Source of Truth and Pinning

- The flake pins Hyprland to v0.55.4 while `hy3` is pinned via the flake inputs (`flake.nix`:12-39).
  The lock file pins the exact commits under that release.
- Supporting inputs (`hyprland-protocols`, `xdg-desktop-portal-hyprland`) follow Hyprland's inputs,
  so once the Hyprland pin is bumped the portal + protocol packages move in lockstep
  (`flake.nix`:22-25).

## nixpkgs Overlay

- `modules/user/nix-maid/hyprland/overlay.nix` (consolidated from the former
  `modules/nix/hyprland.nix`) adds the `hyprglass` decoration plugin to `pkgs.hyprlandPlugins`,
  gated behind `features.gui.enable` so headless hosts skip the `pkgs.hyprland` evaluation.
- The flake-pinned builds are wired in `flake/lib.nix` `hyprlandOverlay`: it routes
  `pkgs.xdg-desktop-portal-hyprland` (pinned input) and `pkgs.hyprlandPlugins.hy3` (`inputs.hy3`) so
  the rest of the configuration consumes them without touching `inputs.*` directly.
- Because everything flows through `pkgs`, Home-Manager modules just reference
  `pkgs.hyprlandPlugins.hy3` and stay agnostic of how the plugin was produced.

## Package Delivery to User Sessions

- The workstation session profile keeps the plugin derivation in the system profile (via the system
  profile). This guarantees the `libhy3.so` payload exists in the store even if a user never
  installs extra Wayland packages manually.

## Home Configuration Wiring

- Everything Hyprland lives under `modules/user/nix-maid/hyprland/` (one domain): `main.nix`
  assembles `environment.nix` (the `hyprland.conf` text: `plugin = hy3/hyprglass` lines plus
  `source` of the lua config), `files.nix` (home-file links: `hyprland.conf`, `hyprland.lua`,
  `hyprlock.conf`, `hypridle.conf`, animations), and `services.nix` (systemd user services + the
  Hyprland-related package set, incl. the session packages formerly in
  `modules/user/session/hyprland.nix`).
- `files.nix` also writes the `permission = ..., plugin, allow` stanza into `hyprland.conf`,
  ensuring hy3 can register without triggering the ecosystem permission guard, plus the wlroots
  screencopy hardening permissions for grim/hyprlock.

## Updating Hyprland + hy3

1. Hyprland itself bumps with nixpkgs (`nix flake lock --update-input nixpkgs`); refresh the
   companion pins with `nix flake update hy3 xdg-desktop-portal-hyprland` (the dedicated `hyprland`
   flake input was removed).
1. Rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.
1. Optional: add `--update-input hy3 --update-input xdg-desktop-portal-hyprland` to
   `system.autoUpgrade` if you want unattended bumps; otherwise keep the updates manual to review
   ABI churn.

Because the overlay flows through `pkgs`, no Home-Manager changes are needed when updating; the new
plugin propagates automatically once the system rebuild succeeds.

## Verification Checklist

- Quick health checks after any update:
  - `nix path-info .#legacyPackages.<system>.hyprlandPlugins.hy3` should print the store path that
    backs the plugin for that host's build (replace `<system>` with `x86_64-linux`, etc.).
  - `grep plugin ~/.config/hypr/hyprland.conf` should show the expected `hy3`/`hyprglass` `.so`
    paths exported by `pkgs.hyprlandPlugins.*` (the old `plugins.conf` was folded into
    `hyprland.conf`).
  - `Hyprland --version` output should match the Hyprland commit recorded in `flake.lock` to confirm
    the plugin and compositor were updated together.

Keeping the above pieces in sync prevents the common ABI mismatch issues that surface when hy3 lags
behind Hyprland.
