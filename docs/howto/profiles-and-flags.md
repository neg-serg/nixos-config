# Profiles and feature flags

- Profiles: feature-flag bundles under `modules/profiles/`:

  - `profiles.desktop` — GUI defaults (features.gui.\* = mkDefault true)
  - `profiles.gaming` — gaming optimizations + GUI apps
  - `profiles.dev` — development toolchains

- Service profiles: toggle per‑service via `servicesProfiles.<name>.enable` (declared in
  `modules/profiles/services.nix`). The former `profiles.services.*` alias module was removed as
  dead code (audit 2026-09-15) — nothing ever set those aliases.

  - Hosts set desired values directly (no mkForce needed).

- Host‑specific config: keep concrete settings under `hosts/<host>/*.nix`.

  - Examples: NIC names, local DNS rewrites.

Example (host):

```nix
{ lib, ... }: {
  # Profiles are composed per host; disable heavy services here if needed
  profiles.services = {
    adguardhome.enable = false;
  };
}
```

Service override examples

```nix
# MPD: change music dir/port and add an extra output
# (all options live under services.mpd.settings, see `man mpd.conf`)
{ ... }: {
  services.mpd.settings = {
    music_directory = "/srv/media/music";
    port = 6601;
    audio_output = [
      {
        type = "alsa";
        name = "USB DAC";
        device = "hw:USB";
      }
    ];
  };
}
```
