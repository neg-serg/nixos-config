##
# Module: media/audio/mpd-voice
# Purpose: install the MPD voice client (mpd-voice) and its system-wide config.
# Key options: features.media.audio.mpdVoice.{enable,language,wakeWord,stt,tts}
# Dependencies: pkgs.mpd-voice (overlay), optional speech backends from
#               features.media.audio.speech (STT :8002 / TTS :8001).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.mpdVoice;
  enabled = config.lib.neg.enabled "media.audio.mpdVoice";

  # Only the settings the client understands; the file is a starting point —
  # ~/.config/mpd-voice/config.toml overrides it key by key.
  settings = lib.filterAttrs (_: value: value != "") {
    language = cfg.language;
    wake_word = cfg.wakeWord;
    stt = cfg.stt;
    stt_url = cfg.sttUrl;
    tts = cfg.tts;
    tts_url = cfg.ttsUrl;
  };
  # lib.generators.toJSON quotes strings, which is exactly TOML's basic string
  # syntax for the simple values used here.
  tomlLine = key: value: "${key} = ${lib.generators.toJSON { } value}";
  configText =
    lib.concatStringsSep "\n" ([ "[mpd-voice]" ] ++ lib.mapAttrsToList tomlLine settings) + "\n";
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [
      pkgs.mpd-voice # voice control for MPD: local STT -> player commands
    ];

    # XDG default; the user file (~/.config/mpd-voice/config.toml) wins. The
    # CLI takes the same values as flags, so this is convenience, not a gate.
    environment.etc."xdg/mpd-voice/config.toml".text = configText;
  };
}
