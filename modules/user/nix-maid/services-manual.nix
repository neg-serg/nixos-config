{
  config,
  lib,
  pkgs,
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  webEnabled = config.features.web.enable or false;
  mediaEnabled = config.features.media.audio.apps.enable or false;

  # Helper to generate INI (Flameshot, Aria2 often uses similar key=val)
  toINI = lib.generators.toINI {
    mkKeyValue = key: value: let
      v =
        if builtins.isString value && lib.hasPrefix "#" value
        then "\"${value}\""
        else if builtins.isBool value
        then
          if value
          then "true"
          else "false"
        else toString value;
    in "${key}=${v}";
  };

  # Flameshot Settings
  flameshotSettings = {
    General = {
      showStartupLaunchMessage = false;
      contrastUiColor = "#005fd7";
      disabledTrayIcon = true;
      drawColor = "#ff1ad4";
      drawThickness = 3;
      savePath = "${config.users.users.neg.home}/dw";
      savePathFixed = false;
      uiColor = "#005faf";
    };
    Shortcuts = {
      TYPE_ARROW = "A";
      TYPE_CIRCLE = "C";
      TYPE_COMMIT_CURRENT_TOOL = "Ctrl+Return";
      TYPE_COPY = "Ctrl+C";
      TYPE_DELETE_CURRENT_TOOL = "Del";
      TYPE_DRAWER = "D";
      TYPE_EXIT = "Ctrl+Q";
      TYPE_IMAGEUPLOADER = "Return";
      TYPE_MARKER = "M";
      TYPE_MOVESELECTION = "Ctrl+M";
      TYPE_MOVE_DOWN = "Down";
      TYPE_MOVE_LEFT = "Left";
      TYPE_MOVE_RIGHT = "Right";
      TYPE_MOVE_UP = "Up";
      TYPE_OPEN_APP = "Ctrl+O";
      TYPE_PENCIL = "P";
      TYPE_PIXELATE = "B";
      TYPE_RECTANGLE = "R";
      TYPE_REDO = "Ctrl+Shift+Z";
      TYPE_RESIZE_DOWN = "Shift+Down";
      TYPE_RESIZE_LEFT = "Shift+Left";
      TYPE_RESIZE_RIGHT = "Shift+Right";
      TYPE_RESIZE_UP = "Shift+Up";
      TYPE_SAVE = "Ctrl+S";
      TYPE_SELECTION = "S";
      TYPE_SELECT_ALL = "Ctrl+A";
      TYPE_TEXT = "T";
      TYPE_TOGGLE_PANEL = "Space";
      TYPE_UNDO = "Ctrl+Z";
    };
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
  aria2ConfText = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${toString v}") aria2Settings);
in {
  # ============================================================================
  # FLAMESHOT
  # ============================================================================
  config = lib.mkMerge [
    (lib.mkIf guiEnabled {
      users.users.neg.maid.file.home = {
        ".config/flameshot/flameshot.ini".text = toINI flameshotSettings;
      };

      systemd.user.services.flameshot = {
        description = "Flameshot screenshot tool";
        after = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        environment = {
          QT_QPA_PLATFORM = "wayland";
        };
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.flameshot}";
          Restart = "on-failure";
          RestartSec = "2";
        };
      };

      environment.systemPackages = [pkgs.flameshot];
    })

    # ============================================================================
    # ARIA2
    # ============================================================================
    (lib.mkIf (webEnabled && config.features.web.tools.enable or false) {
      users.users.neg.maid.file.home = {
        ".config/aria2/aria2.conf".text = aria2ConfText;
        # Ensure session file exists (empty init)
        ".local/share/aria2/session".text = "";
      };

      systemd.user.services.aria2 = {
        description = "aria2 download manager";
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.aria2} --conf-path=%h/.config/aria2/aria2.conf";
          TimeoutStopSec = "5s";
        };
      };

      environment.systemPackages = [pkgs.aria2];
    })

    # ============================================================================
    # PLAYERCTLD
    # ============================================================================
    (lib.mkIf mediaEnabled {
      systemd.user.services.playerctld = {
        description = "Keep track of media player activity";
        wantedBy = ["default.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe' pkgs.playerctl "playerctld"} daemon";
          Restart = "on-failure";
          RestartSec = "2";
        };
      };
      environment.systemPackages = [pkgs.playerctl];
    })

    # ============================================================================
    # VDIRSYNCER
    # ============================================================================
    (lib.mkIf (config.features.mail.enable && config.features.mail.vdirsyncer.enable) {
      systemd.user.services.vdirsyncer = {
        description = "Vdirsyncer synchronization service";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${lib.getExe pkgs.vdirsyncer} metasync";
          ExecStart = "${lib.getExe pkgs.vdirsyncer} sync";
        };
      };
      environment.systemPackages = [pkgs.vdirsyncer];
    })

    # ============================================================================
    # NEKORAY
    # ============================================================================
    (lib.mkIf (config.features.gui.enable or false) {
      systemd.user.services.nekoray = {
        description = "Nekoray Proxy Client";
        after = ["graphical-session-pre.target"];
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          # Binary name might be different depending on package version, but 'nekoray' is standard
          ExecStart = "${lib.getExe pkgs.throne}";
          Restart = "on-failure";
        };
      };
      environment.systemPackages = [pkgs.throne];
    })

    # ============================================================================
    # NEXTCLOUD-CLI
    # ============================================================================
    # Note: This is a partial migration of the custom Nextcloud CLI service.
    # We are porting the 'systemd.user.services.nextcloud-sync' logic.
    # The original module had options for remoteUrl, userName, etc.
    # We will hardcode/adapt defaults for 'neg' user here or use the existing secrets.

    (lib.mkIf (config.features.gui.enable or false) {
      systemd.user.services.nextcloud-sync = {
        description = "Nextcloud CLI sync";
        # Defaults adapted from previous HM module
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = "/run/services/nextcloud-cli.env";
          # We need to ensure secrets are available.
          # The previous module looked for /run/user/1000/secrets/nextcloud-cli.env
          # We should probably stick to that or use the new sops location.

          ExecStart = let
            nextcloudcmd = lib.getExe' pkgs.nextcloud-client "nextcloudcmd";
            syncScript = pkgs.writeShellScript "nextcloud-sync" ''
              set -euo pipefail
              # Normalized URL logic matching original
              normalize_url() {
                case "$1" in
                  *"/remote.php/"*) printf '%s\n' "''${1%%/remote.php/*}" ;;
                  *) printf '%s\n' "$1" ;;
                esac
              }

              # Defaults
              user_default="neg"
              url_default="https://telfir"

              # Secret loading (expecting standard variables from sops/env)
              # We read from the sops-decrypted file if available, or rely on EnvFile
              if [ -f /run/user/1000/secrets/nextcloud-cli.env ]; then
                  source /run/user/1000/secrets/nextcloud-cli.env
              fi

              user=''${NEXTCLOUD_USER:-''${NC_USER:-$user_default}}
              url=$(normalize_url "''${NEXTCLOUD_URL:-$url_default}")
              pass=''${NEXTCLOUD_PASS:-''${NC_PASSWORD:-}}

              if [ -z "$url" ]; then echo "Error: Missing URL"; exit 1; fi
              if [ -z "$user" ]; then echo "Error: Missing User"; exit 1; fi

              export NC_USER="$user"
              if [ -n "$pass" ]; then export NC_PASSWORD="$pass"; fi

              localDir="${config.users.users.neg.home}/sync/telfir"
              mkdir -p "$localDir"

              exec ${nextcloudcmd} --non-interactive --silent "$localDir" "$url"
            '';
          in "${syncScript}";
        };
      };

      systemd.user.timers.nextcloud-sync = {
        description = "Timer: Nextcloud CLI sync";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "5m";
          Persistent = true;
          Unit = "nextcloud-sync.service";
        };
      };

      environment.systemPackages = [pkgs.nextcloud-client];
    })

    # ============================================================================
    # MONADO (OpenXR)
    # ============================================================================
    (lib.mkIf ((config.features.dev.openxr.enable or false) && (config.features.dev.openxr.runtime.service.enable or false)) {
      systemd.user.services.monado-service = {
        description = "Monado OpenXR Runtime Service";
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = "${lib.getExe' pkgs.monado "monado-service"}";
        };
      };

      # Example configs (Monado & Basalt)
      users.users.neg.maid.file.home = {
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
      };
    })
  ];
}
