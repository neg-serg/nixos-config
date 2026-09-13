{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser mainGroup homeDir;

  # Whisper model for local transcription (multilingual, ~488 MB)
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
    hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
    name = "ggml-small.bin";
  };

  hyprwhsprConfig = pkgs.writeText "hyprwhspr-config.jsonc" (
    builtins.replaceStrings [ "@HOMEDIR@" ] [ "${homeDir}" ] (
      builtins.readFile (config.lib.neg.path "files/hyprwhspr/config.jsonc")
    )
  );
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui.hyprwhspr") {
    services.hyprwhspr-rs.enable = true;

    systemd.tmpfiles.rules = [
      "d ${homeDir}/.config/hyprwhspr-rs 0755 ${mainUser} ${mainGroup} -"
      "L+ ${homeDir}/.config/hyprwhspr-rs/config.jsonc - ${mainUser} ${mainGroup} - ${hyprwhsprConfig}"
      "d ${homeDir}/.local/share/hyprwhspr-rs/models 0755 ${mainUser} ${mainGroup} -"
      "L+ ${homeDir}/.local/share/hyprwhspr-rs/models/ggml-small.bin - ${mainUser} ${mainGroup} - ${whisperModel}"
    ];
  };
}
