##
# Module: fun/misc-packages
# Purpose: Provide novelty/entertainment utilities (matrix rain and the like).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "fun";
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [ pkgs.neo ]; # matrix legacy digital rain solution
  };
}
