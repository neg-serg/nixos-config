{
  lib,
  config,
  pkgs,
  systemdUser,
  negLib,
  ...
}: let
  cfg = config.features.cli.nixIndexDB;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Ensure cache dir exists post-write; keeps activation quiet/clean
    {
      home.activation.ensureNixIndexCache = negLib.mkEnsureDirsAfterWrite [
        "${config.xdg.cacheHome}/nix-index"
      ];
    }

    # Systemd user unit: fetch/update prebuilt DB (nix-index -f)
    {
      systemd.user.services.nix-index-update = lib.mkMerge [
        {
          Unit.Description = "Update nix-index prebuilt database";
          Service = {
            Type = "simple";
            # Build/refresh the local database against the pinned nixpkgs used by HM
            # Note: in nix-index 0.1.x, '-f' means '--nixpkgs <path>' (not 'fetch').
            # Database location defaults to $XDG_CACHE_HOME/nix-index; pin it explicitly.
            ExecStart = "${pkgs.nix-index}/bin/nix-index -f ${pkgs.path} --db ${config.xdg.cacheHome}/nix-index";
          };
        }
        # No presets required for the service; timer triggers it.
        # Keep pattern consistent if presets are added later.
      ];

      systemd.user.timers.nix-index-update = lib.mkMerge [
        {
          Unit.Description = "Timer: update nix-index prebuilt DB";
          Timer = {
            OnBootSec = "2m";
            OnUnitActiveSec = "24h";
            Unit = "nix-index-update.service";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
    }
  ]);
}
