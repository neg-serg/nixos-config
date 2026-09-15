{ lib, mkBool, ... }:
with lib;
{
  options.features.cli = {
    enable = mkBool "enable CLI tooling (fastfetch blizzard wrappers and helpers)" true;
    broot.enable = mkBool "enable broot file manager and shell integration" false;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
  };
}
