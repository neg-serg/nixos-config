{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  greeterUser = "greeter";
  greeterCache = "/home/${greeterUser}/.cache";
  greeterWallpaper = "${greeterCache}/greeter-wallpaper";

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
}
