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
        ExecStart = let
          tailrayPkg = inputs.tailray.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in "${lib.getExe (pkgs.writeShellScript "tailray-wrapped" ''
          set -euo pipefail
          TAILRAY="${lib.getExe tailrayPkg}"
          for i in $(seq 12); do
            state="$(${lib.getExe' pkgs.tailscale "tailscale"} status --json 2>/dev/null \
              | ${lib.getExe' pkgs.jq "jq"} -r '.BackendState // "Unknown"')"
            if [ "$state" = "Running" ]; then
              exec "$TAILRAY"
            fi
            sleep 5
          done
          echo "Tailscale not logged in after 60s, giving up"
          exit 1
        '')}";
        Restart = "on-failure";
      };
    };
  };
}
