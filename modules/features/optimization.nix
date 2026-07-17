{ lib, config, ... }:
let
  cfg = config.features.optimization;
in
{
  options.features.optimization = {
    enable = lib.mkEnableOption "Global system optimizations";

    scx = {
      scheduler = lib.mkOption {
        type = lib.types.str;
        default = "scx_lavd";
        description = "SCX Scheduler to use (scx_rusty, scx_lavd, scx_bpfland). scx_lavd is recommended for X3D gaming.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.hostPlatform.system = "x86_64-linux";

    # SCX BPF scheduler replaces kernel CPU isolation.
    # scx_lavd is dual-CCD X3D-aware — it detects V-Cache CCD at runtime
    # and favours it for latency-sensitive tasks without isolcpus.
    features.optimization.scx.enable = lib.mkDefault true;

    # Ananicy-cpp removed — was causing cgroup v2 errors in current boot.
    # Process prioritization is handled by SCX + cpuset pinning.
  };
}
