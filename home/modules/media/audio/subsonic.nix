{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.modules.media.audio.subsonic;
in {
  options.modules.media.audio.subsonic = {
    enable = mkEnableOption "subsonic clients";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      subsonic-tui
      termsonic
    ];
  };
}
