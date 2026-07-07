{ lib, mkBool, ... }:
with lib;
{
  options.features.cli = {
    broot.enable = mkBool "enable broot file manager and shell integration" false;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
  };
}
