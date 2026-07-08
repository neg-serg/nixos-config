{
  lib,
  pkgs,
  config,
  ...
}:
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

    # SCX disabled: conflicts with isolcpus (kernel CPU isolation for gaming)
    # and scx_lavd does not support dual-CCD X3D topology on LTS kernels.
    # Use ananicy-cpp + isolcpus + GAME_PIN_CPUSET instead.
    # To re-enable: set services.scx.enable = true; in host config

    # Enable Ananicy-cpp for process auto-prioritization
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
  };
}
