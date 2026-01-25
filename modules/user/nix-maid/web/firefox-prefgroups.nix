{ lib, ... }:
rec {
  prefgroups = {
    base = {
      "browser.aboutConfig.showWarning" = false;
      "browser.startup.homepage_override.mstone" = "ignore";
      # "browser.startup.homepage" = "about:newtab";
      # "browser.newtab.preload" = false;

      # Show whole url
      "browser.urlbar.trimURLs" = false;

      # disable disk cache to preserve ssd
      "browser.cache.disk.enable" = false;
      "browser.sessionstore.interval" = 6000000;

      "widget.gtk.overlay-scrollbars.enabled" = false;

      # disable the nag icon in the corner
      "browser.tabs.firefox-view" = false;

      # disable plugin signing requirements
      "xpinstall.signatures.required" = false;
      "xpinstall.whitelist.required" = false;

      # disable csd
      "browser.tabs.inTitlebar" = 0;

      # use portal filepicker
      "widget.use-xdg-desktop-portal.file-picker" = 1;
    };

    security = {
      disable-form-autofill = {
        "browser.formfill.enable" = false;
        "extensions.formautofill.available" = "off";
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.available" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "extensions.formautofill.heuristics.enabled" = false;
      };

      disable-password-manager = {
        # Just in case its somehow enabled
        "security.ask_for_password" = 1;
        "security.password_lifetime" = 0;

        "signon.autofillForms" = false;
        "signon.formlessCapture.enabled" = false;

        "signon.rememberSignons" = false;
      };

      disable-cross-origin-auth-dialogs = {
        "network.auth.subresource-http-auth-allow" = 1;
      };

      disable-tls-mitm = {
        "security.ssl.require_safe_negotiation" = true;
        "security.tls.enable_0rtt_data" = false;
      };

      certificate = {
        validity = {
          "security.OCSP.enabled" = 1;
          "security.OCSP.require" = true;

          # CRLite (external service, any concernes unknown?) - certificate revocation
          "security.remote_settings.crlite_filters.enabled" = true;
          "security.pki.crlite_mode" = 2;

          # Firefox certificate blocklist
          "extensions.blocklist.enabled" = true;
        };

        # Disabled local MITM on certificates (Fiddler, AV, etc)
        enforcement = {
          "security.pki.sha1_enforcement_level" = 1;
          "security.cert_pinning.enforcement_level" = 2;
        };
      };

      # HTTP resources on HTTPS pages
      disable-http-resources = {
        "security.mixed_content.block_display_content" = false;
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_send_http_background_request" = false;
      };

      # Display more and better warning information (+ advanced info) for SSL
      ssl-ui = {
        "security.ssl.treat_unsafe_negotiation_as_broken" = true;
        "browser.ssl_override_behavior" = 1;
        "browser.xul.error_pages.expert_bad_cert" = true;
      };

      # No real reason to ever have this enabled
      disable-uitour = {
        "browser.uitour.enabled" = false;
        "browser.uitour.url" = "";
      };

      disable-middlemouse-paste = {
        "middlemouse.paste" = false;

        # With this one enabled, just middleclicking will go to the url in clipboard
        "middlemouse.contentLoadURL" = false;
      };

      # Punycode can be used to make fake domain names
      show-punycode = {
        "network.IDN_show_punycode" = true;
      };

      use-pdfjs = {
        "pdfjs.disabled" = false;
        "pdfjs.enableScripting" = false;
      };

      # Applies to cross origin permission requests
      disable-permission-delegation = {
        "permissions.delegation.enabled" = false;
      };

      # Only allow extionsions installed in profile
      lockdown-extension-dirs = {
        "extensions.enabledScopes" = 5;
        "extensions.autoDisableScopes" = 15;
      };

      always-ask-extension-install = {
        "extensions.postDownloadThirdPartyPrompt" = false;
      };

      # UNTESTED/UNKNOWN
      remove-webchannel-whitelist = {
        "webchannel.allowObject.urlWhitelist" = "";
      };

      # Remove extra permissions on mozilla pages
      remove-mozilla-permissions = {
        "permissions.manager.defaultsUrl" = "";
      };

      # Enable ETP Strict mode
      # Enable Total Cookie Protection (xss cookie protection)
      etp-strict = {
        "browser.contentblocking.category" = "strict";

        # Disable compat features
        # "privacy.antitracking.enableWebcompat" = false;
      };

      partition-serviceworkers = {
        "privacy.partition.serviceWorkers" = true;
      };

      partition-storage = {
        "privacy.partition.always_partition_third_party_non_cookie_storage" = true;
        "privacy.partition.always_partition_third_party_non_cookie_storage.exempt_sessionstorage" = true;
      };

      disable-system-ui = {
        "browser.display.use_system_colors" = false;
        "widget.non-native-theme.enabled" = true;
      };

      disable-webgl = {
        "webgl.disabled" = true;
      };

      disable-sessionrestore = {
        "browser.sessionstore.resume_from_crash" = false;
      };

      # Yoinked from arkenfox/user.js
      enforce-defaults = {
        "network.http.referer.spoofSource" = false;
        "dom.targetBlankNoOpener.enabled" = true;
        "privacy.window.name.update.enabled" = true;
        "dom.storage.next_gen" = true;
        "privacy.firstparty.isolate" = false;
        "extensions.webcompat.enable_shims" = true;
        "security.tls.version.enable-deprecated" = false;
        "extensions.webcompat-reporter.enabled" = false;
      };

      disable-js-jit = {
        "javascript.options.baselinejit" = false;
        "javascript.options.ion" = false;
      };

      disable-wasm = {
        "javascript.options.wasm" = false;
        "javascript.options.asmjs" = false;
      };
    };

    privacy = {
      disable-activity-stream = {
        "browser.newtabpage.activity-stream.telemetry" = false;
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.feeds.snippets" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfg.addons" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfg.features" = false;

        # Remove default sites
        "browser.newtabpage.activity-stream.default.sites" = "";
      };

      geolocation = {
        # Use mozilla's location provider over google's
        "geo.provider.network.url" =
          "https://location.services.mozilla.com/v1/geolocate?key=%MOZILLA_API_KEY%";

        # Disable OS geolocation services
        "geo.provider.use_gpsd" = false;

        # Disable region
        "browser.region.network.url" = "";
        "browser.region.update.enabled" = false;

        # Languages
        "intl.accept_languages" = "en-US, en";
        "javascript.use_us_english_locale" = true;
      };

      # Uses google analytics
      disable-addon-reccomendation = {
        "extensions.getAddons.showPane" = false;
        "extensions.htmlaboutaddons.recommendations.enabled" = false;
        "browser.discovery.enabled" = false;
      };

      disable-mozilla-telemetry = {
        "datareporting.policy.dataSubmissionEnabled" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.server" = "data:,";
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.newProfilePing.enabled" = false;
        "toolkit.telemetry.shutdownPingSender.enabled" = false;
        "toolkit.telemetry.updatePing.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.firstShutdownPing.enabled" = false;
        "toolkit.telemetry.coverage.opt-out" = true;
        "toolkit.coverage.opt-out" = true;
        "toolkit.coverage.endpoint.base" = "";
        "browser.ping-centre.telemetry" = false;
        "toolkit.telemetry.pioneer-new-studies-available" = false;

        "devtools.onboarding.telemetry.logged" = false;
      };

      disable-studies = {
        "app.shield.optoutstudies.enabled" = false;
        "app.normandy.enabled" = false;
        "app.normandy.api_url" = "";
      };

      disable-crash-reports = {
        "breakpad.reportURL" = "";
        "browser.tabs.crashReporting.sendReport" = false;
        "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
      };

      # Impact unchecked (public wifi captive portals)
      disable-captive-portals = {
        "captivedetect.canonicalURL" = "";
        "network.captive-portal-service.enabled" = false;
        "network.connectivity-service.enabled" = false;
      };

      # Calls back to google
      disable-safebrowsing = {
        "browser.safebrowsing.downloads.enabled" = false;

        # May be blocked by `downloads.enabled` already
        "browser.safebrowsing.downloads.remote.enabled" = false;
        "browser.safebrowsing.downloads.remote.url" = "";
        "browser.safebrowsing.downloads.remote.block_potentially_unwanted" = false;
        "browser.safebrowsing.downloads.remote.block_uncommon" = false;

        "browser.safebrowsing.malware.enabled" = false;
        "browser.safebrowsing.phishing.enabled" = false;
      };

      disable-speculative-connections = {
        "browser.places.speculativeConnect.enabled" = false;
        "browser.urlbar.speculativeConnect.enabled" = false;
      };

      disable-search-corrections = {
        "keyword.enabled" = false;

        # Adds www. or .com
        "browser.fixup.alternate.enabled" = false;
      };

      disable-search-suggestions = {
        "browser.search.suggest.enabled" = false;
        "browser.urlbar.suggest.searches" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
      };

      disable-dns-query-leak = {
        "browser.urlbar.dnsResolveSingleWordsAfterSearch" = false;
      };

      webrtc = {
        # Untrusted = no camera/mic granted
        hide-ip-untrusted = {
          "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
          "media.peerconnection.ice.default_address_only" = true;
        };

        hide-ip-trusted = {
          "media.peerconnection.ice.no_host" = true;
        };

        disable = {
          "media.peerconnection.enabled" = false;
          "media.navigator.enabled" = false;
        };
      };

      disable-accessability = {
        "accessibility.force_disabled" = 1;
      };

      # Intended for analytics
      disable-beacon = {
        "beacon.enabled" = false;
      };

      # Clear cookies on exit
      ephemeral-cookies = {
        "network.cookie.lifetimePolicy" = 2;
        "network.cookie.thirdparty.sessionOnly" = true;
        "network.cookie.thirdparty.nonsecureSessionOnly" = true;
      };

      sanitize-on-shutdown = {
        "privacy.sanitize.sanitizeOnShutdown" = true;
        "privacy.clearOnShutdown.cache" = true;
        "privacy.clearOnShutdown.downloads" = true;
        "privacy.clearOnShutdown.formdata" = true;
        "privacy.clearOnShutdown.history" = true;
        "privacy.clearOnShutdown.sessions" = true;

        "privacy.cpd.cache" = true;
        "privacy.cpd.formdata" = true;
        "privacy.cpd.history" = true;
        "privacy.cpd.sessions" = true;

        # Disabled because they have to be explicitly allowed per site
        "privacy.clearOnShutdown.offlineApps" = false;
        "privacy.clearOnShutdown.cookies" = false;

        "privacy.cpd.offlineApps" = false;
        "privacy.cpd.cookies" = false;

        "privacy.sanitize.timeSpan" = 0;
      };

      # Note: breaks dark mode
      resist-fingerprinting = {
        "privacy.resistFingerprinting" = true;
      };

      # Snap window resizing (tor browser does this)
      letterboxing = {
        "privacy.resistFingerprinting.letterboxing" = true;
      };

      disable-referrer-headers = {
        "network.http.sendRefererHeader" = 1; # send when clicking links but not bg loads
        "network.http.referrer.XOriginTrimmingPolicy" = 1; # remove query string but send
        "network.http.referrer.XOriginPolicy" = 1; # base domains must match
      };

      disable-referrer-strict = {
        "network.http.sendRefererHeader" = 0; # never send
      };
    };

    misc = {
      disable-mozilla-account = {
        "identity.fxaccounts.enabled" = false;
      };

      disable-pocket = {
        "extensions.pocket.enabled" = false;
      };

      container-tabs = {
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;

        # Make default + tab action
        # "privacy.userContext.newTabContainerOnLeftClick.enabled" = true;
      };

      # Prefetching may make sites faster, but also causes unwanted background downloads
      disable-prefetching = {
        "network.prefetch-next" = false;
        "network.dns.disablePrefetch" = true;
        "network.predictor.enabled" = false;
        "network.predictor.enable-prefetch" = false;
        "network.http.speculative-parallel-limit" = 0;
      };

      disable-drm = {
        "media.eme.enabled" = false;
      };

      disable-autoplay = {
        "media.autoplay.default" = 5;
        "media.autoplay.blocking_policy" = 2;
      };

      # Disallow sites resizing or moving the browser window
      disable-window-manipulation = {
        "dom.disable_window_move_resize" = true;
      };

      limited-popups = {
        "dom.disable_open_during_load" = false;
        "dom.popup_allowed_events" = "click dblclick mousedown pointerdown";
      };

      ask-downloads = {
        "browser.download.useDownloadDir" = false;

        # Disable panel opening, lumped together
        "browser.download.alwaysOpenPanel" = false;
      };

      ask-new-mimetypes = {
        "browser.download.always_ask_before_handling_new_types" = true;
      };

      # Disable js opening new windows
      always-newtab = {
        "browser.link.open_newwindow" = 3;
        "browser.link.open_newwindow.restriction" = 0;
      };

      # Stop save dialog delay
      reduce-dialog-delay = {
        # Still 500 to be less annoying, while avoiding click hijacking
        "security.dialog_enable_delay" = 500;
      };

      # Handled by nix already
      disable-extension-updates = {
        "extensions.update.enabled" = false;
        "extensions.update.autoUpdateDefault" = false;
      };

      always-show-downloads = {
        "browser.download.autohideButton" = false;
      };

      bookmark-new-tab = {
        "browser.tabs.loadBookmarksInTabs" = true;
      };

      urlbar-openintab = {
        "browser.urlbar.openintab" = true;
      };

      enable-userchrome = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };

      restore-pages = {
        "browser.startup.page" = 3;
      };

      hide-bookmark-bar = {
        "browser.toolbars.bookmarks.visibility" = "never";
      };

      default-dark-theme = {
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
        "layout.css.prefers-color-scheme.content-override" = 0;
      };
    };
  };

  modules = with prefgroups; {
    base =
      { }
      // base
      // misc.disable-mozilla-account
      // misc.container-tabs
      // privacy.disable-activity-stream
      // privacy.disable-addon-reccomendation
      // privacy.disable-mozilla-telemetry
      // privacy.disable-studies
      // privacy.disable-crash-reports
      // privacy.disable-safebrowsing
      // privacy.disable-dns-query-leak
      // security.disable-form-autofill
      // security.disable-password-manager
      // security.disable-cross-origin-auth-dialogs
      // security.disable-tls-mitm
      // security.certificate.validity
      // security.certificate.enforcement
      // security.ssl-ui
      // privacy.webrtc.hide-ip-untrusted
      // misc.disable-drm
      // misc.disable-autoplay
      // misc.disable-window-manipulation
      // misc.limited-popups
      // privacy.disable-beacon
      // security.disable-uitour
      // security.disable-middlemouse-paste
      // security.show-punycode
      // security.use-pdfjs
      // security.disable-permission-delegation
      // misc.ask-downloads
      // misc.ask-new-mimetypes
      // security.lockdown-extension-dirs
      // security.always-ask-extension-install
      // security.remove-mozilla-permissions
      // security.partition-serviceworkers
      // misc.always-newtab
      // misc.reduce-dialog-delay
      // security.enforce-defaults
      // misc.bookmark-new-tab
      // misc.urlbar-openintab
      // misc.disable-pocket
      // misc.always-show-downloads
      // misc.enable-userchrome
      // misc.hide-bookmark-bar
      // misc.default-dark-theme;

    minor-1 =
      { }
      // misc.disable-prefetching
      // privacy.disable-captive-portals
      // privacy.disable-search-suggestions
      // security.disable-http-resources
      // security.remove-webchannel-whitelist
      // security.etp-strict;

    minor-2 =
      { }
      // security.disable-webgl
      // privacy.ephemeral-cookies
      // privacy.sanitize-on-shutdown
      // security.disable-sessionrestore;

    annoying =
      { }
      // privacy.resist-fingerprinting
      // security.disable-js-jit
      // security.disable-wasm
      // privacy.webrtc.hide-ip-trusted
      // privacy.ephemeral-cookies
      // privacy.webrtc.disable
      // privacy.disable-referrer-strict
      // privacy.disable-accessability;

    trusted = { } // modules.base // modules.minor-1;

    general =
      { }
      // modules.base
      // modules.minor-1
      // modules.minor-2
      // privacy.disable-referrer-headers
      // privacy.webrtc.disable;

    schizo = modules.general // modules.annoying;
  };

  mkUserJs =
    prefs:
    lib.concatStrings (
      lib.mapAttrsToList (name: value: ''
        user_pref("${name}", "${builtins.toJSON value}");
      '') prefs
    );
}
