{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  jq = lib.getExe' pkgs.jq "jq";
  systemdUser = config.lib.neg.systemdUser;
  mainHome = config.lib.neg.homeDir;

  # The greeter session runs as its own user and cannot read the main user's
  # home, so the wallpaper is copied into the greeter's cache. Keep these two
  # paths in step with modules/user/session/greetd.nix (greeterCache /
  # greeterWallpaperFallback).
  greeterCache = "/home/greeter/.cache";
  greeterWallpaperFallback = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";

  # When wl daemon changes its state (new wallpaper), write the path to
  # quickshell-wallpaper-path (triggers the greeter sync above) and keep a
  # last-good copy. last-good is the fallback wl-wallpaper-resolve.sh falls back to
  # when both wl sources name a file that is gone — wallpapers get deleted, renamed
  # and moved, and on 2026-09-19 exactly that left the desktop with no wallpaper at
  # all (wl restore exits 0 without painting anything) while the login screen fell
  # back to a random image.
  wlStateSync = pkgs.writeShellScript "wl-state-sync" ''
    set -euo pipefail
    state_file="$HOME/.local/state/wl/state.json"
    notify_file="$HOME/.cache/quickshell-wallpaper-path"
    if [ -f "$state_file" ]; then
      wallpaper_path="$(${jq} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state_file" 2>/dev/null || true)"
      if [ -n "$wallpaper_path" ] && [ -f "$wallpaper_path" ]; then
        echo "$wallpaper_path" > "$notify_file"
        echo "$wallpaper_path" > "$HOME/.local/state/wl/last-good"
      fi
    fi
  '';

  # Copy the current wallpaper into the greeter cache. wl only refreshes that
  # copy for `wl random` (client/src/random.rs:greeter_sync) and
  # system.activationScripts.greetdWallpaper only on a rebuild, so without this
  # service the login screen keeps the wallpaper of the last rebuild. Same
  # source order as greetd/wallpaper.sh: live notify file, daemon state, any
  # image from the collection, then the activation fallback.
  wlGreeterSync = pkgs.writeShellScript "wl-greeter-sync" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils # cat, head, tr, chmod, chgrp, mv, sort
        pkgs.findutils # find
      ]
    }"

    dst="${greeterCache}/greeter-wallpaper"
    src=""

    # 1) Live path: wl writes it on every img/random/restore.
    notify="$HOME/.cache/quickshell-wallpaper-path"
    if [ -f "$notify" ]; then
      candidate="$(head -n1 "$notify" | tr -d '[:space:]')"
      if [ -n "$candidate" ] && [ -r "$candidate" ]; then
        src="$candidate"
      fi
    fi

    # 2) Daemon state — the only source on a fresh boot, before any notify file.
    state="$HOME/.local/state/wl/state.json"
    if [ -z "$src" ] && [ -f "$state" ]; then
      candidate="$(${jq} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state" 2>/dev/null || true)"
      if [ -n "$candidate" ] && [ -r "$candidate" ]; then
        src="$candidate"
      fi
    fi

    # 3) Any wallpaper from the collection, 4) the activation fallback.
    if [ -z "$src" ]; then
      src="$(find "$HOME/pic/wl" -maxdepth 1 -type f 2>/dev/null | sort -R | head -n1 || true)"
    fi
    if [ -z "$src" ] || [ ! -f "$src" ]; then
      src="${greeterWallpaperFallback}"
    fi
    [ -f "$src" ] || exit 0

    # Copy through a temp file in the target directory and rename: after a
    # rebuild the destination is owned by the greeter user, and a user unit
    # cannot chown (install -o needs root) — but the directory is group
    # writable, so only a rename is needed.
    tmp="$dst.$$"
    cat "$src" > "$tmp"
    chmod 0644 "$tmp"
    chgrp greeter "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$dst"
  '';

  # Restore the session wallpaper right after the daemon starts. Two jobs:
  #
  #   * `wl restore` — the daemon's own auto-restore can race the compositor
  #     becoming ready (see daemon/src/main.rs), hence the retries;
  #   * a validity check on wl's state, because the image it names may be gone
  #     (deleted, renamed or moved between sessions). `wl restore` exits 0 having
  #     painted nothing in that case, so on 2026-09-19 the desktop came up black
  #     while the login screen — which validates its candidate — showed a random
  #     image. When the state is stale, whatever wl-wallpaper-resolve.sh considers
  #     current is applied and recorded as last-good.

  wlRestoreRetry = pkgs.writeShellScript "wl-restore-retry" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils # sleep, head, printf
        pkgs.findutils # find (wl-wallpaper-resolve.sh)
        pkgs.gnused # sed (wl-wallpaper-resolve.sh)
        pkgs.jq # state.json, here and in the resolver
        pkgs.wl # wallpaper daemon
      ]
    }"
    state_file="$HOME/.local/state/wl/state.json"
    current="$(${jq} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state_file" 2> /dev/null || true)"

    if [ -n "$current" ] && [ -r "$current" ]; then
      for i in 1 2 3 4 5; do
        wl restore && exit 0
        sleep 1
      done
      exit 0
    fi

    # The state names a file that is not there: restoring it would leave the
    # screen empty. Ask the resolver (the same script the login layer uses) what
    # is actually on disk and apply that.
    candidate="$(/etc/quickshell/scripts/wl-wallpaper-resolve.sh 2> /dev/null || true)"
    if [ -z "$candidate" ]; then
      echo "wl-restore-retry: no wallpaper to restore (state names '$current')" >&2
      exit 0
    fi
    echo "wl-restore-retry: state names a missing wallpaper ('$current'); applying $candidate" >&2
    for i in 1 2 3 4 5; do
      if wl img "$candidate"; then
        printf '%s\n' "$candidate" > "$HOME/.local/state/wl/last-good"
        exit 0
      fi
      sleep 1
    done
  '';

  # Watch hyprland events; when a monitor (re)connects, re-apply wallpapers.
  # A lost display signal (cable / DPMS) removes the output and can kill the
  # wl-daemon (see wl-daemon.service); on re-add the daemon's surfaces are
  # stale, so `wl restore` re-issues them from ~/.local/state/wl/state.json.
  # NOTE: bash `< file` can't open a unix socket (ENXIO) — use socat.
  wlMonitorWatch = pkgs.writeShellScript "wl-monitor-watch" (
    builtins.readFile (
      pkgs.replaceVars ./wallpaper-sync/wl-monitor-watch.sh {
        binPath = lib.makeBinPath [
          pkgs.coreutils # sleep, head
          pkgs.socat # socket relay for hyprctl event socket
          pkgs.wl # wallpaper daemon
        ];
      }
    )
  );
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

  # The path unit above only names its trigger unit: the service itself never
  # existed, so the path unit refused to start ("unit wl-greeter-sync.service to
  # trigger not loaded") and the greeter wallpaper was never refreshed between
  # rebuilds. Also runs once per session so a dead path unit is not fatal.
  systemd.user.services."wl-greeter-sync" = systemdUser.mkUserService {
    description = "Copy the current wallpaper into the greeter cache";
    after = [
      "wl-daemon.service"
      "graphical-session-pre.target"
    ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wlGreeterSync}";
    };
    # wl rewrites its state in bursts while outputs settle (5+ triggers in a few
    # seconds); the default limit of 5 starts per 10 s would fail such a burst.
    unitConfig = {
      StartLimitIntervalSec = 0;
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
    # wl rewrites state.json in bursts while outputs settle (5+ writes within a
    # few seconds). The default start rate limit refused the oneshot then
    # which kills the path unit with 'unit-start-limit-hit' — after that the
    # greeter chain stayed dead for the rest of the session.
    unitConfig = {
      StartLimitIntervalSec = 0;
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
