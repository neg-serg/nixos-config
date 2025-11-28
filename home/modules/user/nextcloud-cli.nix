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
      description = "Nextcloud WebDAV URL root to sync (e.g. https://host/remote.php/dav/files/<user>).";
    };
    localDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/sync/telfir";
      description = "Local directory to sync into.";
    };
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1000/secrets/nextcloud-cli.env";
      description = "Path to dotenv file providing NEXTCLOUD_PASS.";
    };
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "Systemd OnCalendar spec for sync timer.";
      example = "30min";
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

  config = lib.mkIf cfg.enable (
    let
      mkProfile = {
        name,
        userName,
        remoteUrl,
        localDir,
        envFile,
        onCalendar,
        extraArgs,
      }: let
        suffix =
          if name == "default"
          then ""
          else "-${name}";
      in {
        assertions = [
          {
            assertion = remoteUrl != "" && localDir != "";
            message = "nextcloudCli profile '${name}' requires remoteUrl and localDir";
          }
        ];
        systemd.user.tmpfiles.rules = [
          "d ${localDir} 0700 ${config.home.username} ${config.home.username} -"
        ];
        systemd.user.services."nextcloud-sync${suffix}" = lib.mkMerge [
          {
            Unit = {
              Description = "Nextcloud CLI sync (${name})";
              StartLimitBurst = "8";
            };
            Service = {
              Type = "oneshot";
              Environment = ["NC_USER=${userName}"];
              EnvironmentFile = envFile;
              ExecStart = let
                args = extraArgs ++ [localDir remoteUrl];
              in "${nextcloudcmd} ${lib.escapeShellArgs args}";
            };
          }
          (systemdUser.mkUnitFromPresets {presets = ["netOnline" "sops"];})
        ];
        systemd.user.timers."nextcloud-sync${suffix}" = lib.mkMerge [
          {
            Unit = {Description = "Timer: Nextcloud CLI sync (${name})";};
            Timer = {
              OnCalendar = onCalendar;
              RandomizedDelaySec = "5m";
              Persistent = true;
              Unit = "nextcloud-sync${suffix}.service";
            };
          }
          (systemdUser.mkUnitFromPresets {presets = ["timers"];})
        ];
      };

      profiles =
        [
          {
            name = "default";
            userName = config.home.username;
            remoteUrl = cfg.remoteUrl;
            localDir = cfg.localDir;
            envFile = cfg.envFile;
            onCalendar = cfg.onCalendar;
            extraArgs = cfg.extraArgs;
          }
        ]
        ++ lib.optional cfg.work.enable {
          name = "wrk";
          userName = cfg.work.userName;
          remoteUrl = cfg.work.remoteUrl;
          localDir = cfg.work.localDir;
          envFile = cfg.work.envFile;
          onCalendar = cfg.work.onCalendar;
          extraArgs = cfg.work.extraArgs;
        };
    in
      lib.mkMerge (map mkProfile profiles)
  );
}
