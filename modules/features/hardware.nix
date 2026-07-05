{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features = {
    hardware = {
      bluetooth.enable = mkBool "enable Bluetooth support" false;
    };
    input = {
      kanata.enable = mkBool "enable Kanata keyboard remapper (requires uinput module)" false;
      warpd.enable = mkBool "enable warpd (modal keyboard-driven pointer control)" false;
    };
  };
}
