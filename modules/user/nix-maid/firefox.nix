{
  config,
  lib,
  pkgs,
  negLib,
  inputs,
  ...
}: let
  cfg = config.features.web.firefox;
  guiEnabled = config.features.gui.enable or false;

  # Reuse existing libraries
  # Reuse existing libraries with mocked config for home.homeDirectory compatibility
  commonConfig =
    config
    // {
      home.homeDirectory = config.users.users.neg.home;
      # If other HM-specific attrs are needed, add them here.
      # Current audit shows only home.homeDirectory and features.* are used.
    };
  mozillaCommon = import ../../../home/modules/user/web/mozilla-common-lib.nix {
    inherit lib pkgs negLib;
    config = commonConfig;
  };
  inherit (import ../../../home/modules/user/web/firefox/prefgroups.nix {inherit lib;}) modules prefgroups;

  # --- Addon Helpers (Ported from firefox.nix) ---

  firefoxAddons = pkgs.nur.repos.rycee.firefox-addons;

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
      passthru = {inherit addonId;};
      buildCommand = ''
        dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
        mkdir -p "$dst"
        install -v -m644 "$src" "$dst/${addonId}.xpi"
      '';
    };

  remoteXpiAddon = {
    pname,
    version,
    addonId,
    url,
    sha256,
  }:
    buildFirefoxXpiAddon {
      inherit pname version addonId;
      src = pkgs.fetchurl {inherit url sha256;};
    };

  themeAddon = {
    name,
    theme,
  }:
    buildFirefoxXpiAddon {
      pname = "firefox-theme-xpi-${name}";
      version = "1.0";
      addonId = "theme-${name}@outfoxxed.me";
      src = import ../../../home/modules/user/web/firefox/theme.nix {inherit pkgs name theme;};
    };

  extraAddons = {
    github-reposize = remoteXpiAddon {
      pname = "github-reposize";
      version = "1.7.0";
      addonId = "github-repo-size@mattelrah.com";
      url = "https://addons.mozilla.org/firefox/downloads/file/3854469/github_repo_size-1.7.0.xpi";
      sha256 = "2zGY12esYusaw2IzXM+1kP0B/0Urxu0yj7xXlDlutto=";
    };
    /*
    vencord = buildFirefoxXpiAddon {
      pname = "vencord";
      version = "1.2.7";
      addonId = "{5a6c8631-7b96-4127-ae7c-50bc99015e51}";
      url = "https://addons.mozilla.org/firefox/downloads/file/4123132/vencord_web-1.2.7.xpi";
      sha256 = "143r1ba3m44m80q80839h3876lcfrq5gw6b45y6rb8336x1vj5a5";
      meta = {};
    };
    */
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

  # --- Helpers ---

  mkUserJs = prefs:
    lib.concatStrings (lib.mapAttrsToList (name: value: ''
        user_pref("${name}", ${builtins.toJSON value});
      '')
      prefs);

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
        ++ (with extraAddons; [theme-purple]);
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
        ++ (with extraAddons; [github-reposize theme-gray]);
    };
    im = {
      id = 2;
      name = "im";
      path = "im";
      settings = modules.base // prefgroups.misc.restore-pages;
      userChrome = builtins.readFile ../../../home/modules/user/web/firefox/inline_tabs_chrome.css;
      enable = true;
      isDefault = false;
      extensions =
        (with addonList; [
          ublock-origin
        ])
        ++ (with extraAddons; [
          /*
          vencord
          */
        ]);
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
        ++ (with extraAddons; [github-reposize theme-green]);
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
        ++ (with extraAddons; [github-reposize theme-orange]);
    };
    base = {
      id = 5;
      name = "base";
      path = "base";
      settings = {};
      userChrome = "";
      enable = true;
      isDefault = false;
      extensions = [];
    };
  };

  # Generate extension link
  # Extension package must have addonId.
  # Source path logic:
  # - If it's a wrapper (buildFirefoxXpiAddon), the XPI is at share/mozilla/extensions/{id}/{id}.xpi
  # - If it's a raw XPI/directory, we might need to assume or look inside.
  # The HM module seems to rely on packages providing the right structure for linking extensions folder,
  # or it links individual XPIs?
  # HM `programs.firefox` actually creates a `extensions` directory with symlinks to XPIs.

  mkExtensionFiles = _profileName: profilePath: extensions:
    lib.mkMerge (map (ext: let
        extId = ext.addonId or (throw "Extension ${ext.name} has no addonId");
        # Determine XPI path.
        # Assumption: The package `ext` contains the XPI at share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${extId}.xpi
        # This matches buildFirefoxXpiAddon.
        # NUR packages (rycee) also follow this structure or just expose the XPI?
        # Let's assume standard structure for now.
        xpiPath = "${ext}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${extId}.xpi";
      in {
        ".mozilla/firefox/${profilePath}/extensions/${extId}.xpi".source = xpiPath;
      })
      extensions);

  mkProfileFiles = name: profile:
    lib.mkMerge [
      {
        ".mozilla/firefox/${profile.path}/user.js".text = mkUserJs profile.settings;
      }
      (lib.mkIf (profile.userChrome != "") {
        ".mozilla/firefox/${profile.path}/chrome/userChrome.css".text = profile.userChrome;
      })
      (mkExtensionFiles name profile.path (profile.extensions or []))
    ];
in
  lib.mkIf (guiEnabled && (cfg.enable or false)) {
    environment.systemPackages = [pkgs.firefox-devedition];

    nixpkgs.overlays = [inputs.nur.overlays.default];

    users.users.neg.maid.file.home = lib.mkMerge (
      [
        {".mozilla/firefox/profiles.ini".text = mkProfilesIni profiles;}
      ]
      ++ (lib.mapAttrsToList mkProfileFiles profiles)
    );
  }
