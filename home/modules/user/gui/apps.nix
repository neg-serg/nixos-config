{
  lib,
  pkgs,
  config,
  bzmenuProvider ? null,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    let
      devSpeed = config.features.devSpeed.enable or false;
      # Core GUI helpers (cliphist, espanso, matugen) are now provided system-wide.
      extras = lib.optionals (! devSpeed && (bzmenuProvider != null)) [
        (bzmenuProvider pkgs) # extra menu helper from flake input
      ];
    in {
      programs.wallust.enable = true;
      home.packages = config.lib.neg.pkgsList extras;
    }
  )
