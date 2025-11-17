{
  lib,
  pkgs,
  config,
  faProvider ? null,
  ...
}:
let
  firefoxEnabled = (config.features.web.enable or false) && (config.features.web.firefox.enable or false);
in {
  config = lib.mkIf firefoxEnabled (
    let
      common = import ./mozilla-common-lib.nix {inherit lib pkgs config faProvider;};
      inherit (import ./firefox/prefgroups.nix {inherit lib;}) modules prefgroups;

      firefoxAddons =
        if faProvider != null
        then faProvider pkgs
        else throw "firefox: faProvider is required to build managed profiles";

      buildFirefoxXpiAddon = {
        src,
        pname,
        version,
        addonId,
      }:
        pkgs.stdenv.mkDerivation {
          name = "${pname}-${version}";
          inherit src;
          preferLocalBuild = true;
          allowSubstitutes = true;
          buildCommand = ''
            dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
            mkdir -p "$dst"
            install -v -m644 "$src" "$dst/${addonId}.xpi"
          '';
        };

      remoteXpiAddon = {pname, version, addonId, url, sha256}:
        buildFirefoxXpiAddon {
          inherit pname version addonId;
          src = pkgs.fetchurl {inherit url sha256;};
        };

      themeAddon = {name, theme}:
        buildFirefoxXpiAddon {
          pname = "firefox-theme-xpi-${name}";
          version = "1.0";
          addonId = "theme-${name}@outfoxxed.me";
          src = import ./firefox/theme.nix {inherit pkgs name theme;};
        };

      extraAddons = {
        github-reposize = remoteXpiAddon {
          pname = "github-reposize";
          version = "1.7.0";
          addonId = "github-repo-size@mattelrah.com";
          url = "https://addons.mozilla.org/firefox/downloads/file/3854469/github_repo_size-1.7.0.xpi";
          sha256 = "2zGY12esYusaw2IzXM+1kP0B/0Urxu0yj7xXlDlutto=";
        };
        vencord = remoteXpiAddon {
          pname = "vencord";
          version = "1.2.7";
          addonId = "vencord-firefox@vendicated.dev";
          url = "https://addons.mozilla.org/firefox/downloads/file/4123132/vencord_web-1.2.7.xpi";
          sha256 = "A/XKdT0EuDHsQ7mcK9hsXAoAJYUt4Uvp/rtCf/9dAS0=";
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

      sharedUserChrome = ''
        ${builtins.readFile ./firefox/hide_drm_nagbar_chrome.css}
        ${builtins.readFile ./firefox/sideberry_chrome.css}
        ${builtins.readFile ./firefox/sideberry_hide_ext_button.css}
        ${builtins.readFile ./firefox/hide_content_borders.css}
      '';

      mkProfile = {id, name, settings, extensions ? [], userChrome ? sharedUserChrome}: {
        inherit id name;
        path = name;
        isDefault = false;
        inherit settings userChrome;
        extensions.packages = extensions;
      };

      extraProfiles = let
        addonList = firefoxAddons;
      in {
        base = mkProfile {
          id = 5;
          name = "base";
          settings = {};
          extensions = [];
        };

        schizo = mkProfile {
          id = 0;
          name = "schizo";
          settings = modules.schizo;
          extensions =
            (with addonList; [
              darkreader
              sidebery
              sponsorblock
              ublock-origin
              umatrix
            ])
            ++ (with extraAddons; [theme-purple]);
        };

        general = mkProfile {
          id = 1;
          name = "general";
          settings = modules.general;
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
            ++ (with extraAddons; [github-reposize theme-gray]);
        };

        im = mkProfile {
          id = 2;
          name = "im";
          settings = modules.base // prefgroups.misc.restore-pages;
          userChrome = builtins.readFile ./firefox/inline_tabs_chrome.css;
          extensions =
            (with addonList; [
              ublock-origin
            ])
            ++ (with extraAddons; [vencord]);
        };

        trusted = mkProfile {
          id = 3;
          name = "trusted";
          settings = modules.trusted;
          extensions =
            (with addonList; [
              keepassxc-browser
              darkreader
              sidebery
              simplelogin
              ublock-origin
              umatrix
            ])
            ++ (with extraAddons; [github-reposize theme-green]);
        };

        work = mkProfile {
          id = 4;
          name = "work";
          settings = modules.trusted;
          extensions =
            (with addonList; [
              keepassxc-browser
              darkreader
              sidebery
              simplelogin
              ublock-origin
              umatrix
            ])
            ++ (with extraAddons; [github-reposize theme-orange]);
        };
      };

      firefoxPackage = pkgs.firefox-devedition.overrideAttrs (pkg: let
        entries = {
          firefox-im = {
            name = "IMs (Firefox)";
            profile = "im";
            nomime = true;
            noremote = true;
          };
          firefox-trusted = {
            name = "Trusted Firefox";
            profile = "trusted";
            nomime = true;
          };
          firefox-work = {
            name = "Work Firefox";
            profile = "work";
            nomime = true;
          };
          firefox-general = {
            name = "Firefox";
            profile = "general";
          };
          firefox-schizo = {
            name = "Schizo Firefox";
            profile = "schizo";
            nomime = true;
          };
        };
        desktopItems = builtins.attrValues (
          builtins.mapAttrs (n: entry:
            pkg.desktopItem.override (item: {
              name = n;
              desktopName = entry.name;
              mimeTypes =
                if (entry.nomime or false)
                then []
                else item.mimeTypes;
              actions = {};
              exec =
                "${item.exec} ${if (entry.noremote or false) then "-no-remote" else ""} -P ${entry.profile}";
            })
          ) entries
        );
      in {
        buildCommand = ''
          ${pkg.buildCommand}
          rm $out/share/applications/*
          cat <<EOF > $out/share/applications/firefox.desktop
          [Desktop Entry]
          Version=1.4
          Type=Application
          Name=Firefox
          Icon=firefox-devedition
          NoDisplay=true
          EOF
        '' + lib.concatMapStrings (item: ''
          cp ${item}/share/applications/* $out/share/applications
        '') desktopItems;
      });

      baseModule =
        common.mkBrowser {
          name = "firefox";
          package = firefoxPackage;
          profileId = "default-release";
        };

      firefoxBase = baseModule.programs.firefox or {};
    in
      lib.mkMerge [
        baseModule
        {
          programs.firefox =
            firefoxBase
            // {
              profiles = (firefoxBase.profiles or {}) // extraProfiles;
            };
        }
      ]
  );
}
