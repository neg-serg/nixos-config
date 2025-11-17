{
  config,
  lib,
  pkgs,
  systemdUser,
  ...
}: let
  cfg = config.services.cachix.watchStore;
in {
  options.services.cachix.watchStore = {
    enable = (lib.mkEnableOption "Run cachix watch-store as a user service") // {default = false;};

    cacheName = lib.mkOption {
      type = lib.types.str;
      example = "my-cachix-cache";
      description = "Cachix cache name to push paths to.";
    };

    authTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/user/1000/secrets/cachix.env";
      description = ''
        Optional EnvironmentFile for systemd with CACHIX_AUTH_TOKEN=... line.
        If null, cachix will use tokens configured by `cachix authtoken`.
      '';
    };

    requireAuthFile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "If true, fail the unit when auth token file is missing.";
    };

    ownCache = {
      enable = (lib.mkEnableOption "Add this cache to Nix substituters and trusted keys") // {default = false;};
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "neg-serg";
        description = "Your Cachix cache name (without URL).";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "neg-serg.cachix.org-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        description = "Public signing key for your Cachix cache (from Cachix UI).";
      };
    };

    hardening = {
      enable = (lib.mkEnableOption "Apply systemd hardening options to the service") // {default = true;};
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--push-filter" ".*\.drv$"];
      description = "Additional arguments passed to `cachix watch-store`.";
    };
  };

  config = lib.mkIf config.features.dev.enable (lib.mkMerge [
    {
      home.packages = lib.mkIf (cfg.enable || cfg.ownCache.enable) [
        pkgs.cachix # binary cache hosting/CLI
      ];

      nix.settings = lib.mkIf cfg.ownCache.enable {
        substituters = [("https://" + cfg.ownCache.name + ".cachix.org")];
        trusted-public-keys = [cfg.ownCache.publicKey];
      };
    }
    (lib.mkIf cfg.enable {
      systemd.user.services."cachix-watch-store" = lib.mkMerge [
        {
          Unit = {
            Description = "Cachix watch-store for ${cfg.cacheName}";
            # On non-NixOS systems /run/current-system is absent; avoid spurious errors
            ConditionPathExists = "/run/current-system";
          };
          Service = let
            envFile =
              lib.mkIf (cfg.authTokenFile != null)
              (
                if cfg.requireAuthFile
                then cfg.authTokenFile
                else ("-" + cfg.authTokenFile)
              );
          in {
            Type = "simple";
            EnvironmentFile = envFile;
            ExecStartPre = lib.mkIf (cfg.authTokenFile != null && cfg.requireAuthFile) ''
              ${lib.getExe' pkgs.bash "bash"} -c 'if ! ${lib.getExe' pkgs.gnugrep "grep"} -q "^CACHIX_AUTH_TOKEN=" ${cfg.authTokenFile}; then echo "CACHIX_AUTH_TOKEN not set in ${cfg.authTokenFile}"; exit 1; fi'
            '';
            ExecStart = let
              exe = lib.getExe pkgs.cachix;
              args = ["watch-store" cfg.cacheName] ++ cfg.extraArgs;
            in "${exe} ${lib.escapeShellArgs args}";
            Restart = "always";
            RestartSec = 10;
            # Optional hardening
            NoNewPrivileges = lib.mkIf cfg.hardening.enable true;
            PrivateTmp = lib.mkIf cfg.hardening.enable true;
            PrivateDevices = lib.mkIf cfg.hardening.enable true;
            ProtectControlGroups = lib.mkIf cfg.hardening.enable true;
            # Need read access to $HOME because the secret path is a symlink into ~/.config/sops-nix
            ProtectHome = lib.mkIf cfg.hardening.enable "read-only";
            ProtectKernelModules = lib.mkIf cfg.hardening.enable true;
            ProtectKernelTunables = lib.mkIf cfg.hardening.enable true;
            ProtectSystem = lib.mkIf cfg.hardening.enable "strict";
            RestrictNamespaces = lib.mkIf cfg.hardening.enable true;
            RestrictSUIDSGID = lib.mkIf cfg.hardening.enable true;
            LockPersonality = lib.mkIf cfg.hardening.enable true;
            MemoryDenyWriteExecute = lib.mkIf cfg.hardening.enable true;
            CapabilityBoundingSet = lib.mkIf cfg.hardening.enable [""];
            RestrictAddressFamilies = lib.mkIf cfg.hardening.enable ["AF_INET" "AF_INET6"];
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline" "sops" "defaultWanted"];})
      ];
    })
  ]);
}
