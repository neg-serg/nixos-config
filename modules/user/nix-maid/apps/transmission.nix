{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.torrent;
  filesRoot = ../../../../files;

  transmissionPkg = pkgs.transmission_4; # Fast, easy and free BitTorrent client
  confDirNew = "${config.users.users.neg.home}/.config/transmission-daemon";

  # Define the tracker update script wrapper
  transmissionAddTrackers = pkgs.writeShellScriptBin "transmission-add-trackers" ''
    set -euo pipefail

    # Fetch trackers list directly (no local checkout required)
    TRACKERS_URL="''${TRACKERS_URL:-https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt}"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT

    # Prefer wget, fallback to curl if available
    if command -v wget >/dev/null 2>&1; then
      if ! wget -qO "$tmp" "$TRACKERS_URL"; then
        echo "Failed to fetch trackers list with wget: $TRACKERS_URL" >&2
        exit 1
      fi
    elif command -v curl >/dev/null 2>&1; then
      if ! curl -fsSL "$TRACKERS_URL" -o "$tmp"; then
        echo "Failed to fetch trackers list with curl: $TRACKERS_URL" >&2
        exit 1
      fi
    else
      echo "Neither wget nor curl found; please install one to fetch trackers." >&2
      exit 1
    fi

    # Optional connection args for transmission-remote
    # TRANSMISSION_REMOTE may be a host, host:port or full RPC URL
    # TRANSMISSION_AUTH may be "user:pass" if auth is enabled
    args=()
    if [ -n "''${TRANSMISSION_REMOTE:-}" ]; then
      args+=("$TRANSMISSION_REMOTE")
    fi
    if [ -n "''${TRANSMISSION_AUTH:-}" ]; then
      args+=(--auth "$TRANSMISSION_AUTH")
    fi

    # Probe connection (non-fatal)
    ${lib.getExe' transmissionPkg "transmission-remote"} "''${args[@]}" -si >/dev/null 2>&1 || true

    # Add each tracker to all torrents; ignore duplicates/errors
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in \#*) continue;; esac
      case "$line" in *://*) ;; *) continue;; esac
      ${lib.getExe' transmissionPkg "transmission-remote"} "''${args[@]}" -t all -td "$line" >/dev/null 2>&1 || true
    done < "$tmp"
  '';
in
lib.mkIf (cfg.enable or false) (
  lib.mkMerge [
    {
      environment.systemPackages = [
        # transmissionPkg # Fast, easy and free Bittorrent client
        transmissionAddTrackers # Helper script to add trackers to Transmission
      ];

      # Ensure runtime dirs exist. Maid itself doesn't do "ensure dirs" easily without files,
      # but we can abuse systemd.tmpfiles.rules to create them owned by the user.
      systemd.tmpfiles.rules = [
        "d ${confDirNew}/resume 0700 neg users -"
        "d ${confDirNew}/torrents 0700 neg users -"
        "d ${confDirNew}/blocklists 0700 neg users -"
      ];

      # Replicate user services
      systemd.user.services = {
        # Transmission
        transmission-daemon = {
          description = "transmission service";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${lib.getExe' transmissionPkg "transmission-daemon"} -g ${confDirNew} -f --log-level=error";
            Restart = "on-failure";
            RestartSec = "30";
            ExecReload = "${lib.getExe' pkgs.util-linux "kill"} -s HUP $MAINPID"; # Set of system utilities for Linux
          };
          wantedBy = [ "default.target" ];
        };

        # Trackers update
        transmission-trackers-update = {
          description = "Update Transmission trackers from trackerslist";
          after = [ "transmission-daemon.service" ];
          wants = [ "transmission-daemon.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe transmissionAddTrackers}";
          };
        };
      };

      # Timer for trackers update
      systemd.user.timers.transmission-trackers-update = {
        description = "Timer: update Transmission trackers daily";
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "15m";
          Persistent = true;
          Unit = "transmission-trackers-update.service";
        };
        wantedBy = [ "timers.target" ];
      };
    }

    # Config files linked via maid
    (n.mkHomeFiles {
      ".config/transmission-daemon/settings.json".source = "${filesRoot}/transmission/settings.json";
      ".config/transmission-daemon/bandwidth-groups.json".source =
        "${filesRoot}/transmission/bandwidth-groups.json";
    })
  ]
)
