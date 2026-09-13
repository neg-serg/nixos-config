{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.torrent;
  filesRoot = config.lib.neg.path "files";

  transmissionPkg = pkgs.transmission_4; # Fast, easy and free BitTorrent client
  confDirNew = "${config.users.users.neg.home}/.config/transmission-daemon";

  # Define the tracker update script wrapper
  transmissionAddTrackers = pkgs.writeShellScriptBin "transmission-add-trackers" (
    builtins.readFile (
      pkgs.replaceVars ./transmission/add-trackers.sh {
        curl = lib.getExe pkgs.curl;
        transmissionRemote = lib.getExe' transmissionPkg "transmission-remote";
      }
    )
  );
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
    (neg.mkHomeFiles {
      ".config/transmission-daemon/settings.json".source = "${filesRoot}/transmission/settings.json";
      ".config/transmission-daemon/bandwidth-groups.json".source =
        "${filesRoot}/transmission/bandwidth-groups.json";
    })
  ]
)
