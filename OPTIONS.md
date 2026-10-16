# NixOS Features Overview

Human-curated notes on how `features.*` flags are composed and overridden in this
repo — profile cascades, unfree policy, exclusions, and notable behaviors.

> **Exhaustive flag reference:** read the declarations — every `features.*` flag carries its type,
> default and description where it is declared (`modules/features/*.nix`, plus flags declared next
> to their domain, e.g. `features.profiles` in `modules/profiles/default.nix`).

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
`hosts/trantor/services/policy.nix`, and `flake/devshells/*` stay static by design.

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
- **Scrobbling** (`features.media.audio.listenbrainzMpd`): installs `listenbrainz-mpd`
  (MPD → ListenBrainz) and emits its user unit only when
  `secrets/home/listenbrainz-mpd.sops.yaml` (key `token`) exists — no secret, no unit.
  `apiUrl` can point at the local Koito hub (`servicesProfiles.koito`, loopback 4110, starts
  without any secret); the mpdas/Last.fm path stays unchanged until the new one is verified.
- **Pleamar shell** (`features.gui.pleamar.enable`, default off): per-scene systemd user units
  (`pleamar-<scene>.service`) run `pkgs.pleamar` on `~/.config/pleamar/shells/<scene>/<scene>.plm`
  with memory/CPU caps, a `pleamar-health` hang watchdog, and nix-maid links of
  `files/pleamar/{shells,lib}` plus a generated `~/.config/pleamar/autostart`. Quickshell stays the
  default shell until the flag is flipped.

## Extra Arguments (flake extraSpecialArgs)

These are passed from `flake/nixos.nix` (`mkSpecialArgs`) into modules for convenience (camelCase):

- `iosevkaNeg` — system package set from the custom Iosevka flake input. Used in
  `modules/fonts/default.nix` and `modules/user/nix-maid/gui/theme.nix`.

## Ready-Made Configurations

- Full: `nix build .#nixosConfigurations.trantor.config.system.build.toplevel`

Switch examples:

- `sudo nixos-rebuild switch --flake .#trantor`

## Developer Notes

- Commit subjects are enforced to start with `[scope]` via a local hook in `.githooks/commit-msg`.
  - Enable it with: `git config core.hooksPath .githooks` or `just hooks-enable`
