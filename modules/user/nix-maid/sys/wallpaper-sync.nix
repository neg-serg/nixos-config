{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  jq = lib.getExe' pkgs.jq "jq";

  # When wl daemon changes its state (new wallpaper), write the path
  # to quickshell-wallpaper-path, which triggers the greeter sync above.
  wlStateSync = pkgs.writeShellScript "wl-state-sync" ''
    set -euo pipefail
    state_file="$HOME/.local/state/wl/state.json"
    notify_file="$HOME/.cache/quickshell-wallpaper-path"
    if [ -f "$state_file" ]; then
      wallpaper_path="$(${jq} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state_file" 2>/dev/null || true)"
      if [ -n "$wallpaper_path" ] && [ -f "$wallpaper_path" ]; then
        echo "$wallpaper_path" > "$notify_file"
      fi
    fi
  '';

  # Retry `wl restore` after the daemon starts — its auto-restore can race
  # the compositor becoming ready (see daemon/src/main.rs).
  wlRestoreRetry = pkgs.writeShellScript "wl-restore-retry" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils # sleep, head
        pkgs.wl # wallpaper daemon
      ]
    }"
    for i in 1 2 3 4 5; do
      wl restore && break
      sleep 1
    done
  '';
  # Watch hyprland events; when a monitor (re)connects, re-apply wallpapers.
  # A lost display signal (cable / DPMS) removes the output and can kill the
  # wl-daemon (see wl-daemon.service); on re-add the daemon's surfaces are
  # stale, so `wl restore` re-issues them from ~/.local/state/wl/state.json.
  # NOTE: bash `< file` can't open a unix socket (ENXIO) — use socat.
  wlMonitorWatch = pkgs.writeShellScript "wl-monitor-watch" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils # sleep, head
        pkgs.socat # socket relay for hyprctl event socket
        pkgs.wl # wallpaper daemon
      ]
    }"
    HYPRCTL="/run/current-system/sw/bin/hyprctl"
    while true; do
      sock="$(ls -d "''${XDG_RUNTIME_DIR:-/run/user/1000}"/hypr/*/.socket2.sock 2>/dev/null | head -1 || true)"
      if [ -z "$sock" ]; then
        sleep 3
        continue
      fi
      # Read events; on monitor loss notify, on (re)connect ensure the daemon
      # is alive (DPMS removal can kill it) and restore the wallpapers.
      socat -u UNIX-CONNECT:"$sock" STDOUT | while read -r line; do
        case "$line" in
          monitoradded*|monitorremoved*)
            mon="''${line#*>>}"
            sleep 1
            case "$line" in
              monitorremoved*)
                "$HYPRCTL" notify -1 6000 "rgb(ff5555)" "Monitor lost: $mon" >/dev/null 2>&1 || true
                ;;
              *)
                "/run/current-system/sw/bin/systemctl" --user is-active wl-daemon.service >/dev/null 2>&1 \
                  || "/run/current-system/sw/bin/systemctl" --user restart wl-daemon.service
                sleep 1
                wl restore || true
                ;;
            esac
            ;;
        esac
      done
      sleep 2
    done
  '';
in
lib.mkIf (cfg.enable or false) {
  # wl-daemon: auto-restart on crash (DPMS output removal kills it)
  systemd.user.services."wl-daemon" = {
    description = "wl wallpaper daemon (Vulkan)";
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    # Cap restarts: systemd >= 254 defaults to unlimited retries, so a
    # persistent start failure (e.g. single-instance lock held elsewhere)
    # spams the journal forever. 10 tries / 60s then the unit goes failed.
    startLimitIntervalSec = 60;
    startLimitBurst = 10;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.wl}-daemon";
      ExecStartPost = "${wlRestoreRetry}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services."wl-monitor-watch" = {
    description = "Re-apply wallpapers when a monitor (re)connects";
    after = [
      "wl-daemon.service"
      "graphical-session-pre.target"
    ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 3;
      ExecStart = "${wlMonitorWatch}";
    };
  };

  systemd.user.paths."wl-greeter-sync" = {
    description = "Watch for wallpaper changes and sync to greeter";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    pathConfig = {
      PathChanged = "%h/.cache/quickshell-wallpaper-path";
      Unit = "wl-greeter-sync.service";
    };
  };

  # Watches wl daemon's state file; on each wallpaper change it
  # writes the current wallpaper path to quickshell-wallpaper-path,
  # which the wl-greeter-sync path unit above picks up.
  systemd.user.services."wl-state-sync" = {
    description = "Extract current wallpaper path from wl state and notify quickshell";
    after = [
      "wl-daemon.service"
      "graphical-session-pre.target"
    ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wlStateSync}";
    };
  };

  systemd.user.paths."wl-state-sync" = {
    description = "Watch wl state.json for wallpaper changes";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    pathConfig = {
      PathChanged = "%h/.local/state/wl/state.json";
      Unit = "wl-state-sync.service";
    };
  };
}
