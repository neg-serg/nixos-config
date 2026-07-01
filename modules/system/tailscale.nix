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

  tailrayPkg = inputs.tailray.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Wrapper that waits for tailscale to be logged in before starting tailray
  tailrayWrapped = pkgs.writeShellScript "tailray-wrapped" ''
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
  '';
in
{
  config = lib.mkIf enabled {
    services.tailscale.enable = true;

    environment.systemPackages = [
      tailrayPkg # GUI client for Tailscale
    ];

    # Override start ordering for Tailray systemd user service
    # so it waits for graphical session (tray icon requirement)
    systemd.user.services.tailray = {
      wantedBy = [ "graphical-session.target" ];
      after = lib.mkForce [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe' tailrayWrapped "tailray-wrapped"}";
        Restart = "on-failure";
      };
    };
  };
}
