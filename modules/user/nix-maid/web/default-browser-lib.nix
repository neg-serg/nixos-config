{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  cfg = config.features.web;
  key = cfg.default or "floorp";
  browsers = import ./browsers-table.nix {
    inherit
      lib
      pkgs
      ;
  };
in
lib.attrByPath [ key ] browsers browsers.floorp
