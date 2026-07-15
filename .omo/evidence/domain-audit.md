# Domain Usage Audit for Host `odin`

**Date**: 2026-07-15\
**Scope**: Extra domains beyond `basicDomains` in `allDomains` (from `flake/nixos.nix`)\
**Method**: Grep `hosts/odin/` and transitive profile/role modules for each domain name, feature
flag references, and option references.

## Legend

- **KEEP**: Domain modules provide config actively used or referenced by odin.
- **SKIP**: Domain modules provide config not needed by odin (zero odin references).

## Audit Table

| Domain | Verdict | Evidence | |--------|---------|----------| | **appimage** | **SKIP** | No
references to `appimage` in `hosts/odin/*.nix`. No `features.appimage.*` feature flags exist. The
module unconditionally sets `boot.binfmt.registrations.appimage` — not needed on odin. | | **apps**
| **SKIP** | Only provides `apps/obsidian/default.nix` guarded by `features.apps.obsidian.enable`.
Odin uses Obsidian via Flatpak (see `default.nix:121` comment). Odin sets
`features.apps.guiAppsFull.enable = false` — this is a feature flag in `features/apps.nix` (part of
`features` domain, always imported), not the `apps` domain module. | | **dev** | **KEEP** | Odin
`services.nix:38-41` enables `features.dev.ai.opencode`, `features.dev.ai.pi`, `features.dev.tla`.
Odin `default.nix:129` sets `features.dev.haskell.enable = false` and `default.nix:135` sets
`features.dev.cpp.enable = true`. `dev` profile enables many dev feature flags. | | **emulators** |
**KEEP** | `desktop` profile (`profiles/desktop.nix:18`) sets
`features.emulators.retroarch.full = mkDefault true`. Module `emulators/pkgs.nix` conditionally
installs retroarch/extra packages. | | **flatpak** | **KEEP** | Module unconditionally enables
`services.flatpak` and installs Obsidian via Flatpak. Odin `default.nix:121` comment confirms
"Obsidian installed via Flatpak". | | **fun** | **KEEP** | `desktop` profile sets
`features.fun.enable = mkDefault true`. Module `fun/launchers-packages.nix` installs Proton/Wine
helpers for gaming. | | **games** | **KEEP** | Odin uses `gaming` profile (`default.nix:111`).
Gaming profile sets `features.games.enable = mkDefault true`. Module `games/controllers.nix` adds
DualSense udev rules. | | **llm** | **SKIP** | Odin explicitly sets `ollama.enable = false`
(`services.nix:385`). `features.llm.enable` defaults to false and is not set by odin. The
`services.ollama` option exists from nixpkgs regardless. | | **media** | **KEEP** | `desktop`
profile enables `features.media.audio.{core,apps,creation,mpd}`. Odin `services.nix:50` sets
`roles.media.enable = true` (enables MPD + Avahi). Shairport-sync audio service configured. | |
**servers** | **KEEP** | Odin enables `roles.homelab` (adguardhome, unbound, openssh, mpd) and
`roles.media` (mpd, avahi, openssh). `servicesProfiles` configure adguardhome, avahi, samba,
duckdns. Unbound, shairport-sync services active. | | **torrent** | **KEEP** | `desktop` profile
sets `features.torrent.enable = mkDefault true`. Module conditionally installs Transmission
packages. | | **user** | **KEEP** | Provides nix-maid (Hyprland, scratchpads, workspaces), GUI
packages, fonts, XDG config. Odin configures `users.main` and uses desktop profile. Core for GUI
usage. | | **web** | **SKIP** | Module has empty imports — provides nothing. Feature flags
(`features.web.*`) are defined in `features/web.nix` (part of `features` domain, always imported).
Vivaldi config is in `user/nix-maid/web/` (part of `user` domain). |

## `odinDomains` (reduced set)

```nix
odinDomains = basicDomains ++ [
  "dev" "emulators" "flatpak" "fun" "games"
  "media" "servers" "torrent" "user"
];
```

### Domains excluded vs `allDomains`

| Domain | Reason for exclusion | |--------|---------------------| | appimage | Zero odin
references, unconditional module, not needed | | apps | Odin uses Flatpak for Obsidian; module
guarded by unused flag | | llm | Ollama explicitly disabled; nixpkgs provides `services.ollama`
option | | web | Empty module (no imports); feature flags in `features` domain |
