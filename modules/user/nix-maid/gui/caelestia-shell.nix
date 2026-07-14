{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  caelestiaShellEnabled =
    config.features.gui.enable or false
    && config.features.gui.caelestia-shell.enable or false
    && !(config.features.devSpeed.enable or false);
  shellPkg = inputs.caelestia-shell.packages.${system}.default;
in
lib.mkIf caelestiaShellEnabled {
  environment.systemPackages = [
    shellPkg # Caelestia Desktop Shell for Hyprland (built on Quickshell)
  ];

  systemd.user.services.caelestia-shell = {
    enable = true;
    description = "Caelestia Desktop Shell";
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe shellPkg}";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStopSec = "5s";
      Environment = [ "QT_QPA_PLATFORM=wayland" ];
      Slice = "session.slice";
    };
  };
}
