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
  # Helper to generate user.js
  mkUserJs = prefs:
    lib.concatStrings (lib.mapAttrsToList (name: value: ''
        user_pref("${name}", ${builtins.toJSON value});
      '')
      prefs);

  # Helper to generate profiles.ini
  mkProfilesIni = profiles: let
    enabledProfiles = lib.filterAttrs (_: v: v.enable) profiles;
    sortedProfiles = lib.sort (a: b: a.id < b.id) (lib.attrValues enabledProfiles);
    mkSection = index: profile: ''
      [Profile${toString index}]
      Name=${profile.name}
      Path=${profile.path}
      IsRelative=1
      Default=${
        if profile.isDefault
        then "1"
        else "0"
      }
    '';
    sections = lib.imap0 mkSection sortedProfiles;
  in ''
    [General]
    StartWithLastProfile=1
    Version=2

    ${lib.concatStringsSep "\n" sections}
  '';

  mkProfileFiles = _name: profile:
    lib.mkMerge [
      {
        ".librewolf/${profile.path}/user.js".text = mkUserJs profile.settings;
      }
      (lib.mkIf (profile.userChrome != "") {
        ".librewolf/${profile.path}/chrome/userChrome.css".text = profile.userChrome;
      })
    ];
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
  in
    lib.mkMerge [
      {
        environment.systemPackages = [pkgs.librewolf]; # privacy-focused Firefox fork with security-hardened defaults
      }
      (n.mkHomeFiles (lib.mkMerge (
        [
          {".librewolf/profiles.ini".text = mkProfilesIni profiles;}
        ]
        ++ (lib.mapAttrsToList mkProfileFiles profiles)
      )))
    ])
