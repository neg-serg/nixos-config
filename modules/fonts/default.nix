{lib, config, pkgs, ...}: let
  guiEnabled = config.features.gui.enable or false;
  packages = [
    pkgs.pango
  ];
in {
  config = lib.mkIf guiEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
