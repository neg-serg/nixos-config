# NixOS Features Overview

This document maps the main `features.*` options used by this NixOS/nix-maid setup, their defaults,
and how profiles affect them. It also notes where the libretro allowlist lives and how to toggle
`retroarchFull`.

## Profiles

- `features.profile`: `"full" | "lite"` (default: `"full"`)
  - Profile influences defaults via `modules/default.nix`.
  - You can still override any option after the profile is set.

## Web Stack (`modules/user/nix-maid/web`)

- `features.web.enable` (default: true in full, false in lite)
- `features.web.tools.enable` (aria2, yt‑dlp, misc tools)
  - Default: true in full, false in lite
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
  - Default: true in full, false in lite
- `features.media.audio.apps.enable` (players, tagging, analysis tools)
  - Default: true in full, false in lite
- `features.media.audio.creation.enable` (DAW, synths)
  - Default: true in full, false in lite
- `features.media.audio.mpd.enable` (mpd, mpdris2, clients)
  - Default: true in full, false in lite

## Emulators / RetroArch (`modules/emulators/default.nix`)

- `features.emulators.retroarch.full` (use `retroarchFull` with extended cores)
  - Default: true in full, false in lite (and false by default outside profiles)
  - When enabled, extra unfree libretro cores are auto‑allowlisted (see below).

## Unfree Policy

The central unfree policy and presets live in:

- `modules/features/core.nix` (defines `features.allowUnfree` options)
- `modules/features-data/unfree-presets.nix` (presets)
  - Preset `desktop` currently includes: `abuse`, `ocenaudio`, `vcv-rack`, `vital`,
    `stegsolve`, `volatility3`,
    `ai-studio` (or `lmstudio` on older nixpkgs).

Libretro allowlist (gated by RetroArch mode) lives in:

- `modules/emulators/pkgs.nix`
  - Adds common libretro cores to `features.allowUnfree.extra` only when
    `features.emulators.retroarch.full = true`.

You can always extend with your own names via:

- `features.allowUnfree.extra = [ "pkgName1" "pkgName2" ];`
- Or override entirely via `features.allowUnfree.allowed`.

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

- `features.dev.pkgs.iac` — include Infrastructure‑as‑Code CLI (default: true in full profile)
- `features.dev.iac.backend` — choose backend: `"terraform" | "tofu"` (default: `"terraform"`)
  - When `terraform` is selected, the unfree predicate auto‑allowlists it.
  - Packages are added via `modules/dev/pkgs/default.nix`.
