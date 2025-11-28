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
      type = lib.types.str;
      default = "https://telfir/remote.php/dav/files/${config.home.username}";
      description = "Nextcloud WebDAV URL root to sync.";
    };
    localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/sync/telfir";
      description = "Local directory to sync into.";
    };
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1000/secrets/nextcloud-cli.env";
      description = "Path to dotenv providing NEXTCLOUD_PASS.";
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
        type = lib.types.str;
        default = "";
        description = "Work Nextcloud WebDAV URL root.";
      };
      localDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/sync/wrk";
        description = "Local directory for work sync.";
      };
      envFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/user/1000/secrets/nextcloud-cli-wrk.env";
        description = "Path to dotenv with NEXTCLOUD_PASS for work profile.";
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
        type = lib.types.str;
        default = config.home.username;
        description = "Username for work profile.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.remoteUrl != "" && cfg.localDir != "";
          message = "nextcloudCli requires remoteUrl and localDir";
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
            Environment = ["NC_USER=${config.home.username}"];
            EnvironmentFile = cfg.envFile;
            ExecStart = let
              args = cfg.extraArgs ++ [cfg.localDir cfg.remoteUrl];
            in "${nextcloudcmd} ${lib.escapeShellArgs args}";
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
          assertion = cfg.work.remoteUrl != "" && cfg.work.localDir != "";
          message = "nextcloudCli work profile requires remoteUrl and localDir";
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
            Environment = ["NC_USER=${cfg.work.userName}"];
            EnvironmentFile = cfg.work.envFile;
            ExecStart = let
              args = cfg.work.extraArgs ++ [cfg.work.localDir cfg.work.remoteUrl];
            in "${nextcloudcmd} ${lib.escapeShellArgs args}";
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
