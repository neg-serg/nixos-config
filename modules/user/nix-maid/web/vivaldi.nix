{
  pkgs,
  lib,
  config,
  ...
}:
let
  libChromium = import ./chromium-common-lib.nix { inherit lib pkgs; };
in
libChromium.mkChromiumModule {
  inherit config;
  browserName = "vivaldi";
  package = pkgs.vivaldi; # Browser for our Friends, powerful and personal
}
