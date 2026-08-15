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
    };
    photo.enable = mkBool "enable photography workflow (darktable, rawtherapee, testdisk)" false;
    webcam.enable = mkBool "enable virtual webcam support (v4l2loopback)" false;
  };
}
