##  Module: user/nix-maid/apps/renoise
# Purpose: Keep Renoise's JACK output ports linked into the shared PipeWire
# graph. Renoise runs under pw-jack (packages/overlay.nix), and pipewire-jack
# does NOT auto-connect client ports, so without this watcher the tracker is
# silent even though its JACK driver initialises fine.
{
  lib,
  config,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  # Port watcher unit (lib/jack-app.nix): the pw-link poll loop, the unit
  # policy and the PATH live there, shared with the other JACK clients.
  jackApp = config.lib.neg.jackApp;
in
{
  config = lib.mkIf enabled {
    # Renoise's JACK client name is "renoise" (PipeWire appends -N on name
    # collisions), and its stereo output ports are output_01_left/right. Link
    # them to the game-stereo virtual sink (routed to the RME AES pair by the
    # hdspe module) whenever they appear, surviving tracker restarts.
    systemd.user.services."renoise-link" = jackApp.mkUnit {
      name = "renoise-link";
      description = "Link Renoise JACK out ports to game-stereo";
      client = "renoise";
      pairs = [
        {
          from = "output_01_left";
          to = "playback_FL";
        }
        {
          from = "output_01_right";
          to = "playback_FR";
        }
      ];
      sink = "game-stereo";
    };
  };
}
