{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # OpenRGB daemon — starts the SDK server so clients (profile service, GUI) can connect.
    # The profile is NOT loaded on daemon startup (it may not exist yet); the
    # openrgb-profile oneshot applies the saved "neg" profile after the server is ready.
    openrgb = systemdUser.mkUserService {
      presets = [
        "graphicalSession"
        "restartOnFailure"
      ];
      description = "OpenRGB SDK server";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.openrgb} --server"; # SDK server for RGB control
        RestartSec = "30";
      };
    };

    # OpenRGB profile — applies saved "neg" profile after daemon starts.
    # If no profile has been saved yet (first run), this will produce a "Profile
    # failed to load" message but does NOT fail the unit — status=0 is expected.
    # Save a profile named "neg" via the GUI or CLI to make this effective.
    # Both the server and this applier SEGV if they enumerate i2c devices
    # concurrently at session start, so wait for the server to settle, then
    # retry a few times before giving up.
    #
    # Type=exec + the settle delay inside the command, NOT `Type=oneshot` +
    # `ExecStartPre=sleep 10`: this unit is WantedBy graphical-session.target, and
    # systemd orders such units Before= the target, so a oneshot makes the whole
    # session transaction wait for the sleep. Journal 2026-09-19: "Starting Apply
    # OpenRGB neg profile" 18:25:52.689 → "Reached target Hyprland compositor
    # session" 18:26:03.73 — hypridle, vicinae, kanata, the portals and the bar were
    # all dispatched 10.4 s after the password, for a delay nothing on screen asked
    # for. Type=exec marks the unit started as soon as the process is spawned; the
    # profile still lands ~10 s in, just no longer on the session's critical path.
    openrgb-profile = systemdUser.mkUserService {
      presets = [
        "graphicalWanted"
        "restartOnFailure"
      ];
      description = "Apply OpenRGB neg profile";
      after = [ "openrgb.service" ];
      requires = [ "openrgb.service" ];
      # startLimit* are unit-level options: expressed through unitConfig so the
      # rest of the unit still goes through the shared constructor.
      unitConfig = {
        StartLimitIntervalSec = 120;
        StartLimitBurst = 6;
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.runtimeShell} -c 'sleep 10; exec ${lib.getExe pkgs.openrgb} -p %h/.config/openrgb/neg.orp'";
        RemainAfterExit = false;
        # 10 s: the delay this unit has always used.
        RestartSec = 10;
      };
    };
  };
}
