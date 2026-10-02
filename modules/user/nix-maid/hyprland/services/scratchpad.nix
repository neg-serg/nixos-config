{
  lib,
  pkgs,
  scratchpadGeometry,
  ...
}:
{
  systemdServices = {
    # Hyprscratch daemon (scratchpad manager)
    # bindsTo ensures hyprscratch stops when the session target stops.
    # After hyprland reload/suspend the IPC socket changes, so
    # hyprland.lua restarts this service on hyprland.start (below).
    hyprscratch = {
      description = "Hyprscratch - improved scratchpad functionality for Hyprland";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.hyprscratch} init spotless";
        Restart = "always";
        RestartSec = "2";
      };
    };

    # Scratchpad geometry persistence: saves window geometry on move/resize
    # (via event stream + poll) and reapplies it when a special workspace shows.
    # Exits when the IPC socket dies; Restart=always brings it back.
    scratchpad-geometry = {
      description = "Persist Hyprland scratchpad geometry across show/hide cycles";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe scratchpadGeometry}";
        Restart = "always";
        RestartSec = "2";
      };
    };
  };
}
