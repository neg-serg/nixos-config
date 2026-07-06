{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  jq = lib.getExe' pkgs.jq "jq";
  greeterUser = "greeter";
  greeterCache = "/home/${greeterUser}/.cache";
  greeterWallpaper = "${greeterCache}/greeter-wallpaper";

  # When quickshell-wallpaper-path changes, copy to greeter cache.
  wlGreeterSync = pkgs.writeShellScript "wl-greeter-sync" ''
    set -euo pipefail
    notify_file="$HOME/.cache/quickshell-wallpaper-path"
    if [ -f "$notify_file" ]; then
      wallpaper_path="$(head -1 "$notify_file" 2>/dev/null || true)"
      if [ -n "$wallpaper_path" ] && [ -f "$wallpaper_path" ]; then
        install -Dm644 "$wallpaper_path" "${greeterWallpaper}" 2>/dev/null || true
      fi
    fi
  '';

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
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services."wl-greeter-sync" = {
    description = "Sync current wallpaper to greeter cache for smooth transitions";
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wlGreeterSync}";
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
    after = [ "graphical-session-pre.target" ];
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
