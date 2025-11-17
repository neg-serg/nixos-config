{
  lib,
  pkgs,
  config,
  faProvider ? null,
  ...
}:
with lib; let
  # Prefer configured XDG Downloads directory; fallback to ~/dw to match defaults
  dlDir = lib.attrByPath ["xdg" "userDirs" "download"] "${config.home.homeDirectory}/dw" config;
  useNurAddons = config.features.web.addonsFromNUR.enable or false;
  fa =
    if useNurAddons && faProvider != null
    then faProvider pkgs
    else null;
  addons =
    if fa != null
    then config.lib.neg.browserAddons fa
    else {common = [];};
  nativeMessagingHosts = [
    pkgs.pywalfox-native # native host for Pywalfox (theme colors)
    pkgs.tridactyl-native # native host for Tridactyl extension
  ];

  baseSettings = {
    # Locale/region
    "browser.region.update.region" = "US";
    "browser.search.region" = "US";
    "intl.locale.requested" = "en-US";
    # Downloads and userChrome support
    "browser.download.dir" = dlDir;
    "browser.download.useDownloadDir" = true;
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    # Content blocking and notifications
    "browser.contentblocking.category" = "standard";
    "permissions.default.desktop-notification" = 2;
    # HW video decoding (Wayland/VA-API)
    "media.ffmpeg.vaapi.enabled" = true;
    "media.hardware-video-decoding.enabled" = true;
    # Disable autoplay
    "media.autoplay.default" = 1; # block audible
    "media.autoplay.blocking_policy" = 2;
    "media.autoplay.block-webaudio" = true;
    "media.block-autoplay-until-in-foreground" = true;
    # Address bar tweaks
    # Do not replace URL with search terms on search result pages (prevents engine badge overlay)
    "browser.urlbar.showSearchTerms.enabled" = false;
    # Do not suggest alternate search engines as a dedicated row in the urlbar popup
    "browser.urlbar.suggest.engines" = false;
    # Optional: do not show Top Sites in urlbar (reduces engine rows)
    "browser.urlbar.suggest.topsites" = false;
    # Optional: do not suggest quickactions (less badges)
    "browser.urlbar.suggest.quickactions" = false;
    # Do not show separate Search Bar widget in toolbar
    "browser.search.widget.inNavBar" = false;

    # DevTools (Browser Toolbox) and UI inspection helpers
    # Allow inspecting browser chrome (not just web content)
    "devtools.chrome.enabled" = true;
    # Allow remote debugging (required by Browser Toolbox)
    "devtools.debugger.remote-enabled" = true;
    # Do not prompt when connecting Browser Toolbox
    "devtools.debugger.prompt-connection" = false;
    # Keep popups open: default off; enable manually when inspecting
    "ui.popup.disable_autohide" = false;
  };

  # FastFox-like prefs: performance-leaning overrides gated by features.web.prefs.fastfox.enable.
  # Summary: boosts parallelism (HTTP/DNS), enables site isolation (fission),
  # prefers lazy tab restore, WebRender pacing, disables built-in PDF viewer/scripting,
  # and applies a few UX/QoL toggles.
  # Caveats: may increase memory footprint (fission, processCount),
  # can break AMO install flow if RFP MAM is blocked (privacy.resistFingerprinting.block_mozAddonManager),
  # disables inline PDF viewing (pdfjs.*), and certain render flags may misbehave on rare GPU/driver combos.
  fastfoxSettings = {
    # UX / warnings / minor QoL
    "general.warnOnAboutConfig" = false;
    "accessibility.typeaheadfind.flashBar" = 0;
    "browser.bookmarks.addedImportButton" = false;
    "browser.bookmarks.restore_default_bookmarks" = false;
    # PDF viewer tightening (disables inline PDF; use external viewer)
    "pdfjs.disabled" = true;
    "pdfjs.enableScripting" = false;
    "pdfjs.enableXFA" = false;
    # Color management
    "gfx.color_management.enabled" = true;
    "gfx.color_management.enablev4" = false;
    # Process model and site isolation (more processes; more memory)
    "dom.ipc.processCount" = 8;
    "fission.autostart" = true;
    # Networking concurrency and caches (aggressive parallelism + larger caches)
    "network.http.max-connections" = 1800;
    "network.http.max-persistent-connections-per-server" = 10;
    "network.http.max-urgent-start-excessive-connections-per-host" = 6;
    "network.dnsCacheEntries" = 10000;
    "network.dnsCacheExpirationGracePeriod" = 240;
    "network.ssl_tokens_cache_capacity" = 32768;
    "network.speculative-connection.enabled" = true;
    # Memory / tabs
    "browser.tabs.unloadOnLowMemory" = true;
    "browser.sessionstore.restore_tabs_lazily" = true;
    # Rendering (force WebRender + precache shaders on supported GPUs)
    "gfx.webrender.all" = true;
    "gfx.webrender.precache-shaders" = true;
    # Misc (minor UI and RFP/AMO behavior)
    "browser.startup.preXulSkeletonUI" = false;
    # Optional: MAM exposure under RFP (can break AMO)
    "privacy.resistFingerprinting.block_mozAddonManager" = true;
  };

  settings = baseSettings // (optionalAttrs (config.features.web.prefs.fastfox.enable or false) fastfoxSettings);

  extraConfig = "";

  userChrome = ''
    /* Hide buttons you don't use */
    #nav-bar #back-button,
    #nav-bar #forward-button,
    #nav-bar #stop-reload-button,
    #nav-bar #home-button { display: none !important; }
    /* Compact urlbar text and results */
    :root { --urlbar-min-height: 30px !important; }
    #urlbar-input { font-size: 14px !important; font-weight: 500 !important; }
    .urlbarView-row .urlbarView-title,
    .urlbarView-row .urlbarView-url { font-size: 12px !important; font-weight: 400 !important; }
    /* Keep urlbar dropdown reasonable */
    .urlbarView-body-inner{ max-height: min(60vh, 640px) !important; overflow: auto !important; }
  '';

  # Tridactyl UI sizing (fallback cap):
  # Some Tridactyl builds/layouts render the completions list without the expected
  # inner wrapper targeted by theme CSS, which can lead to very tall popups
  # (e.g., :tabopen listing many buffers). Provide a conservative fallback that
  # caps the visible height to ~8 lines and scrolls, without touching other layout.
  tridactylUserContent = ''
    /* Fallback: cap completions viewport to ~8 rows and enable scrolling */
    #TridactylModeIndicatorAndCmdline #completions,
    #TridactylCommandline #completions{
      /* Fallback line height if theme doesn't provide one */
      --tri-option-height: 1.4em;
      max-height: calc(8 * var(--tri-option-height)) !important;
      overflow-y: auto !important;
    }

    /* If an inner wrapper exists, cap it as well (newer markup variants) */
    #TridactylModeIndicatorAndCmdline #completions > div,
    #TridactylCommandline #completions > div{
      max-height: calc(8 * var(--tri-option-height)) !important;
      overflow-y: auto !important;
    }

    /* Buffer (tabopen) source often grows aggressively; enforce row height */
    #TridactylModeIndicatorAndCmdline #completions table tr,
    #TridactylCommandline #completions table tr{
      line-height: var(--tri-option-height) !important;
    }
  '';

  # Optional: move URL bar/toolbar to bottom.
  # Based on MrOtherGuy's firefox-csshacks (navbar_below_content.css).
  # Upstream: https://github.com/MrOtherGuy/firefox-csshacks
  # Notes:
  # - Keeps extension panels working by using -webkit-box in fixed toolbar.
  # - Pushes content up with a margin on #browser to avoid overlap.
  # - Flips urlbar popup to open upward when at the bottom.
  bottomNavbarChrome = ''
    @-moz-document url(chrome://browser/content/browser.xhtml){
      /* Height of the bottom toolbar (normal/compact density) */
      :root:not([inFullscreen]){
        --uc-bottom-toolbar-height: calc(39px + var(--toolbarbutton-outer-padding));
      }
      :root[uidensity="compact"]:not([inFullscreen]){
        --uc-bottom-toolbar-height: calc(32px + var(--toolbarbutton-outer-padding));
      }

      /* Keep page content above the bottom toolbar */
      #browser,
      #customization-container{ margin-bottom: var(--uc-bottom-toolbar-height,0px) }

      /* Pin navigation toolbar to the bottom edge */
      #nav-bar{
        position: fixed !important;
        bottom: 0;
        display: -webkit-box; /* keeps extension panels working */
        width: 100%;
        z-index: 1;
      }
      #nav-bar-customization-target{ -webkit-box-flex: 1; }

      /* Theme backgrounds for lwtheme */
      :root[lwtheme] #nav-bar{
        background-image: linear-gradient(var(--toolbar-bgcolor),var(--toolbar-bgcolor)), var(--lwt-additional-images,var(--toolbar-bgimage)) !important;
        background-position: top,var(--lwt-background-alignment);
        background-repeat: repeat,var(--lwt-background-tiling);
      }
      :root[lwtheme-image] #nav-bar{
        background-image: linear-gradient(var(--toolbar-bgcolor),var(--toolbar-bgcolor)),var(--lwt-header-image), var(--lwt-additional-images,var(--toolbar-bgimage)) !important;
      }

      /* Urlbar popup opens upward when toolbar is at the bottom */
      #urlbar[breakout][breakout-extend]{
        display: flex !important;
        flex-direction: column-reverse !important;
        bottom: 0 !important;
        top: auto !important;
      }

      .urlbarView-body-inner{ border-top-style: none !important; }

      /* Panel sizing fixes (helps big dropdowns) */
      .panel-viewstack{ max-height: unset !important; }
    }
  '';

  # Hide the URL bar search-mode chip (engine badge) in a minimal, stable way.
  # This mirrors commonly used FirefoxCSS snippets: it targets the indicator id/class
  # that Firefox uses across recent versions. It does not touch other urlbar layout.
  hideSearchModeChip = ''
    @-moz-document url(chrome://browser/content/browser.xhtml){
      #urlbar-search-mode-indicator,
      #urlbar .urlbar-search-mode-indicator,
      /* Floorp/Lepton sometimes renders indicator at toolbox scope */
      #navigator-toolbox .urlbar-search-mode-indicator{ display: none !important; }
    }
  '';

  # Hide urlbar one-off engine buttons entirely (canonical pattern used widely in FirefoxCSS).
  # This removes the Google/engine icons row in the urlbar popup.
  hideUrlbarOneOffs = ''
    @-moz-document url(chrome://browser/content/browser.xhtml){
      /* Hide urlbar one-off engine row in all common containers */
      #urlbar .search-one-offs,
      .urlbarView .search-one-offs,
      #PopupAutoCompleteRichResult .search-one-offs{ display: none !important; }
      /* Hide individual engine one-off items, including Floorp/Lepton ids */
      #urlbar .searchbar-engine-one-off-item,
      .search-panel-one-offs .searchbar-engine-one-off-item,
      #urlbar-engine-one-off-item-tabs{ display: none !important; }
      /* When in searchmode, remove any reserved left space for a chip */
      #urlbar[searchmode] #urlbar-input-container{ padding-inline-start: 0 !important; }
      #urlbar[searchmode] #urlbar-input{ margin-inline-start: 0 !important; }
    }
  '';

  # Hide the classic Search Bar widget entirely (engine dropdown icon + field)
  # Some themes (e.g., Floorp/Lepton) may expose the engine badge as a floating
  # button near the top when navbar is moved. Removing the widget avoids that.
  hideSearchBarWidget = ''
    @-moz-document url(chrome://browser/content/browser.xhtml){
      #search-container,
      #searchbar,
      #searchbar-container{ display: none !important; }
    }
  '';

  # No global removal of engine badges/one-offs here — will follow upstream guidance.

  policies = {
    ExtensionSettings = {
      "hide-scrollbars@qashto" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/hide-scrollbars/latest.xpi";
      };
      "kellyc-show-youtube-dislikes@nradiowave" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/kellyc-show-youtube-dislikes/latest.xpi";
      };
      "{4a311e5c-1ccc-49b7-9c23-3e2b47b6c6d5}" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/%D1%81%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C-%D0%BC%D1%83%D0%B7%D1%8B%D0%BA%D1%83-%D1%81-%D0%B2%D0%BA-vkd/latest.xpi";
      };
      # Explicitly block Tampermonkey userscript manager
      "firefox@tampermonkey.net" = {installation_mode = "blocked";};
    };
    Extensions = {
      Install = true;
      Updates = true;
    };
  };
in {
  inherit nativeMessagingHosts settings extraConfig userChrome policies addons;
  # mkBrowser: build a module fragment for programs.<name>
  # args: {
  #   name,
  #   package,
  #   profileId ? "default",
  #   # Settings overrides merged into base settings
  #   settingsExtra ? {},
  #   # Back-compat alias for settingsExtra (will be merged too)
  #   defaults ? {},
  #   # Extra extension packages to install
  #   addonsExtra ? [],
  #   # Extra native messaging hosts to add
  #   nativeMessagingExtra ? [],
  #   # Extra/override Firefox enterprise policies
  #   policiesExtra ? {},
  #   # Extra profile fields to merge (e.g., isDefault, bookmarks, search)
  #   profileExtra ? {},
  #   userChromeExtra ? "",
  #   # Whether to pin navbar to bottom via CSS (default true)
  #   bottomNavbar ? true,
  #   # When true, do not inject default userChrome tweaks (return to stock UI)
  #   vanillaChrome ? false,
  # }
  mkBrowser = {
    name,
    package,
    profileId ? "default",
    settingsExtra ? {},
    defaults ? {},
    addonsExtra ? [],
    nativeMessagingExtra ? [],
    policiesExtra ? {},
    profileExtra ? {},
    userChromeExtra ? "",
    bottomNavbar ? true,
    vanillaChrome ? false,
  }: let
    pid = profileId;
    mergedSettings = settings // defaults // settingsExtra;
    mergedNMH = nativeMessagingHosts ++ nativeMessagingExtra;
    mergedPolicies = policies // policiesExtra;
    # Soft migration hint: legacy downloads were stored under ~/dw.
    # When XDG Downloads differs, emit a one-time warning for the default browser.
    oldDownloadsDir = "${config.home.homeDirectory}/dw";
    isDefaultBrowser = let def = config.features.web.default or "floorp"; in def == name;
    needsMigration = (config.features.web.enable or false) && (dlDir != oldDownloadsDir) && isDefaultBrowser;
    userChromeInjected =
      if vanillaChrome
      then userChromeExtra
      else userChrome
        + (optionalString bottomNavbar bottomNavbarChrome)
        + hideSearchModeChip
        + hideUrlbarOneOffs
        + hideSearchBarWidget
        + userChromeExtra;

    profileBase = {
      isDefault = true;
      extensions = {packages = (addons.common or []) ++ addonsExtra;};
      settings = mergedSettings;
      userChrome = userChromeInjected;
      # Clamp Tridactyl overlay sizes globally via userContent.css
      userContent = tridactylUserContent;
      inherit extraConfig;
    };
    profile = profileBase // profileExtra;
  in {
    programs = {
      "${name}" = {
        enable = true;
        inherit package;
        nativeMessagingHosts = mergedNMH;
        profiles = {
          "${pid}" = profile;
        };
        policies = mergedPolicies;
      };
    };
    warnings = lib.optional needsMigration (
      "Browser downloads directory moved to XDG Downloads. "
      + "Consider migrating from " + oldDownloadsDir + " to " + dlDir + "."
    );
  };
}
