{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  userGroup = lib.attrByPath [ "group" ] user userData;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;

  # Whisper model for local transcription (multilingual, ~488 MB)
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
    hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
    name = "ggml-small.bin";
  };

  hyprwhsprConfig = pkgs.writeText "hyprwhspr-config.jsonc" ''
    {
      // local whisper.cpp transcription, no API keys
      "audio_feedback": true,
      "start_sound_volume": 0.1,
      "stop_sound_volume": 0.1,
      "auto_copy_clipboard": true,
      "transcription": {
        "provider": "whisper_cpp",
        "request_timeout_secs": 45,
        "whisper_cpp": {
          "model": "ggml-small.bin",
          "threads": 12,
          "gpu_layers": 0,
          "fallback_cli": true,
          "no_speech_threshold": 0.6,
          "models_dirs": [ "${homeDir}/.local/share/hyprwhspr-rs/models" ]
        }
      }
    }
  '';
in
{
  services.hyprwhspr-rs.enable = true;

  systemd.tmpfiles.rules = [
    "d ${homeDir}/.config/hyprwhspr-rs 0755 ${user} ${userGroup} -"
    "L+ ${homeDir}/.config/hyprwhspr-rs/config.jsonc - ${user} ${userGroup} - ${hyprwhsprConfig}"
    "d ${homeDir}/.local/share/hyprwhspr-rs/models 0755 ${user} ${userGroup} -"
    "L+ ${homeDir}/.local/share/hyprwhspr-rs/models/ggml-small.bin - ${user} ${userGroup} - ${whisperModel}"
  ];
}
