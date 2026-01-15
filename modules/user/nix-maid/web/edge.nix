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
  browserName = "edge";
  package = pkgs.microsoft-edge; # Web browser from Microsoft
}
