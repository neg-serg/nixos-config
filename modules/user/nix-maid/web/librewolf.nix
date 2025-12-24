{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  negLib,
  faProvider ? null,
  ...
}: let
  n = neg impurity;
in
  lib.mkIf (config.features.web.enable && config.features.web.librewolf.enable) (let
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

    mkProfileFiles = _name: profile:
      lib.mkMerge [
        {
          ".librewolf/${profile.path}/user.js".text = n.mkUserJs profile.settings;
        }
        (lib.mkIf (profile.userChrome != "") {
          ".librewolf/${profile.path}/chrome/userChrome.css".text = profile.userChrome;
        })
      ];
  in
    lib.mkMerge [
      {
        environment.systemPackages = [pkgs.librewolf]; # privacy-focused Firefox fork with security-hardened defaults
      }
      (n.mkHomeFiles (lib.mkMerge (
        [
          {".librewolf/profiles.ini".text = n.mkProfilesIni profiles;}
        ]
        ++ (lib.mapAttrsToList mkProfileFiles profiles)
      )))
    ])
