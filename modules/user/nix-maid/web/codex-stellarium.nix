{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.features.web.codexStellarium;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;

  extPkg = import "${inputs.codex-stellarium}/pkgs/codex-stellarium-vivaldi" {
    inherit (pkgs) stdenvNoCC lib;
  };
in {
  config = mkIf (webEnabled && guiEnabled && cfg.enable) {
    environment.systemPackages = [ extPkg ];

    systemd.tmpfiles.rules = [
      "d /home/neg/.local/share/codex-stellarium 0755 neg users -"
      "L+ /home/neg/.local/share/codex-stellarium/vivaldi - - - - ${extPkg}/share/codex-stellarium-vivaldi"
    ];
  };
}
