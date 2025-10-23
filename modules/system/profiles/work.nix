##
# Module: system/profiles/work
# Purpose: Desktop "work" profile — enable zswap and related memory tweaks suitable for interactive workloads.
# Key options: profiles.work.enable
# Dependencies: Relies on profiles.performance.zswap options.
{ lib, config, ... }:
let
  cfg = config.profiles.work or { enable = false; };
in {
  options.profiles.work.enable = lib.mkEnableOption "Enable desktop 'work' profile (turn on zswap).";

  config = lib.mkIf cfg.enable {
    # Prefer compressed in-RAM swap for desk/work sessions to reduce disk thrash
    profiles.performance.zswap = {
      enable = lib.mkForce true;
      compressor = lib.mkDefault "zstd";
      maxPoolPercent = lib.mkDefault 15;
      zpool = lib.mkDefault "zsmalloc";
    };
  };
}

