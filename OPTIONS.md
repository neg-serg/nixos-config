# NixOS Features Overview

This document maps the main `features.*` options used by this NixOS/nix-maid setup, their defaults,
and how profiles affect them. It also notes where the libretro allowlist lives and how to toggle
`retroarchFull`.

## Profiles

- `features.profiles`: list of active profiles (default: `["desktop"]`)
  - Available: `desktop`, `gaming`, `audio-pro`, `dev`.
  - Each profile sets feature-flag defaults via `modules/profiles/<name>.nix`
    (`mkDefault`); order matters — later profiles override earlier ones.
  - You can still override any option after the profiles are set.

## Web Stack (`modules/user/nix-maid/web`)

- `features.web.enable` (default: true — set by the `desktop` profile)
- `features.web.tools.enable` (aria2, yt‑dlp, misc tools)
  - Default: true (desktop profile)
- `features.web.vivaldi.enable` (Vivaldi browser)
  - Default: false
  - Installs `pkgs.vivaldi` with Wayland flags via `--ozone-platform-hint=wayland`
  - Extensions force‑installed via Chromium managed policies: SurfingKeys
  - Chromium policies applied: disabled password manager, blocked notifications, no metrics,
    standard safe browsing, disabled search suggestions, no sync, home button shown
- `features.web.chat.enable` (Telegram chat client)
  - Default: true
  - Installs `telegram-desktop` and `tdl`, pulls in webkitgtk
- `features.web.default` (default browser)
  - Type: one of `"vivaldi" | "chrome" | "brave" | "edge"`
  - Default: `null` (no default set)
  - Selected browser record is exposed at `config.lib.neg.web.defaultBrowser` with fields
    `{ name, pkg, bin, desktop, newTabArg }`.
  - The full table is available as `config.lib.neg.web.browsers`.

## Audio Stack (`modules/media/audio`)

- `features.media.audio.core.enable` (PipeWire routing tools)
  - Default: true (desktop/audio-pro profiles)
- `features.media.audio.apps.enable` (players, tagging, analysis tools)
  - Default: true (desktop/audio-pro profiles)
- `features.media.audio.creation.enable` (DAW, synths)
  - Default: true (desktop/audio-pro profiles)
- `features.media.audio.mpd.enable` (mpd, mpdris2, clients)
  - Default: true (desktop/audio-pro profiles)

## Emulators / RetroArch (`modules/emulators/default.nix`)

- `features.emulators.retroarch.full` (use `retroarchFull` with extended cores)
  - Default: true (desktop profile), false otherwise

## Unfree Policy

Unfree packages are allowed globally:

- `flake/lib.nix` (`config.allowUnfree = true`) — applied to all system `pkgs`.
- `flake/pkgs-config.nix` — nixpkgs config for the flake's own package builds.

The per-feature allowlist (`features.allowUnfree.*` + `features-data/`) was
removed — it was never read by any module.

## Package Exclusions

- `features.excludePkgs = [ "pkgName" ... ]`
  - Globally exclude packages (by `pname`) from curated module lists that adopt this filter (e.g.,
    pentest/sniffing).
  - Useful to avoid building/adding problematic packages without modifying module files.

## Extra Arguments (flake extraSpecialArgs)

These are passed from `flake.nix` into modules for convenience (camelCase):


- `iosevkaNeg` — system package set from the custom Iosevka flake input. Used in
  `modules/user/theme/default.nix`.

## Ready‑Made Configurations

- Full: `.#homeConfigurations.neg.activationPackage`

Switch examples:

- `sudo nixos-rebuild switch --flake .#odin`

## Developer Notes

- Commit subjects are enforced to start with `[scope]` via a local hook in `.githooks/commit-msg`.
  - Enable it with: `git config core.hooksPath .githooks` or `just hooks-enable`

## IaC (Terraform / OpenTofu)

- `features.dev.pkgs.iac` — include Infrastructure-as-Code CLI (default: true — set by the `dev` profile)
