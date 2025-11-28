{
  lib,
  pkgs,
  config,
  systemdUser,
  ...
}: let
  cfg = config.services.nextcloudCli;
  secretName = "nextcloud-cli/env";
  nextcloudcmd = lib.getExe' pkgs.nextcloud-client "nextcloudcmd";
  secretPath = lib.attrByPath [secretName "path"] null config.sops.secrets;
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
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Provide a default SOPS secret definition when not already set upstream.
      sops.secrets.${secretName} = lib.mkDefault {
        format = "dotenv";
        sopsFile = config.neg.repoRoot + "/secrets/home/nextcloud-cli.env.sops";
        path = "/run/user/1000/secrets/nextcloud-cli.env";
        mode = "0400";
      };

      # Ensure local sync dir exists via tmpfiles
      systemd.user.tmpfiles.rules = [
        "d ${cfg.localDir} 0700 ${config.home.username} ${config.home.username} -"
      ];

      systemd.user.services.nextcloud-sync = lib.mkMerge [
        {
          Unit = {
            Description = "Nextcloud CLI sync";
            StartLimitBurst = "8";
          };
          Service =
            {
              Type = "oneshot";
              Environment = ["NC_USER=${config.home.username}"];
              ExecStart = let
                args =
                  cfg.extraArgs
                  ++ [
                    cfg.localDir
                    cfg.remoteUrl
                  ];
              in "${nextcloudcmd} ${lib.escapeShellArgs args}";
            }
            // lib.optionalAttrs (secretPath != null) {EnvironmentFile = secretPath;};
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
  ]);
}
