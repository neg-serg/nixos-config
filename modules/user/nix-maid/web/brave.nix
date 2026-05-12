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
  browserName = "brave";
  package = pkgs.brave;
  extraPolicies = {
    "BraveVPNEndable" = false;
    "BraveWalletDisabled" = true;
    "BraveAIChatEnabled" = false;
  };
}
