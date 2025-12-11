{
  lib,
  config,
  inputs,
  pkgs,
  ...
}: let
  cfg = config.features.net.tailscale or {};
  enabled = cfg.enable or false;
in {
  config = lib.mkIf enabled {
    services.tailscale.enable = true;

    # Tailray: GUI client for Tailscale
    # The tailray package comes from the flake input
    environment.systemPackages = [inputs.tailray.packages.${pkgs.system}.default];

    # Override start ordering for Tailray systemd user service
    # so it waits for graphical session (tray icon requirement)
    systemd.user.services.tailray = {
      wantedBy = ["graphical-session.target"];
      after = lib.mkForce ["graphical-session.target"];
    };
  };
}
