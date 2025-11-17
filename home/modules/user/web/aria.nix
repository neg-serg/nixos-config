{
  config,
  lib,
  pkgs,
  xdg,
  systemdUser,
  ...
}: let
  inherit (lib) getExe';
  inherit (config.xdg) configHome dataHome;
  aria2Bin = getExe' pkgs.aria2 "aria2c";
  sessionFile = "${dataHome}/aria2/session";
in {
  options.features.web.aria2.service.enable =
    (lib.mkEnableOption "run aria2 as a user systemd service (graphical preset)") // {default = false;};

  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) (lib.mkMerge [
    {
      # Minimal, robust aria2 configuration through Home Manager
      programs.aria2 = {
        enable = true;
        settings = {
          # Download destination under XDG paths
          dir = "${config.xdg.userDirs.download}/aria";
          # Enable RPC for external clients/UI
          enable-rpc = true;
          # Session file kept in XDG data (persist resume state)
          save-session = sessionFile;
          input-file = sessionFile;
          save-session-interval = 1800;
        };
      };
    }
    # Ensure the session file exists under XDG data (no activation DAG noise)
    (xdg.mkXdgDataText "aria2/session" "")
    # Optional user service (behind a flag)
    (lib.mkIf (config.features.web.aria2.service.enable or false) {
      systemd.user.services.aria2 = lib.mkMerge [
        {
          Unit = {
            Description = "aria2 download manager";
            PartOf = ["graphical-session.target"];
          };
          Service = {
            ExecStart = let
              exe = aria2Bin;
              args = ["--conf-path=${configHome}/aria2/aria2.conf"];
            in "${exe} ${lib.escapeShellArgs args}";
            TimeoutStopSec = "5s";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
      ];
    })
  ]);
}
