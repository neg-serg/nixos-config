{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.media = {
    aiUpscale = {
      enable = mkBool "enable AI upscaling integration for video (mpv)" false;
      # realtime: use mpv + VapourSynth hook (fast path; requires VS runtime; falls back to no-op if plugin absent)
      # offline: provide a CLI wrapper to render to a new file via Real-ESRGAN
      mode = lib.mkOption {
        type = lib.types.enum [
          "realtime"
          "offline"
        ];
        default = "realtime";
        description = "AI upscale mode: realtime (mpv VapourSynth) or offline (CLI pipeline).";
      };
      content = lib.mkOption {
        type = lib.types.enum [
          "general"
          "anime"
        ];
        default = "general";
        description = "Tuning/model preference for content type.";
      };
      scale = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Upscale factor for realtime path (2 or 4).";
      };
      installShaders = mkBool "install recommended mpv GLSL shaders (FSRCNNX/SSimSR/Anime4K)" true;
    };
    audio = {
      core.enable = mkBool "enable audio core (PipeWire routing tools)" true;
      apps.enable = mkBool "enable audio apps (players, tools)" true;
      creation.enable = mkBool "enable audio creation stack (DAW, synths)" true;
      mpd.enable = mkBool "enable MPD stack (mpd, clients, mpdris2)" true;
      spotify.enable = mkBool "enable Spotify stack (spotifyd daemon, spotify-tui)" false;
      carlaLoopback.enable = mkBool "enable virtual loopback sink for Carla" false;
      proAudio.enable = mkBool "enable professional audio tools (REW, OpenSoundMeter, rtcqs)" false;
      cider.enable = mkBool "enable Cider (Apple Music client)" false;
      yandexMusic.enable = mkBool "enable Yandex Music client" false;
      spicetify.enable = mkBool "enable Spicetify (Spotify customization)" false;
    };
    photo.enable = mkBool "enable photography workflow (darktable, rawtherapee, testdisk)" false;
    webcam.enable = mkBool "enable virtual webcam support (v4l2loopback)" false;
  };
}
