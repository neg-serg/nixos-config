# NixOS Features Overview

Human-curated notes on how `features.*` flags are composed and overridden in this
repo — profile cascades, unfree policy, exclusions, and notable behaviors.

> **Exhaustive flag reference is generated, not maintained here:**
> - Full option docs (every `features.*` flag with type/default/description):
>   [`docs/howto/modules.md`](./docs/howto/modules.md) — regenerate with `just docs-modules`
> - Structural map + compact flag list with defaults:
>   [`docs/codebase.md`](./docs/codebase.md) — regenerate with `just codebase`

## Profiles

- `features.profiles`: list of active profiles (default: `["desktop"]`)
  - Available: `desktop`, `gaming`, `dev`.
  - Each profile sets feature-flag defaults via `modules/profiles/<name>.nix`
    (`mkDefault`); order matters — later profiles override earlier ones.
  - You can still override any option after the profiles are set.

## Unfree Policy

Unfree packages are allowed globally:

- `flake/lib.nix` (`config.allowUnfree = true`) — applied to all system `pkgs`.
- `flake/lib.nix` (`mkPkgs`) — nixpkgs config for the flake's own package builds.

The per-feature allowlist (`features.allowUnfree.*` + `features-data/`) was
removed — it was never read by any module.

## Package Exclusions

The `features.excludePkgs` filter was removed: nothing in the repo (or in the `neg-pkgs` flake input)
ever read it into a curated list, and the `config.lib.neg.pkgsList` helper its comment referenced was
never implemented. Dev tooling is gated where it is installed instead — `features.dev.cpp` /
`features.dev.java` control their package lists (`modules/user/nix-maid/sys/dev.nix`,
`modules/dev/java/`), `features.dev.rust` gates the host list in
`hosts/odin/services/policy.nix`, and `flake/devshells/*` stay static by design.

## Notable Behaviors

- **Vivaldi** (`features.web.vivaldi.enable`): installed with Wayland flags
  (`--ozone-platform-hint=wayland`); extensions force-installed via Chromium managed policies
  (SurfingKeys); Chromium policies applied: disabled password manager, blocked notifications, no
  metrics, standard safe browsing, disabled search suggestions, no sync, home button shown.
- **Default browser** (`features.web.default`): the selected record is exposed at
  `config.lib.neg.web.defaultBrowser` with fields `{ name, pkg, bin, desktop, newTabArg }`;
  the full table is `config.lib.neg.web.browsers` (currently only `vivaldi`).
- **RetroArch full** (`features.emulators.retroarch.full`): use `retroarchFull` with extended
  (unfree) cores.
- **Declarative Wine apps** (`features.wine.enable`): Wine runtime
  (`wineWow64Packages.stable` + `winetricks`) and the `wineapps` CLI; per-app prefixes in
  `~/.local/share/wineprefixes/<app>` (bind → `/gamez/main/wineprefixes`), registry at
  `/etc/wineapps/apps.json`. Apps are declared in `features.wine.apps.<id>`
  (installer/executable/winetricks/...); see the `wine-apps` DSH skill for the add/remove workflow.

## Extra Arguments (flake extraSpecialArgs)

These are passed from `flake/nixos.nix` (`mkSpecialArgs`) into modules for convenience (camelCase):

- `iosevkaNeg` — system package set from the custom Iosevka flake input. Used in
  `modules/fonts/default.nix` and `modules/user/nix-maid/gui/theme.nix`.

## Ready-Made Configurations

- Full: `nix build .#nixosConfigurations.odin.config.system.build.toplevel`

Switch examples:

- `sudo nixos-rebuild switch --flake .#odin`

## Developer Notes

- Commit subjects are enforced to start with `[scope]` via a local hook in `.githooks/commit-msg`.
  - Enable it with: `git config core.hooksPath .githooks` or `just hooks-enable`
