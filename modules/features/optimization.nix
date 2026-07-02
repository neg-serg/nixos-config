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
    nixpkgs.hostPlatform = {
      system = "x86_64-linux";
      gcc.arch = "znver5"; # AMD Zen 5 (Ryzen 9000 series)
      gcc.tune = "znver5";
    };

    # Enable sched_ext (SCX) scheduler
    services.scx = {
      enable = true;
      scheduler = cfg.scx.scheduler;
    };

    # Enable Ananicy-cpp for process auto-prioritization
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
  };
}
