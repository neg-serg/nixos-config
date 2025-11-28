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
    secretName = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud-cli/env";
      description = "Name of the SOPS secret (attr path) providing NEXTCLOUD_PASS.";
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
    additionalProfiles = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule ({name, ...}: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Profile name used to suffix unit names.";
          };
          userName = lib.mkOption {
            type = lib.types.str;
            default = config.home.username;
            description = "Username for this profile.";
          };
          remoteUrl = lib.mkOption {
            type = lib.types.str;
            description = "Nextcloud WebDAV URL root to sync for this profile.";
          };
          localDir = lib.mkOption {
            type = lib.types.str;
            description = "Local directory to sync into for this profile.";
          };
          secretName = lib.mkOption {
            type = lib.types.str;
            default = "nextcloud-cli/${name}";
            description = "SOPS secret path (attr) providing NEXTCLOUD_PASS for this profile.";
          };
          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = config.services.nextcloudCli.onCalendar;
            description = "OnCalendar for this profile.";
          };
          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = config.services.nextcloudCli.extraArgs;
            description = "Extra arguments for this profile.";
          };
        };
      }));
      default = [];
      description = "Additional nextcloudcmd profiles (independent dirs/credentials).";
    };
  };

  config = lib.mkIf cfg.enable (let
    mkProfile = p: let
      suffix =
        if p.name == "default"
        then ""
        else "-${p.name}";
      envPath =
        if p.name == "default"
        then "/run/user/1000/secrets/nextcloud-cli.env"
        else "/run/user/1000/secrets/nextcloud-cli-${p.name}.env";
      sopsFile =
        if p.name == "default"
        then config.neg.repoRoot + "/secrets/home/nextcloud-cli.env.sops"
        else config.neg.repoRoot + "/secrets/home/nextcloud-cli-${p.name}.env.sops";
    in
      lib.mkMerge [
        {
          sops.secrets."${p.secretName}" = lib.mkDefault {
            format = "dotenv";
            inherit sopsFile;
            path = envPath;
            mode = "0400";
          };
          systemd.user.tmpfiles.rules = [
            "d ${p.localDir} 0700 ${config.home.username} ${config.home.username} -"
          ];
          systemd.user.services."nextcloud-sync${suffix}" = lib.mkMerge [
            {
              Unit = {
                Description = "Nextcloud CLI sync (${p.name})";
                StartLimitBurst = "8";
              };
              Service =
                {
                  Type = "oneshot";
                  Environment = ["NC_USER=${p.userName}"];
                  ExecStart = let
                    args = p.extraArgs ++ [p.localDir p.remoteUrl];
                  in "${nextcloudcmd} ${lib.escapeShellArgs args}";
                }
                // {EnvironmentFile = envPath;};
            }
            (systemdUser.mkUnitFromPresets {presets = ["netOnline" "sops"];})
          ];
          systemd.user.timers."nextcloud-sync${suffix}" = lib.mkMerge [
            {
              Unit = {Description = "Timer: Nextcloud CLI sync (${p.name})";};
              Timer = {
                OnCalendar = p.onCalendar;
                RandomizedDelaySec = "5m";
                Persistent = true;
                Unit = "nextcloud-sync${suffix}.service";
              };
            }
            (systemdUser.mkUnitFromPresets {presets = ["timers"];})
          ];
        }
      ];

    defaultProfile = {
      name = "default";
      userName = config.home.username;
      remoteUrl = cfg.remoteUrl;
      localDir = cfg.localDir;
      secretName = cfg.secretName;
      onCalendar = cfg.onCalendar;
      extraArgs = cfg.extraArgs;
    };

    extraProfiles =
      map
      (p: {
        inherit
          (p)
          name
          userName
          remoteUrl
          localDir
          secretName
          onCalendar
          extraArgs
          ;
      })
      cfg.additionalProfiles;
  in
    lib.mkMerge (map mkProfile ([defaultProfile] ++ extraProfiles)));
}
