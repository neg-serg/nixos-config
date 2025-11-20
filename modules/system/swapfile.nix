##
# Module: system/swapfile
# Purpose: Ensure a swap file exists (create if missing) before swap activation.
# Usage: set system.swapfile.enable = true; optionally adjust path/sizeGiB.
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  inherit (lib) mkIf mkEnableOption;
  opts = import (inputs.self + "/lib/opts.nix") {inherit lib;};
  cfg = config.system.swapfile;
in {
  options.system.swapfile = with opts; {
    enable = mkEnableOption "Create the swap file if missing before swap.target.";
    path = mkStrOpt {
      default = "/zero/swapfile";
      description = "Absolute path to the swap file to ensure.";
      example = "/zero/swapfile";
    };
    sizeGiB = mkIntOpt {
      default = 80;
      description = "Swap file size in GiB used on creation (if missing).";
      example = 80;
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
      path = [pkgs.util-linux pkgs.coreutils];
      # Ensure the underlying path is mounted before running
      unitConfig = {
        # Avoid implicit After=basic.target and friends which cause
        # an ordering cycle with Before=swap.target during sysinit.
        DefaultDependencies = false;
        RequiresMountsFor = [cfg.path];
      };
      before = ["swap.target"]; # must run before any swap units
      wantedBy = ["swap.target"]; # run automatically during boot
      script = ''
        set -euo pipefail
        P=${lib.escapeShellArg cfg.path}
        S=${toString cfg.sizeGiB}
        if [ ! -f "$P" ]; then
          echo "[swapfile-ensure] Creating swapfile $P (${toString cfg.sizeGiB}G)"
          umask 077
          mkdir -p "$(dirname "$P")"
          if command -v fallocate >/dev/null 2>&1; then
            fallocate -l "${toString cfg.sizeGiB}G" "$P"
          else
            # Fallback: allocate by writing zeros (slower but portable)
            dd if=/dev/zero of="$P" bs=1G count="$S" status=none
          fi
          chmod 600 "$P"
          chown root:root "$P"
          mkswap -f "$P"
        else
          echo "[swapfile-ensure] Swapfile already exists: $P (skipping)"
        fi
      '';
    };
  };
}
