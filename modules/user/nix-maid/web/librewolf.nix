{
  lib,
  pkgs,
  config,
  negLib,
  faProvider ? null,
  ...
}:
with lib;
  mkIf (config.features.web.enable && config.features.web.librewolf.enable) (let
    common = import ./mozilla-common-lib.nix {inherit lib pkgs config faProvider negLib;};
  in
    common.mkBrowser {
      name = "firefox";
      package = pkgs.librewolf;
      inherit (common) profileId;
    })
