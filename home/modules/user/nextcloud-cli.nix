{
  lib,
  pkgs,
  config,
  systemdUser,
  ...
}: let
  cfg = config.services.nextcloudCli;
  nextcloudcmd = lib.getExe' pkgs.nextcloud-client "nextcloudcmd";
in {
  options.services.nextcloudCli = {
    enable = lib.mkEnableOption "nextcloudcmd periodic sync (user-level)";
    remoteUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://telfir/remote.php/dav/files/${config.home.username}";
      description = "Nextcloud WebDAV URL root to sync; can be overridden with NEXTCLOUD_URL from envFile.";
    };
    userName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.home.username;
      description = "Username to authenticate; can be overridden with NEXTCLOUD_USER from envFile.";
    };
    localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/sync/telfir";
      description = "Local directory to sync into.";
    };
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1000/secrets/nextcloud-cli.env";
      description = "Path to dotenv providing NEXTCLOUD_PASS (and optionally NEXTCLOUD_URL/NEXTCLOUD_USER/NC_* overrides).";
    };
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "Systemd OnCalendar spec for sync timer.";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["--non-interactive" "--silent"];
      description = "Extra arguments passed to nextcloudcmd.";
    };
    work = {
      enable = lib.mkEnableOption "enable secondary Nextcloud sync profile";
      remoteUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Work Nextcloud WebDAV URL root; can be overridden with NEXTCLOUD_URL from envFile.";
      };
      localDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/sync/wrk";
        description = "Local directory for work sync.";
      };
      envFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/user/1000/secrets/nextcloud-cli-wrk.env";
        description = "Path to dotenv with NEXTCLOUD_PASS and optional NEXTCLOUD_URL/NEXTCLOUD_USER overrides for work profile.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        description = "OnCalendar for work profile.";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["--non-interactive" "--silent"];
        description = "Extra arguments for work profile.";
      };
      userName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.home.username;
        description = "Username for work profile; can be overridden with NEXTCLOUD_USER from envFile.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.localDir != "";
          message = "nextcloudCli requires localDir";
        }
      ];
      systemd.user.tmpfiles.rules = [
        "d ${cfg.localDir} 0700 ${config.home.username} ${config.home.username} -"
      ];
      systemd.user.services.nextcloud-sync = lib.mkMerge [
        {
          Unit = {
            Description = "Nextcloud CLI sync";
            StartLimitBurst = "8";
          };
          Service = {
            Type = "oneshot";
            EnvironmentFile = cfg.envFile;
            ExecStart = let
              remoteDefault =
                if cfg.remoteUrl == null
                then ""
                else cfg.remoteUrl;
              userDefault =
                if cfg.userName == null
                then config.home.username
                else cfg.userName;
              runner = pkgs.writeShellScript "nextcloud-sync" ''
                set -euo pipefail
                user_default=${lib.escapeShellArg userDefault}
                url_default=${lib.escapeShellArg remoteDefault}
                user=''${NEXTCLOUD_USER:-''${NC_USER:-$user_default}}
                url=''${NEXTCLOUD_URL:-$url_default}
                pass=''${NEXTCLOUD_PASS:-''${NC_PASSWORD:-}}

                if [ -z "$url" ]; then
                  echo "nextcloud-sync: remote URL is missing (set remoteUrl or NEXTCLOUD_URL)" >&2
                  exit 1
                fi
                if [ -z "$user" ]; then
                  echo "nextcloud-sync: username is missing (set userName or NEXTCLOUD_USER/NC_USER)" >&2
                  exit 1
                fi

                export NC_USER="$user"
                if [ -n "$pass" ]; then
                  export NC_PASSWORD="$pass"
                fi

                exec ${nextcloudcmd} ${lib.escapeShellArgs cfg.extraArgs} ${lib.escapeShellArg cfg.localDir} "$url"
              '';
            in
              runner;
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline" "sops"];})
      ];
      systemd.user.timers.nextcloud-sync = lib.mkMerge [
        {
          Unit = {Description = "Timer: Nextcloud CLI sync";};
          Timer = {
            OnCalendar = cfg.onCalendar;
            RandomizedDelaySec = "5m";
            Persistent = true;
            Unit = "nextcloud-sync.service";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
    }
    (lib.mkIf cfg.work.enable {
      assertions = [
        {
          assertion = cfg.work.localDir != "";
          message = "nextcloudCli work profile requires localDir";
        }
      ];
      systemd.user.tmpfiles.rules = [
        "d ${cfg.work.localDir} 0700 ${config.home.username} ${config.home.username} -"
      ];
      systemd.user.services."nextcloud-sync-wrk" = lib.mkMerge [
        {
          Unit = {
            Description = "Nextcloud CLI sync (wrk)";
            StartLimitBurst = "8";
          };
          Service = {
            Type = "oneshot";
            EnvironmentFile = cfg.work.envFile;
            ExecStart = let
              remoteDefault =
                if cfg.work.remoteUrl == null
                then ""
                else cfg.work.remoteUrl;
              userDefault =
                if cfg.work.userName == null
                then config.home.username
                else cfg.work.userName;
              runner = pkgs.writeShellScript "nextcloud-sync-wrk" ''
                set -euo pipefail
                user_default=${lib.escapeShellArg userDefault}
                url_default=${lib.escapeShellArg remoteDefault}
                user=''${NEXTCLOUD_USER:-''${NC_USER:-$user_default}}
                url=''${NEXTCLOUD_URL:-$url_default}
                pass=''${NEXTCLOUD_PASS:-''${NC_PASSWORD:-}}

                if [ -z "$url" ]; then
                  echo "nextcloud-sync-wrk: remote URL is missing (set work.remoteUrl or NEXTCLOUD_URL)" >&2
                  exit 1
                fi
                if [ -z "$user" ]; then
                  echo "nextcloud-sync-wrk: username is missing (set work.userName or NEXTCLOUD_USER/NC_USER)" >&2
                  exit 1
                fi

                export NC_USER="$user"
                if [ -n "$pass" ]; then
                  export NC_PASSWORD="$pass"
                fi

                exec ${nextcloudcmd} ${lib.escapeShellArgs cfg.work.extraArgs} ${lib.escapeShellArg cfg.work.localDir} "$url"
              '';
            in
              runner;
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline" "sops"];})
      ];
      systemd.user.timers."nextcloud-sync-wrk" = lib.mkMerge [
        {
          Unit = {Description = "Timer: Nextcloud CLI sync (wrk)";};
          Timer = {
            OnCalendar = cfg.work.onCalendar;
            RandomizedDelaySec = "5m";
            Persistent = true;
            Unit = "nextcloud-sync-wrk.service";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
    })
  ]);
}
