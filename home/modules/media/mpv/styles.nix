{
  lib,
  config,
  ...
}:
lib.mkIf (config.features.gui.enable or false) {
  xdg.configFile."mpv/styles.ass".source = ./styles.ass;
}
