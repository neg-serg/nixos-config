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

    zen5 = {
      enable = lib.mkEnableOption "Optimize for AMD Zen 5 (Ryzen 9000/9950X3D)";
      rebuildWorld = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Rebuild entire system with -march=znver5 (WARNING: Massive compile time)";
      };
    };

    scx = {
      scheduler = lib.mkOption {
        type = lib.types.str;
        default = "scx_rusty";
        description = "SCX Scheduler to use (scx_rusty, scx_lavd, scx_bpfland). scx_lavd is recommended for X3D gaming.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Global Compiler Flags (The "Nuclear Option")
    # Forces all packages to be built with -march=znver5
    nixpkgs.hostPlatform = lib.mkIf (cfg.zen5.enable && cfg.zen5.rebuildWorld) {
      system = "x86_64-linux";
      gcc.arch = "znver5";
      gcc.tune = "znver5";
    };
  };
}
