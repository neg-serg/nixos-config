##
# Module: system/swapfile
# Purpose: Ensure a swap file exists (create if missing) before swap activation.
# Usage: set system.swapfile.enable = true; optionally adjust path/sizeGiB.
{
  lib,
  config,
  pkgs,
  opts,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.system.swapfile;
in
{
  options.system.swapfile = with opts; {
    enable = mkEnableOption "Create the swap file if missing before swap.target.";
    path = mkStrOpt {
      default = "/zero/swapfile";
      description = "Absolute path to the swap file to ensure.";
      example = "/zero/swapfile";
    };
    sizeGiB = mkIntOpt {
      default = 100;
      description = "Swap file size in GiB used on creation (if missing).";
      example = 100;
    };
  };

  config = mkIf cfg.enable {
    # One-shot service that creates the swapfile if it doesn't exist yet.
    systemd.services.swapfile-ensure = {
      description = "Ensure swap file exists (create if missing)";
      serviceConfig = {
        Type = "oneshot";
      };
      # Provide required tools in PATH
      path = [
        pkgs.util-linux # for mkswap, fallocate
        pkgs.coreutils # for dd, chmod, chown, mkdir
      ];
      # Ensure the underlying path is mounted before running
      unitConfig = {
        # Avoid implicit After=basic.target and friends which cause
        # an ordering cycle with Before=swap.target during sysinit.
        DefaultDependencies = false;
        RequiresMountsFor = [ cfg.path ];
      };
      before = [ "swap.target" ]; # must run before any swap units
      wantedBy = [ "swap.target" ]; # run automatically during boot
      script =
        builtins.replaceStrings
          [ "@PATH@" "@SIZEGIB@" "@SIZEGIB_V2@" "@SIZEGIB_V3@" ]
          [
            "${lib.escapeShellArg cfg.path}"
            "${toString cfg.sizeGiB}"
            "${toString cfg.sizeGiB}"
            "${toString cfg.sizeGiB}"
          ]
          (builtins.readFile ./swapfile-ensure.sh);
    };
  };
}
