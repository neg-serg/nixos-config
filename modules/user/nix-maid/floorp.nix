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
  mozillaCommon = import ./web/mozilla-common-lib.nix {
    inherit lib pkgs negLib;
    config = commonConfig;
  };

  # Floorp settings
  profileId = "bqtlgdxw.default";

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

      # Proxy settings - disable proxy (reset from Hiddify)
      # 0 = No proxy, 1 = Manual, 2 = PAC, 4 = WPAD, 5 = System
      "network.proxy.type" = 0;
      "network.proxy.http" = "";
      "network.proxy.http_port" = 0;
      "network.proxy.ssl" = "";
      "network.proxy.ssl_port" = 0;
      "network.proxy.socks" = "";
      "network.proxy.socks_port" = 0;
      "network.proxy.no_proxies_on" = "localhost, 127.0.0.1";
    };

  profiles = {
    default = {
      id = 0;
      name = "default";
      path = profileId; # Use the specific folder name
      inherit settings;
      userChrome = "";
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
    ];
in
  lib.mkIf (guiEnabled && (cfg.enable or false)) {
    environment.systemPackages = [
      pkgs.floorp-bin # custom Firefox-based browser with Japanese origin
      # Native messaging hosts for browser extensions
      pkgs.tridactyl-native # Tridactyl vim-like bindings native messenger
      pkgs.pywalfox-native # Pywalfox theme colors native messenger
    ];

    users.users.neg.maid.file.home = lib.mkMerge (
      [
        {".floorp/profiles.ini".text = mkProfilesIni profiles;}
        # Tridactyl native messenger manifest - link to ~/.mozilla for native messaging
        {".mozilla/native-messaging-hosts/tridactyl.json".source = "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";}
      ]
      ++ (lib.mapAttrsToList mkProfileFiles profiles)
    );

    # Floorp policies for extensions (force-install via enterprise policies)
    # Note: Floorp uses the same policies format as Firefox, placed in /etc/floorp/policies/
    environment.etc."floorp/policies/policies.json".text = builtins.toJSON {
      policies = {
        ExtensionSettings = {
          # Tridactyl - vim-like keyboard navigation
          "tridactyl.vim@cmcaine.co.uk" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/tridactyl-vim/latest.xpi";
          };
          # Dark Reader - dark mode for all sites
          "addon@darkreader.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
          };
          # Stylus - custom CSS for sites
          "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/styl-us/latest.xpi";
          };
          # Search by Image
          "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/search_by_image/latest.xpi";
          };
          # Hide Scrollbars
          "hide-scrollbars@qashto" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/hide-scrollbars/latest.xpi";
          };
          # YouTube Dislikes
          "kellyc-show-youtube-dislikes@nradiowave" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/kellyc-show-youtube-dislikes/latest.xpi";
          };
          # VK Music Downloader
          "{4a311e5c-1ccc-49b7-9c23-3e2b47b6c6d5}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/%D1%81%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C-%D0%BC%D1%83%D0%B7%D1%8B%D0%BA%D1%83-%D1%81-%D0%B2%D0%BA-vkd/latest.xpi";
          };
          # Block Tampermonkey
          "firefox@tampermonkey.net" = {installation_mode = "blocked";};
        };
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        CaptivePortal = false;
        DNSOverHTTPS = {
          Enabled = true;
          Locked = false;
        };
      };
    };

    # Environment variables (from old floorp.nix)
    environment.sessionVariables = {
      MOZ_DBUS_REMOTE = "1";
      MOZ_ENABLE_WAYLAND = "1";
    };
  }
