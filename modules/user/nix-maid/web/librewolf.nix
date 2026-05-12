{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  negLib,
  faProvider ? null,
  ...
}:
let
  common = import ./mozilla-common-lib.nix {
    inherit
      lib
      pkgs
      faProvider
      negLib
      ;
    config = config // {
      home.homeDirectory = config.users.users.neg.home;
    };
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
      extensions = common.addons.common or [ ];
    };
  };
in
common.mkMozillaModule {
  inherit impurity neg profiles;
  cfg = config.features.web.librewolf;
  guiEnabled = config.features.gui.enable;
  package = pkgs.librewolf; # Fork of Firefox, focused on privacy, security and freedom
  browserType = "librewolf";
}
