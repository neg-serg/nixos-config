{
  pkgs,
  lib,
  config,
  systemdUser,
  ...
}: let
  transmissionPkg = pkgs.transmission_4;
  confDirNew = "${config.xdg.configHome}/transmission-daemon";
in
  lib.mkIf config.features.torrent.enable (lib.mkMerge [
    {
      # Link selected Transmission config files from repo; runtime subdirs remain local
      xdg.configFile."transmission-daemon/settings.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/misc/transmission-daemon/conf/settings.json";
        recursive = false;
        force = true;
      };
      xdg.configFile."transmission-daemon/bandwidth-groups.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${config.neg.hmConfigRoot}/modules/misc/transmission-daemon/conf/bandwidth-groups.json";
        recursive = false;
        force = true;
      };

      # Ensure runtime subdirectories exist even if the config dir is a symlink
      # to an external location. This avoids "resume: No such file or directory"
      # on first start after activation.
      home.activation.ensureTransmissionDirs = config.lib.neg.mkEnsureDirsAfterWrite [
        "${confDirNew}/resume"
        "${confDirNew}/torrents"
        "${confDirNew}/blocklists"
      ];

      # Core torrent tools (migration helpers removed)
      home.packages = config.lib.neg.pkgsList [
        transmissionPkg # Transmission 4 BitTorrent client
        pkgs.bitmagnet # BitTorrent DHT crawler/search (CLI)
        pkgs.neg.bt_migrate # migrate legacy torrent data/config
        pkgs.rustmission # transmission-remote replacement (Rust CLI)
        pkgs.curl # required by trackers update helper
        pkgs.jq # required by trackers update helper
        pkgs.jackett # torrent indexer/aggregator with Torznab/JSON API
      ];

      # No additional activation cleanup for Transmission config; rely on XDG helpers.
    }
    {
      # Jackett service (systemd user)
      systemd.user.services."jackett" = lib.mkMerge [
        {
          Unit = {
            Description = "Jackett (torrent indexer)";
            ConditionPathExists = lib.getExe pkgs.jackett;
            StartLimitBurst = "8";
          };
          Service = {
            Type = "simple";
            ExecStart = lib.getExe pkgs.jackett;
            Restart = "on-failure";
            RestartSec = "10s";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline" "defaultWanted"];})
      ];
    }
    {
      # Transmission daemon service (systemd user)
      systemd.user.services."transmission-daemon" = lib.mkMerge [
        {
          Unit = {
            Description = "transmission service";
            ConditionPathExists = "${lib.getExe' transmissionPkg "transmission-daemon"}";
            StartLimitBurst = "8";
          };
          Service = {
            Type = "simple";
            ExecStart = let
              exe = lib.getExe' transmissionPkg "transmission-daemon";
              args = ["-g" confDirNew "-f" "--log-level=error"];
            in "${exe} ${lib.escapeShellArgs args}";
            Restart = "on-failure";
            RestartSec = "30";
            ExecReload = let kill = lib.getExe' pkgs.util-linux "kill"; in "${kill} -s HUP $MAINPID";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["net" "defaultWanted"];})
      ];
    }
    # Local bin wrapper installed to ~/.local/bin (avoid config.* to prevent recursion)
    (let
      mkLocalBin = import ../../../packages/lib/local-bin.nix {inherit lib;};
    in
      mkLocalBin "transmission-add-trackers" ''        #!/usr/bin/env bash
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
            transmission-remote "''${args[@]}" -si >/dev/null 2>&1 || true

            # Add each tracker to all torrents; ignore duplicates/errors
            while IFS= read -r line; do
              [ -z "$line" ] && continue
              case "$line" in \#*) continue;; esac
              case "$line" in *://*) ;; *) continue;; esac
              transmission-remote "''${args[@]}" -t all -td "$line" >/dev/null 2>&1 || true
            done < "$tmp"
      '')

    {
      # Periodic job to add/update public trackers on existing torrents
      # Run manually: transmission-trackers-update (service) or timer start
      #   systemctl --user start transmission-trackers-update.service
      #   systemctl --user start transmission-trackers-update.timer

      # One-shot service that runs the wrapper
      systemd.user.services."transmission-trackers-update" = lib.mkMerge [
        {
          Unit = {
            Description = "Update Transmission trackers from trackerslist";
            After = ["transmission-daemon.service"];
            Wants = ["transmission-daemon.service"];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${config.home.homeDirectory}/.local/bin/transmission-add-trackers";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline"];})
      ];

      # Daily timer with persistence (runs missed executions on boot)
      systemd.user.timers."transmission-trackers-update" = lib.mkMerge [
        {
          Unit = {Description = "Timer: update Transmission trackers daily";};
          Timer = {
            OnCalendar = "daily";
            RandomizedDelaySec = "15m";
            Persistent = true;
            Unit = "transmission-trackers-update.service";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
    }
    # Soft migration warning removed; defaults and docs are sufficient
  ])
