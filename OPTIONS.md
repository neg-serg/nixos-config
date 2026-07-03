# NixOS Features Overview

This document maps the main `features.*` options used by this NixOS/nix-maid setup, their defaults,
and how profiles affect them. It also notes where the libretro allowlist lives and how to toggle
`retroarchFull`.

## Profiles

- `features.profile`: `"full" | "lite"` (default: `"full"`)
  - Profile influences defaults via `modules/default.nix`.
  - You can still override any option after the profile is set.

## Web Stack (`modules/user/web`)

- `features.web.enable` (default: true in full, false in lite)
- `features.web.tools.enable` (aria2, yt‑dlp, misc tools)
  - Default: true in full, false in lite
- `features.web.floorp.enable` (Floorp browser)
  - Default: true in full, false in lite
- `features.web.zen.enable` (Zen browser)
  - Default: true
  - Note: profile migrated manually to `~/.config/zen/`; symlink `~/.zen` created via systemd tmpfiles
- `features.web.chat.enable` (Telegram chat client)
  - Default: true
  - Installs `telegram-desktop` and `tdl`, pulls in webkitgtk
- `features.web.prefs.fastfox.enable` (FastFox‑like Mozilla prefs)
  - Default: true in full, false in lite
  - Summary: increases parallelism, enables site isolation (Fission), lazy tab restore, forces
    WebRender, disables inline PDF.
  - Caveats: higher memory usage, possible AMO/RFP interaction, inline PDF disabled.
- `features.web.default` (default browser)
  - Type: one of `"floorp" | "firefox" | "librewolf" | "zen" | "chrome" | "brave" | "vivaldi" | "edge"`
  - Default: `"floorp"`
  - Selected browser record is exposed at `config.lib.neg.web.defaultBrowser` with fields
    `{ name, pkg, bin, desktop, newTabArg }`.
  - The full table is available as `config.lib.neg.web.browsers`.

Notes


  See `flake.nix` and usage in `modules/user/web/browsing.nix`.
- Floorp profile and prefs live in `modules/user/web/floorp.nix`.

Mozilla browsers

- Firefox, LibreWolf and Floorp share a unified constructor in
  `modules/user/web/mozilla-common-lib.nix`:
  - Signature:

    ```nix
    mkBrowser {
      name,
      package,
      profileId ? "default",
      settingsExtra ? {},
      defaults ? {},
      addonsExtra ? [],
      nativeMessagingExtra ? [],
      policiesExtra ? {},
      profileExtra ? {},
      userChromeExtra ? "",
      bottomNavbar ? true,
    }
    ```

  - Browser modules call this to produce their `programs.<name>` blocks, avoiding duplication.

  - Use the `*Extra` fields to extend settings/policies/addons per browser.

  - `bottomNavbar` toggles optional CSS that moves the navigation bar to the bottom. Defaults to
    `true`; Floorp overrides it to `false`.

## Audio Stack (`modules/media/audio`)

- `features.media.audio.core.enable` (PipeWire routing tools)
  - Default: true in full, false in lite
- `features.media.audio.apps.enable` (players, tagging, analysis tools)
  - Default: true in full, false in lite
- `features.media.audio.creation.enable` (DAW, synths)
  - Default: true in full, false in lite
- `features.media.audio.mpd.enable` (mpd, mpdris2, clients)
  - Default: true in full, false in lite

## Emulators / RetroArch (`modules/user/fun/emulators.nix`)

- `features.emulators.retroarch.full` (use `retroarchFull` with extended cores)
  - Default: true in full, false in lite (and false by default outside profiles)
  - When enabled, extra unfree libretro cores are auto‑allowlisted (see below).

## Unfree Policy

The central unfree policy and presets live in:

- `modules/misc/unfree.nix` (wires `nixpkgs.config.allowUnfreePredicate`)
- `modules/features-data/unfree-presets.nix` (presets)
  - Preset `desktop` currently includes: `abuse`, `ocenaudio`, `vcv-rack`, `vital`,
    `stegsolve`, `volatility3`,
    `ai-studio` (or `lmstudio` on older nixpkgs).

Libretro allowlist (gated by RetroArch mode) lives in:

- `modules/misc/unfree-libretro.nix`
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

- `sudo nixos-rebuild switch --flake .#telfir`

## Developer Notes

- Commit subjects are enforced to start with `[scope]` via a local hook in `.githooks/commit-msg`.
  - Enable it with: `git config core.hooksPath .githooks` or `just hooks-enable`

## IaC (Terraform / OpenTofu)

- `features.dev.pkgs.iac` — include Infrastructure‑as‑Code CLI (default: true in full profile)
- `features.dev.iac.backend` — choose backend: `"terraform" | "tofu"` (default: `"terraform"`)
  - When `terraform` is selected, the unfree predicate auto‑allowlists it.
  - Packages are added via `modules/dev/pkgs/default.nix`.
