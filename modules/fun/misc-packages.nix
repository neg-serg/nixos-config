##
# Module: fun/misc-packages
# Purpose: Provide novelty/entertainment utilities (matrix rain, ASCII art, etc.).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "fun";
  packages = [

    pkgs.neo # matrix legacy digital rain solution

    pkgs.neg.brrtfetch # animated ASCII art GIF renderer for sysinfo

  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
