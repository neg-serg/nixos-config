##
# Module: fun/misc-packages
# Purpose: Provide novelty/entertainment utilities (matrix rain, ASCII art, text banners, etc.).
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
    pkgs.nms # "No More Secrets" decrypt effect
    pkgs.taoup # The Tao of Unix Programming
    pkgs.toilet # text banners

    pkgs.neg.brrtfetch # animated ASCII art GIF renderer for sysinfo

    pkgs.esshader # Shadertoy-compatible GLES shader viewer (shtoy plays links in it)

  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
