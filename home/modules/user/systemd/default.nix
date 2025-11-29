{
  pkgs,
  lib,
  config,
  systemdUser,
  ...
}:
with lib;
  lib.mkMerge [
    {
      systemd.user.startServices = true;
    }
    (lib.mkIf (config.features.gui.enable or false)
      (let
        picDirsRunner = pkgs.writeShellApplication {
          name = "pic-dirs-runner";
          text = ''
            set -euo pipefail
            exec pic-dirs-list
          '';
        };
        pyprlandWatchOnce = pkgs.writeShellApplication {
          name = "pyprland-watch-once";
          text = ''
            set -euo pipefail
            if [ -z "$XDG_RUNTIME_DIR" ]; then
              XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
            fi
            dir="$XDG_RUNTIME_DIR/hypr"
            stamp="$dir/.pyprland-watch.stamp"
            now=$(${pkgs.coreutils}/bin/date +%s)
            last=0
            if [ -f "$stamp" ]; then
              last=$(${pkgs.coreutils}/bin/date +%s -r "$stamp" 2>/dev/null || echo 0)
            fi
            if [ $((now - last)) -lt 2 ]; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/mkdir -p "$dir"
            ${pkgs.coreutils}/bin/touch "$stamp"

            # Determine the newest Hyprland instance signature present
            newest=""
            if [ -d "$dir" ]; then
              newest="$(${pkgs.coreutils}/bin/ls -td "$dir"/* 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.coreutils}/bin/xargs -r basename || true)"
            fi
            if [ -z "$newest" ]; then
              # No hypr instance detected; nothing to do
              exit 0
            fi

            # Read current pyprland MainPID and its bound signature, if running
            mainpid="$(${pkgs.systemd}/bin/systemctl --user show -p MainPID --value pyprland.service 2>/dev/null || echo 0)"
            current_sig=""
            if [ -n "$mainpid" ] && [ "$mainpid" != "0" ] && [ -r "/proc/$mainpid/environ" ]; then
              current_sig="$(${pkgs.coreutils}/bin/tr '\0' '\n' < "/proc/$mainpid/environ" | ${pkgs.gnugrep}/bin/grep -m1 '^HYPRLAND_INSTANCE_SIGNATURE=' | ${pkgs.coreutils}/bin/cut -d= -f2 || true)"
            fi

            if [ "$current_sig" = "$newest" ]; then
              # Already bound to the newest instance; skip restart
              exit 0
            fi

            # Restart (or start) pyprland to bind to the newest instance; ignore errors
            ${pkgs.systemd}/bin/systemctl --user restart pyprland.service >/dev/null 2>&1 || true
          '';
        };
      in {
        # Quickshell session (Qt-bound, skip in dev-speed) + other services
        systemd.user.services = lib.mkMerge [
          (lib.mkIf ((config.features.gui.qt.enable or false) && (config.features.gui.quickshell.enable or false) && (! (config.features.devSpeed.enable or false))) {
            quickshell = lib.mkMerge [
              {
                Unit.Description = "Quickshell Wayland shell";
                Service = {
                  ExecStart = let
                    wrapped = config.neg.quickshell.wrapperPackage or null;
                    pkg =
                      if wrapped != null
                      then wrapped
                      else pkgs.quickshell;
                    exe = lib.getExe' pkg "qs";
                  in
                    exe;
                  Environment = [
                    "RUST_LOG=info,quickshell.dbus.properties=error"
                    "QSG_RENDER_LOOP=basic" # prefer basic loop to reduce wakeups
                  ];
                  # Quickshell 0.2+ removed SIGHUP reload support; rely on restarts for updates.
                  Restart = "on-failure";
                  RestartSec = "1";
                  Slice = "background-graphical.slice";
                  TimeoutStopSec = "5s";
                  RuntimeDirectory = "quickshell";
                  RuntimeDirectoryMode = "0700";
                };
                Unit.PartOf = ["graphical-session.target"];
              }
              (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
            ];
          })
          {
            # Pic dirs notifier
            "pic-dirs" = lib.mkMerge [
              {
                Unit = {
                  Description = "Pic dirs notification";
                  StartLimitIntervalSec = "0";
                };
                Service = {
                  ExecStart = let exe = lib.getExe' picDirsRunner "pic-dirs-runner"; in "${exe}";
                  PassEnvironment = ["XDG_PICTURES_DIR" "XDG_DATA_HOME"];
                  Restart = "on-failure";
                  RestartSec = "1";
                };
              }
              (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
            ];

            # Pyprland daemon (Hyprland helper)
            # Use a wrapper that resolves the current HYPRLAND_INSTANCE_SIGNATURE
            # at start time so restarts after Hyprland crashes/restarts are stable.
            pyprland = lib.mkMerge [
              {
                Unit = {
                  Description = "Pyprland daemon for Hyprland";
                  StartLimitIntervalSec = "0";
                  # Start only when a Hyprland instance socket exists
                  ConditionPathExistsGlob = [
                    "%t/hypr/*/.socket.sock"
                    "%t/hypr/*/.socket2.sock"
                  ];
                };
                Service = {
                  Type = "simple";
                  # Wrapper ensures we always target the newest Hypr instance
                  ExecStart = "${config.home.homeDirectory}/.local/bin/pypr-run";
                  Restart = "always";
                  RestartSec = "1s";
                  Slice = "background-graphical.slice";
                  TimeoutStopSec = "5s";
                  # Ensure common env from the user manager is visible
                  PassEnvironment = [
                    "XDG_RUNTIME_DIR"
                    "WAYLAND_DISPLAY"
                    "HYPRLAND_INSTANCE_SIGNATURE"
                  ];
                };
                Unit.PartOf = ["graphical-session.target"];
              }
              (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
            ];

            # OpenRGB daemon
            openrgb = lib.mkMerge [
              {
                Unit = {
                  Description = "OpenRGB daemon with profile";
                  PartOf = ["graphical-session.target"];
                  StartLimitBurst = "8";
                };
                Service = {
                  ExecStart = let
                    exe = lib.getExe pkgs.openrgb;
                    args = ["--server" "-p" "neg.orp"];
                  in "${exe} ${lib.escapeShellArgs args}";
                  RestartSec = "30";
                };
              }
              (systemdUser.mkUnitFromPresets {
                presets = ["dbusSocket" "graphical"];
              })
            ];

            # Watch Hyprland socket and restart pyprland on new instance
            pyprland-watch = lib.mkMerge [
              {
                Unit = {
                  Description = "Restart pyprland on Hyprland instance change";
                  # Disable start-rate limiting; path may trigger bursts on Hypr restarts
                  StartLimitIntervalSec = "0";
                };
                Service = {
                  Type = "oneshot";
                  ExecStart = lib.getExe' pyprlandWatchOnce "pyprland-watch-once";
                  SuccessExitStatus = ["0"]; # explicit for clarity
                };
              }
              (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
            ];
          }
        ];
        # Path unit triggers the oneshot service whenever a new hypr socket appears
        systemd.user.paths.pyprland-watch = lib.mkMerge [
          {
            Unit = {
              Description = "Watch Hyprland socket path";
              # Also disable rate limiting on the path unit itself
              StartLimitIntervalSec = "0";
            };
            Path = {
              # Trigger when hypr creates sockets (avoid noisy PathChanged)
              PathExistsGlob = [
                "%t/hypr/*/.socket.sock"
                "%t/hypr/*/.socket2.sock"
              ];
              # Disable path trigger rate limiting (systemd v258)
              TriggerLimitIntervalSec = "0";
              TriggerLimitBurst = 0;
              Unit = "pyprland-watch.service";
            };
          }
          (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
        ];
      }))
  ]
