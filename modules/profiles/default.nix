#
# Profiles and feature flags
# (folded from docs/howto/profiles-and-flags.md; keep it in sync with the code it describes)
#
#
# - Profiles: feature-flag bundles under `modules/profiles/`:
#
#   - `profiles.desktop` — GUI defaults (features.gui.\* = mkDefault true)
#   - `profiles.gaming` — gaming optimizations + GUI apps
#   - `profiles.dev` — development toolchains
#
# - Service profiles: toggle per‑service via `servicesProfiles.<name>.enable` (declared in
#   `modules/profiles/services.nix`). The former `profiles.services.*` alias module was removed as
#   dead code (audit 2026-09-15) — nothing ever set those aliases.
#
#   - Hosts set desired values directly (no mkForce needed).
#
# - Host‑specific config: keep concrete settings under `hosts/<host>/*.nix`.
#
#   - Examples: NIC names, local DNS rewrites.
#
# Example (host):
#
#     { lib, ... }: {
#       # Profiles are composed per host; disable heavy services here if needed
#       profiles.services = {
#         adguardhome.enable = false;
#       };
#     }
#
# Service override examples
#
#     # MPD: change music dir/port and add an extra output
#     # (all options live under services.mpd.settings, see `man mpd.conf`)
#     { ... }: {
#       services.mpd.settings = {
#         music_directory = "/srv/media/music";
#         port = 6601;
#         audio_output = [
#           {
#             type = "alsa";
#             name = "USB DAC";
#             device = "hw:USB";
#           }
#         ];
#       };
#     }

{
  neg,
  lib,
  ...
}:
{
  options.features.profiles = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "desktop" ];
    description = ''
      List of enabled system profiles. Each profile sets a bundle of feature-flag defaults
      via mkDefault. Order matters — profiles listed later override earlier ones.
      Available: desktop, gaming, dev.
    '';
  };

  # All profiles always imported (Nix is lazy — they only run when mkIf condition passes).
  imports = neg.importDir { dir = ./.; };
}
