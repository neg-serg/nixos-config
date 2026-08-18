{ lib, mkBool, ... }:
with lib;
{
  options.features.media = {
    aiUpscale = {
      enable = mkBool "enable AI upscaling integration for video (mpv)" false;
    };
    audio = {
      core.enable = mkBool "enable audio core (PipeWire routing tools)" true;
      apps.enable = mkBool "enable audio apps (players, tools)" true;
      creation.enable = mkBool "enable audio creation stack (DAW, synths)" true;
      mpd.enable = mkBool "enable MPD stack (mpd, clients, mpdris2)" true;
      # LAN audio access: MPD binds to all interfaces, PipeWire exposes a
      # Pulse-compatible TCP server (port 4713) and an RTP multicast sink.
      lanAccess = {
        enable = mkBool "LAN audio access (MPD on all interfaces, PipeWire Pulse TCP 4713, RTP sink)" false;
        rtp = {
          interface = lib.mkOption {
            type = lib.types.str;
            default = "net1";
            description = "Network interface used by the PipeWire RTP sink for multicast output.";
          };
        };
      };
      spotify.enable = mkBool "enable Spotify stack (spotifyd daemon, spotify-tui)" false;
      carlaLoopback.enable = mkBool "enable virtual loopback sink for Carla" false;
      cider.enable = mkBool "enable Cider (Apple Music client)" false;
      spicetify.enable = mkBool "enable Spicetify (Spotify customization)" false;
      beets = {
        enable = mkBool "enable Beets music library manager" true;
        mode = lib.mkOption {
          type = lib.types.enum [
            "native"
            "distrobox"
          ];
          default = "distrobox";
          description = "Beets runtime mode: native (Nixpkgs) or distrobox (CachyOS container)";
        };
      };
      speech.enable = mkBool "enable local speech stack (Chatterbox TTS :8000, Piper TTS :8001, whisper.cpp STT :8002)" false;
    };
    photo.enable = mkBool "enable photography workflow (darktable, rawtherapee, testdisk)" false;
    webcam.enable = mkBool "enable virtual webcam support (v4l2loopback)" false;
  };
}
