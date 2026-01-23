{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  webEnabled = config.features.web.enable or false;
  nyxtEnabled = webEnabled && (config.features.web.nyxt.enable or false);
  package = inputs.nyxt-bin.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  config = lib.mkIf nyxtEnabled {
    environment.systemPackages = lib.mkAfter [ package ]; # Keyboard-centric, Common Lisp-extensible browser
  };
}
