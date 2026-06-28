{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.cli = {
    broot.enable = mkBool "enable broot file manager and shell integration" false;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
    television.enable = mkBool "enable television (blazingly fast fuzzy finder)" true;
  };
}
