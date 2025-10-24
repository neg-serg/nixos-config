##
# Module: system/kernel/sysctl-mem-extras
# Purpose: Optional memory sysctl tweaks (desktop/work)
# Key options: profiles.performance.memExtras.* (all disabled by default)
# Dependencies: Applies to boot.kernel.sysctl.
{ lib, config, ... }:
let
  opts = import ../../../lib/opts.nix { inherit lib; };
  cfg = config.profiles.performance.memExtras;
in {
  options.profiles.performance.memExtras = {
    enable = opts.mkEnableOption "Enable optional memory sysctl tweaks for desktop/work sessions.";

    # vm.swappiness: favor RAM (lower) vs swap (higher); 20 is a common desktop default.
    swappiness = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Set vm.swappiness to prefer RAM over swap (lower value reduces swapping).";
      };
      value = opts.mkIntOpt {
        default = 20;
        description = "vm.swappiness value (0..200). Lower = less eager swapping.";
        example = 20;
      };
    };

    # vm.max_map_count: raise VMA limit for large games, IDEs, or servers with many mappings.
    maxMapCount = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Set vm.max_map_count for workloads with many memory mappings (e.g., large games, IDEs).";
      };
      value = opts.mkIntOpt {
        default = 1048576;
        description = "vm.max_map_count value (e.g., 262144..1048576).";
        example = 1048576;
      };
    };
  };

  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      (lib.mkIf (cfg.swappiness.enable or false) {
        boot.kernel.sysctl."vm.swappiness" = cfg.swappiness.value;
      })
      (lib.mkIf (cfg.maxMapCount.enable or false) {
        boot.kernel.sysctl."vm.max_map_count" = cfg.maxMapCount.value;
      })
    ]
  );
}
