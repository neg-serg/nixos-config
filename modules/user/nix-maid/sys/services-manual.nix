{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  guiEnabled = config.features.gui.enable or false;
  webEnabled = config.features.web.enable or false;
  mediaEnabled = config.features.media.audio.apps.enable or false;

  # Helper to generate INI (Flameshot, Aria2 often uses similar key=val)
  toINI = lib.generators.toINI {
    mkKeyValue =
      key: value:
      let
        v =
          if builtins.isString value && lib.hasPrefix "#" value then
            "\"${value}\""
          else if builtins.isBool value then
            if value then "true" else "false"
          else
            toString value;
      in
      "${key}=${v}";
  };

  # Aria2 Settings
  aria2Settings = {
    dir = "${config.users.users.neg.home}/dw/aria";
    enable-rpc = "true";
    # Store session in XDG data
    save-session = "${config.users.users.neg.home}/.local/share/aria2/session";
    input-file = "${config.users.users.neg.home}/.local/share/aria2/session";
    save-session-interval = "1800";
    # Additional Aria2 defaults often useful
    continue = "true";
  };

  # Aria2 config text generator (key=value)
  aria2ConfText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "${k}=${toString v}") aria2Settings
  );
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
        (n.mkHomeFiles {
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

    (lib.mkIf
      (
        (config.features.dev.openxr.enable or false)
        && (config.features.dev.openxr.runtime.service.enable or false)
      )
      (
        lib.mkMerge [
          {
            systemd.user.services.monado-service = {
              description = "Monado OpenXR Runtime Service";
              wantedBy = [ "graphical-session.target" ];
              serviceConfig = {
                ExecStart = "${lib.getExe' pkgs.monado "monado-service"}"; # Open source XR runtime
              };
            };
          }
          (n.mkHomeFiles {
            ".config/monado/config.example.jsonc".text = ''
              // Monado user configuration (example).
              // Rename to config.json to activate.
              {
                "settings": { "log": { "level": "info" } }
              }
            '';
            ".config/monado/basalt.config.example.jsonc".text = ''
              // Basalt + Monado example.
              {
                "drivers": {
                  "basalt": {
                    "enable": true,
                    "cams": [ { "name": "/dev/video0", "resolution": [1280, 720], "fps": 60 } ],
                    "imu": "icm20602",
                    "calibration": {
                      "intrinsics": "${config.users.users.neg.home}/.config/monado/calib/intrinsics.yaml",
                      "cam_to_imu": "${config.users.users.neg.home}/.config/monado/calib/cam_to_imu.yaml"
                    }
                  }
                }
              }
            '';
          })
        ]
      )
    )
  ];
}
