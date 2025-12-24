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
    commonConfig = config // {home.homeDirectory = config.users.users.neg.home;};
    common = import ./mozilla-common-lib.nix {
      inherit lib pkgs faProvider negLib;
      config = commonConfig;
    };
    profiles = {
      default = {
        id = 0;
        name = "default";
        path = "default";
        settings = common.settings;
        userChrome = common.userChrome;
        enable = true;
        isDefault = true;
        extensions = common.addons.common or [];
      };
    };
  in {
    environment.systemPackages = [pkgs.librewolf]; # privacy-focused Firefox fork with security-hardened defaults
    nixpkgs.overlays = [inputs.nur.overlays.default];

    users.users.neg.maid.file.home = lib.mkMerge (
      [
        {".librewolf/profiles.ini".text = common.mkProfilesIni profiles;}
      ]
      ++ (lib.mapAttrsToList (name: profile: common.mkProfileFiles name profile) profiles)
    );
  })
