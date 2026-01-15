{
  config,
  lib,
  pkgs,
  negLib,
  neg,
  impurity ? null,
  inputs,
  ...
}:
let
  cfg = config.features.web.firefox;
  guiEnabled = config.features.gui.enable or false;

  # Reuse existing libraries with mocked config for home.homeDirectory compatibility
  commonConfig = config // {
    home.homeDirectory = config.users.users.neg.home;
  };
  mozillaCommon = import ./mozilla-common-lib.nix {
    inherit lib pkgs negLib;
    config = commonConfig;
  };
  inherit (import ./firefox-prefgroups.nix { inherit lib; }) modules prefgroups;

  inherit (mozillaCommon) remoteXpiAddon themeAddon mkMozillaModule;

  firefoxAddons = pkgs.nur.repos.rycee.firefox-addons;

  extraAddons = {
    github-reposize = remoteXpiAddon {
      pname = "github-reposize";
      version = "1.7.0";
      addonId = "github-repo-size@mattelrah.com";
      url = "https://addons.mozilla.org/firefox/downloads/file/3854469/github_repo_size-1.7.0.xpi";
      sha256 = "2zGY12esYusaw2IzXM+1kP0B/0Urxu0yj7xXlDlutto=";
    };
    theme-gray = themeAddon {
      name = "theme-gray";
      theme.colors = {
        toolbar = "rgb(42, 46, 50)";
        toolbar_text = "rgb(255, 255, 255)";
        frame = "rgb(27, 30, 32)";
        tab_background_text = "rgb(215, 226, 239)";
        toolbar_field = "rgb(27, 30, 32)";
        toolbar_field_text = "rgb(255, 255, 255)";
        tab_line = "rgb(0, 0, 0)";
        popup = "rgb(42, 46, 50)";
        popup_text = "rgb(252, 252, 252)";
        tab_loading = "rgb(0, 0, 0)";
      };
    };
    theme-green = themeAddon {
      name = "theme-green";
      theme.colors = {
        toolbar = "rgb(26, 53, 40)";
        toolbar_text = "rgb(255, 255, 255)";
        frame = "rgb(26, 43, 35)";
        tab_background_text = "rgb(215, 226, 239)";
        toolbar_field = "rgb(26, 43, 35)";
        toolbar_field_text = "rgb(255, 255, 255)";
        tab_line = "rgb(0, 0, 0)";
        popup = "rgb(42, 46, 50)";
        popup_text = "rgb(252, 252, 252)";
        tab_loading = "rgb(0, 0, 0)";
      };
    };
    theme-orange = themeAddon {
      name = "theme-orange";
      theme.colors = {
        toolbar = "rgb(66, 44, 28)";
        toolbar_text = "rgb(255, 255, 255)";
        frame = "rgb(43, 34, 26)";
        tab_background_text = "rgb(215, 226, 239)";
        toolbar_field = "rgb(43, 34, 26)";
        toolbar_field_text = "rgb(255, 255, 255)";
        tab_line = "rgb(0, 0, 0)";
        popup = "rgb(42, 46, 50)";
        popup_text = "rgb(252, 252, 252)";
        tab_loading = "rgb(0, 0, 0)";
      };
    };
    theme-purple = themeAddon {
      name = "theme-purple";
      theme.colors = {
        toolbar = "rgb(42, 28, 66)";
        toolbar_text = "rgb(255, 255, 255)";
        frame = "rgb(34, 26, 43)";
        tab_background_text = "rgb(215, 226, 239)";
        toolbar_field = "rgb(34, 26, 43)";
        toolbar_field_text = "rgb(255, 255, 255)";
        tab_line = "rgb(0, 0, 0)";
        popup = "rgb(42, 46, 50)";
        popup_text = "rgb(252, 252, 252)";
        tab_loading = "rgb(0, 0, 0)";
      };
    };
  };

  addonList = firefoxAddons;

  # Profile Definitions
  profiles = {
    schizo = {
      id = 0;
      name = "schizo";
      path = "schizo";
      settings = modules.schizo;
      userChrome = mozillaCommon.userChrome;
      enable = true;
      isDefault = false;
      extensions =
        (with addonList; [
          darkreader
          sidebery
          sponsorblock
          ublock-origin
          umatrix
        ])
        ++ (with extraAddons; [ theme-purple ]);
    };
    general = {
      id = 1;
      name = "general";
      path = "general";
      settings = modules.general;
      userChrome = mozillaCommon.userChrome;
      enable = true;
      isDefault = true;
      extensions =
        (with addonList; [
          keepassxc-browser
          darkreader
          sidebery
          simplelogin
          sponsorblock
          ublock-origin
          umatrix
        ])
        ++ (with extraAddons; [
          github-reposize
          theme-gray
        ]);
    };
    im = {
      id = 2;
      name = "im";
      path = "im";
      settings = modules.base // prefgroups.misc.restore-pages;
      userChrome = builtins.readFile ./firefox/inline_tabs_chrome.css;
      enable = true;
      isDefault = false;
      extensions =
        (with addonList; [
          ublock-origin
        ])
        ++ (with extraAddons; [ ]);
    };
    trusted = {
      id = 3;
      name = "trusted";
      path = "trusted";
      settings = modules.trusted;
      userChrome = mozillaCommon.userChrome;
      enable = true;
      isDefault = false;
      extensions =
        (with addonList; [
          keepassxc-browser
          darkreader
          sidebery
          simplelogin
          ublock-origin
          umatrix
        ])
        ++ (with extraAddons; [
          github-reposize
          theme-green
        ]);
    };
    work = {
      id = 4;
      name = "work";
      path = "work";
      settings = modules.trusted;
      userChrome = mozillaCommon.userChrome;
      enable = true;
      isDefault = false;
      extensions =
        (with addonList; [
          keepassxc-browser
          darkreader
          sidebery
          simplelogin
          ublock-origin
          umatrix
        ])
        ++ (with extraAddons; [
          github-reposize
          theme-orange
        ]);
    };
    base = {
      id = 5;
      name = "base";
      path = "base";
      settings = { };
      userChrome = "";
      enable = true;
      isDefault = false;
      extensions = [ ];
    };
  };
in
mkMozillaModule {
  inherit
    impurity
    neg
    cfg
    guiEnabled
    profiles
    ;
  package = pkgs.firefox-devedition; # Web browser built from Firefox Developer Edition source tree
  overlays = [ inputs.nur.overlays.default ];
}
