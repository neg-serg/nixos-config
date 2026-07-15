{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
  webEnabled = config.features.web.enable or false;
  mediaEnabled = config.features.media.audio.apps.enable or false;

  # Helper to generate INI (Flameshot, Aria2 often uses similar key=val)

  # Aria2 Settings
  aria2Settings = {
    dir = "${home}/dw/aria";
    enable-rpc = "true";
    # Store session in XDG data
    save-session = "${home}/.local/share/aria2/session";
    input-file = "${home}/.local/share/aria2/session";
    save-session-interval = "1800";
    # Additional Aria2 defaults often useful
    continue = "true";
  };

  # Aria2 config in key=value format
  aria2ConfText = lib.generators.toKeyValue { } aria2Settings;
in
{
  config = lib.mkMerge [
    (lib.mkIf (webEnabled && config.features.web.tools.enable or false) (
      lib.mkMerge [
        {
          systemd.user.services.aria2 = {
            description = "aria2 download manager";
            partOf = [ "graphical-session.target" ];
            wantedBy = [ "graphical-session.target" ];
            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.aria2} --conf-path=%h/.config/aria2/aria2.conf";
              TimeoutStopSec = "5s";
            };
          };
          # aria2 is installed via cli/file-ops.nix
        }
        (neg.mkHomeFiles {
          ".config/aria2/aria2.conf".text = aria2ConfText;
          # Ensure session file exists (empty init)
          ".local/share/aria2/session".text = "";
        })
      ]
    ))

    (lib.mkIf mediaEnabled {
      systemd.user.services.playerctld = {
        description = "Keep track of media player activity";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe' pkgs.playerctl "playerctld"} daemon"; # Command-line utility and library for controlling media players
          Restart = "on-failure";
          RestartSec = "2";
        };
      };
      environment.systemPackages = [ ]; # command-line tool for controlling media players
    })

  ];
}
