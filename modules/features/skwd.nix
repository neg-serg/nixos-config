{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.gui.skwd;
  guiEnabled = config.features.gui.enable or false;
  skwdEnabled = cfg.enable && guiEnabled && !(config.features.devSpeed.enable or false);
in
lib.mkIf skwdEnabled {
  environment.systemPackages = [ pkgs.skwd ];
  systemd.packages = [ pkgs.skwd ];
}
