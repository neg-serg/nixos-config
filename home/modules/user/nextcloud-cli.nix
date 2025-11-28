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
      default = "${config.home.homeDirectory}/Nextcloud";
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
      assertions = [
        {
          assertion = config.sops.secrets ? secretName;
          message = ''
            services.nextcloudCli.enable is true but ${secretName} is missing.
            Add secrets/home/nextcloud-cli.env.sops with a NEXTCLOUD_PASS entry.
          '';
        }
      ];

      # Ensure local sync dir exists
      home.activation.ensureNextcloudDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p ${lib.escapeShellArg cfg.localDir}
      '';

      systemd.user.services.nextcloud-sync = lib.mkMerge [
        {
          Unit = {
            Description = "Nextcloud CLI sync";
            StartLimitBurst = "8";
          };
          Service =
            {
              Type = "oneshot";
              ExecStart = let
                args =
                  cfg.extraArgs
                  ++ [
                    "--user"
                    config.home.username
                    "--password-from-env"
                    "NEXTCLOUD_PASS"
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
