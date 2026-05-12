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
        default = "scx_rusty";
        description = "SCX Scheduler to use (scx_rusty, scx_lavd, scx_bpfland). scx_lavd is recommended for X3D gaming.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # World rebuild disabled to prevent massive compilation times.
    # Zen 5 optimizations are applied via kernel selection (znver4) and
    # specific package overrides (using znver4 for cache compatibility)
  };
}
