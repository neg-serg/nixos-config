{
  config,
  lib,
  pkgs,
  negLib,
  ...
}: let
  cfg = config.features.web.floorp;
  guiEnabled = config.features.gui.enable or false;

  commonConfig =
    config
    // {
      home.homeDirectory = config.users.users.neg.home;
    };
  mozillaCommon = import ../../../home/modules/user/web/mozilla-common-lib.nix {
    inherit lib pkgs negLib;
    config = commonConfig;
  };

  # Floorp settings
  profileId = "bqtlgdxw.default";
  shimmerEnabled = cfg.shimmer.enable or false;
  shimmer = pkgs.fetchFromGitHub {
    owner = "nuclearcodecat";
    repo = "shimmer";
    rev = "main";
    sha256 = "0ypwzyfbavdm4za8y0r2yz4b5aaw7g2j0q6n1ppixpr5q8m5ia1p";
  };

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

  # Profile definition
  # Floorp uses base settings + specific tweaks defined in old floorp.nix
  settings =
    mozillaCommon.settings
    // {
      # Tweaks copied from old floorp.nix
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      "browser.newtabpage.activity-stream.feeds.topsites" = false;
      "browser.newtabpage.activity-stream.showTopSites" = false;
      "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
      "browser.newtabpage.activity-stream.showHighlights" = false;
      "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
      "browser.newtabpage.activity-stream.showWeather" = false;
      "browser.newtabpage.activity-stream.feeds.section.weather" = false;
      "browser.newtabpage.activity-stream.feeds.weather" = false;
      "browser.urlbar.quicksuggest.enabled" = false;
      "browser.urlbar.quicksuggest.sponsoredEnabled" = false;
      "browser.urlbar.quicksuggest.nonSponsoredEnabled" = false;
      "browser.urlbar.merino.enabled" = false;
      "browser.urlbar.trending.featureGate" = false;
      "browser.urlbar.quicksuggest.scenario" = "offline";
      "browser.contentblocking.category" = "strict";
      "widget.use-xdg-desktop-portal.file-picker" = 1;
    };

  profiles = {
    default = {
      id = 0;
      name = "default";
      path = profileId; # Use the specific folder name
      inherit settings;
      userChrome = lib.optionalString shimmerEnabled ''
        @import "shimmer/userChrome.css";
      '';
      enable = true;
      isDefault = true;
    };
  };

  mkProfileFiles = _name: profile:
    lib.mkMerge [
      {
        ".floorp/${profile.path}/user.js".text = mkUserJs profile.settings;
      }
      (lib.mkIf (profile.userChrome != "") {
        ".floorp/${profile.path}/chrome/userChrome.css".text = profile.userChrome;
      })
      # Shimmer theme
      (lib.mkIf shimmerEnabled {
        ".floorp/${profile.path}/chrome/shimmer".source = shimmer;
      })
    ];
in
  lib.mkIf (guiEnabled && (cfg.enable or false)) {
    environment.systemPackages = [pkgs.floorp-bin];

    users.users.neg.maid.file.home = lib.mkMerge (
      [
        {".floorp/profiles.ini".text = mkProfilesIni profiles;}
      ]
      ++ (lib.mapAttrsToList mkProfileFiles profiles)
    );

    # Environment variables (from old floorp.nix)
    environment.sessionVariables = {
      MOZ_DBUS_REMOTE = "1";
      MOZ_ENABLE_WAYLAND = "1";
    };
  }
