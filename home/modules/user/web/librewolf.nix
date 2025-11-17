{
  lib,
  pkgs,
  config,
  faProvider ? null,
  ...
}:
with lib;
  mkIf (config.features.web.enable && config.features.web.librewolf.enable) (let
    common = import ./mozilla-common-lib.nix {inherit lib pkgs config faProvider;};
  in
    common.mkBrowser {
      name = "firefox";
      package = pkgs.librewolf;
      inherit (common) profileId;
    })
