{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.features.net.tailscale or { };
  enabled = cfg.enable or false;
in
{
  config = lib.mkIf enabled {
    services.tailscale.enable = true;

    # Tailray: GUI client for Tailscale
    # The tailray package comes from the flake input
    environment.systemPackages = [
      inputs.tailray.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]; # GUI client for Tailscale

    # Override start ordering for Tailray systemd user service
    # so it waits for graphical session (tray icon requirement)
    systemd.user.services.tailray = {
      wantedBy = [ "graphical-session.target" ];
      after = lib.mkForce [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe inputs.tailray.packages.${pkgs.stdenv.hostPlatform.system}.default}";
        Restart = "on-failure";
      };
    };
  };
}
