##
# Module: nix-maid/gui/noctalia
# Purpose: Noctalia v5 — Wayland shell (bar, launcher, etc.)
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  noctaliaEnabled =
    config.features.gui.enable or false
    && config.features.gui.noctalia.enable or false
    && !(config.features.devSpeed.enable or false);
  noctaliaPkg = inputs.noctalia.packages.${system}.default;
in
lib.mkIf noctaliaEnabled {
  environment.systemPackages = [
    noctaliaPkg # Noctalia Wayland shell (bar, launcher, notifications)
  ];

  systemd.user.services.noctalia = {
    enable = true;
    description = "Noctalia Wayland shell";
    documentation = [ "https://docs.noctalia.dev/v5/" ];
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe noctaliaPkg}";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStopSec = "5s";
      Slice = "session.slice";
    };
  };
}
