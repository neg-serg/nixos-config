##  Module: user/nix-maid/apps/renoise
# Purpose: Keep Renoise's JACK output ports linked into the shared PipeWire
# graph. Renoise runs under pw-jack (packages/overlay.nix), and pipewire-jack
# does NOT auto-connect client ports, so without this watcher the tracker is
# silent even though its JACK driver initialises fine.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  # Renoise's JACK client name is "renoise" (PipeWire appends -N on name
  # collisions), and its stereo output ports are output_01_left/right. Link
  # them to the game-stereo virtual sink (routed to the RME AES pair by the
  # hdspe module) whenever they appear, surviving tracker restarts.
  renoiseLinkScript = pkgs.writeShellScript "renoise-link" ''
    set -u
    while true; do
      left=$(pw-link -o 2>/dev/null | grep -m1 -E '^renoise[^:]*:output_01_left$' || true)
      right=$(pw-link -o 2>/dev/null | grep -m1 -E '^renoise[^:]*:output_01_right$' || true)
      if [[ -n "$left" && -n "$right" ]]; then
        pw-link "$left" game-stereo:playback_FL 2>/dev/null || true
        pw-link "$right" game-stereo:playback_FR 2>/dev/null || true
      fi
      sleep 2
    done
  '';
in
{
  config = lib.mkIf enabled {
    systemd.user.services."renoise-link" = {
      description = "Link Renoise JACK out ports to game-stereo";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        ExecStart = "${renoiseLinkScript}";
        Environment = "PATH=${
          lib.makeBinPath [
            config.services.pipewire.package # pw-link
            pkgs.gnugrep # grep
            pkgs.coreutils # sleep
          ]
        }";
      };
    };
  };
}
