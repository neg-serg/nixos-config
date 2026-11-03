{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.lib.neg.enabled "web") {
  # The hooks server is a Rust binary now (packages/local-bin-tools): it needs no
  # interpreter and prints one log line per request instead of five.
  systemd.user.services.surfingkeys-server = config.lib.neg.systemdUser.mkUserService {
    presets = [
      "graphicalSession"
      "restartOnFailure"
    ];
    description = "HTTP server for Surfingkeys configuration (focus/close/addressbar/proxy)";
    # The preset carries wantedBy+partOf; ordering (After=/Wants=) stays explicit.
    after = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.neg.local-bin-tools "surfingkeys-server"}";
      Environment = "PATH=${pkgs.hyprland}/bin:$PATH";
      RestartSec = "5";
      Slice = "background.slice";
    };
  };

  systemd.user.services.surfingkeys-extension-patch = {
    description = "Patch SurfingKeys extension to auto-load config from local server";
    # The script logs every patch through `logger` (util-linux), which is not
    # part of systemd's default service PATH — without it the unit died with
    # status 127 on every login since at least 2026-09-19.
    path = [ pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe' pkgs.neg.local-bin-system "surfingkeys-extension-patch";
    };
    after = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
  };

  # Vivaldi updates the force-installed extension in place and mid-session
  # (1.19.3 landed at 21:17 while the session was already running), while the
  # oneshot above only runs at login. Without this watch a new version stays
  # unpatched — and an unpatched SurfingKeys can register the server's error
  # body as its settings userScript (see the script header).
  systemd.user.paths.surfingkeys-extension-watch = {
    description = "Re-patch SurfingKeys when Vivaldi updates the extension";
    wantedBy = [ "graphical-session.target" ];
    pathConfig = {
      PathChanged = "%h/.config/vivaldi/Default/Extensions/gfbliohnnapiefjpjlpjnehglfpaknnc";
      Unit = "surfingkeys-extension-patch.service";
    };
  };
}
