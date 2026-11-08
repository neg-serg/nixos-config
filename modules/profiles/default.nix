#
# Profiles and feature flags
# (keep this header in sync with the code it describes)
#
#
# - Bundle profiles: `features.profiles` is a list of bundle names; each name
#   imports `modules/profiles/<name>.nix`, which sets feature-flag defaults via
#   `mkDefault` (later list entries win):
#
#   - `desktop` — GUI defaults (features.gui.\* = mkDefault true)
#   - `gaming` — gaming optimizations + GUI apps
#   - `dev` — development toolchains
#
# - Option profiles: a separate mechanism, unrelated to `features.profiles`.
#   `profiles.<name>.enable` gates kernel/performance/security settings. Names
#   live next to what they configure: debug, performance, security, vm and work
#   in this directory, `games` in `modules/user/games/`, `network` in
#   `modules/system/net/`.
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
#       # Service profiles are composed per host; disable heavy services here.
#       servicesProfiles = {
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
    type = lib.types.listOf (
      lib.types.enum [
        "desktop"
        "gaming"
        "dev"
      ]
    );
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
