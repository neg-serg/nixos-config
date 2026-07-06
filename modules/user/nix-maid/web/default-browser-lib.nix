{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  cfg = config.features.web;
  key = cfg.default or null;
  browsers = import ./browsers-table.nix {
    inherit lib pkgs;
  };
in
if key == null || browsers ? ${key} then
  lib.attrByPath [ (key or null) ] { } browsers
else
  { }
