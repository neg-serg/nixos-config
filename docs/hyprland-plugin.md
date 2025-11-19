# Hyprland Plugin (hy3)

This note pulls together every moving part related to the `hy3` plugin so we can keep it aligned with the Hyprland compositor without hopping across multiple files.

## Source of Truth and Pinning

- The flake pins Hyprland and the `hy3` plugin to the Hyprland v0.51.x release series so the plugin ABI always matches the compositor (`flake.nix`:12-39). The lock file pins the exact commits under that release.
- Supporting inputs (`hyprland-protocols`, `xdg-desktop-portal-hyprland`) follow Hyprland's inputs, so once the Hyprland pin is bumped the portal + protocol packages move in lockstep (`flake.nix`:22-25).

## nixpkgs Overlay

- `modules/nix/hyprland.nix` injects an overlay that rewires `pkgs.hyprland`, `pkgs.xdg-desktop-portal-hyprland`, and `pkgs.hyprlandPlugins.hy3` so the rest of the configuration consumes the flake-pinned builds without touching `inputs.*` directly (`modules/nix/hyprland.nix`:1-13).
- Because everything flows through `pkgs`, Home-Manager modules just reference `pkgs.hyprlandPlugins.hy3` and stay agnostic of how the plugin was produced.

## Package Delivery to User Sessions

- The workstation session profile keeps the plugin derivation in the system profile (`modules/user/session/pkgs.nix`:60-83). This guarantees the `libhy3.so` payload exists in the store even if a user never installs extra Wayland packages manually.

## Home Configuration Wiring

- `home/modules/user/gui/hyprland/core.nix` builds `~/.config/hypr/plugins.conf` dynamically and injects `plugin = ${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so` so Hyprland loads hy3 on every graphical login. Hyprsplit support piggybacks on the same helper when that feature flag is on (`home/modules/user/gui/hyprland/core.nix`:38-116).
- The same module also writes the `permission = ..., plugin, allow` stanza directly into `hyprland.conf`, ensuring hy3 can register without triggering the ecosystem permission guard.
- For wlroots screencopy hardening, `home/modules/user/gui/hyprland/permissions.nix` keeps a dedicated `permissions.conf` that includes both the hy3 and hyprsplit plugin paths (if enabled) alongside grim/hyprlock permissions (`home/modules/user/gui/hyprland/permissions.nix`:12-38).

## Updating Hyprland + hy3

1. Run `nix flake update hyprland hy3` to bump both pins (`README.md`:27-39).
2. Rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.
3. Optional: add `--update-input hyprland --update-input hy3` to `system.autoUpgrade` if you want unattended bumps; otherwise keep the updates manual to review ABI churn (same README section).

Because the overlay flows through `pkgs`, no Home-Manager changes are needed when updating; the new plugin propagates automatically once the system rebuild succeeds.

## Migration / Verification Helpers

- `scripts/hm-hy3-system.apply.sh` rewrites a standalone Home-Manager checkout so it consumes the system-managed plugin and drops any lingering hy3 flake inputs. It backs up the touched files, patches flake args, and points `plugins.conf` at `/etc/static/hypr/libhy3.so`, then prints post-run checks (plugin file present, Hyprland reports expected version) (`scripts/hm-hy3-system.apply.sh`:1-93).
- Quick health checks after any update:
  - `nix path-info .#legacyPackages.<system>.hyprlandPlugins.hy3` should print the store path that backs the plugin for that host's build (replace `<system>` with `x86_64-linux`, etc.).
  - `grep plugin ~/.config/hypr/plugins.conf` should show the expected `libhy3.so` path exported by `pkgs.hyprlandPlugins.hy3`.
  - `Hyprland --version` output should match the Hyprland commit recorded in `flake.lock` to confirm the plugin and compositor were updated together.

Keeping the above pieces in sync prevents the common ABI mismatch issues that surface when hy3 lags behind Hyprland.
