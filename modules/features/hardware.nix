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
  };
}
