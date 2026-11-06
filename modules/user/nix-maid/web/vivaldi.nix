{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.web.vivaldi;
  webEnabled = config.lib.neg.enabled "web";
  guiEnabled = config.lib.neg.enabled "gui";
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };

  # Extension install strategy — ExtensionInstallForcelist (force-installed via
  # managed policy). The browser itself downloads and (re)installs SurfingKeys +
  # Tampermonkey from the Chrome Web Store on every startup, so there is no
  # file-copying into the profile and no Preferences surgery — nothing to race
  # with, nothing to clobber. Previous approaches (--load-extension, file
  # injection via a systemd oneshot, ExtensionSettings normal_installed) all
  # lost the extensions eventually: a running Vivaldi rewrites Preferences from
  # its in-memory state and purges orphaned extension dirs. Force-installed
  # extensions cannot be removed by the user (only disabled); DevTools stays
  # available via DeveloperToolsAvailability=1 below.

  # Vivaldi bundles its own libffmpeg.so with all codecs (proprietary browser).
  # nixpkgs proprietaryCodecs=true replaces it with an outdated chromium-codecs-ffmpeg-extra
  # snap that lacks av_dynamic_hdr_smpte2094_app5_to_t35 → symbol lookup error.
  # We keep proprietaryCodecs=false (no snap download), but vivaldi-bin has libffmpeg.so
  # as DT_NEEDED and its RUNPATH only covers opt/vivaldi/lib/, not opt/vivaldi/ where
  # the bundled libffmpeg.so lives. So we patch the RUNPATH to include opt/vivaldi/.

in
{
  config = lib.mkIf (webEnabled && guiEnabled && cfg.enable) {

    environment.systemPackages = [
      (onDemand {
        name = "vivaldi";
        attr = "vivaldi";
      }) # Vivaldi browser (Chromium-based, patched build), built on first use
      (pkgs.makeDesktopItem {
        name = "vivaldi-stable";
        desktopName = "Vivaldi";
        exec = "vivaldi %U";
        icon = "vivaldi";
        categories = [
          "Network"
          "WebBrowser"
        ];
        mimeTypes = [
          "application/pdf"
          "application/rdf+xml"
          "application/rss+xml"
          "application/xhtml+xml"
          "application/xhtml_xml"
          "application/xml"
          "image/gif"
          "image/jpeg"
          "image/png"
          "image/webp"
          "text/html"
          "text/xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
        ];
      })
    ];

    # BROWSER/DEFAULT_BROWSER resolve the launcher by name; referencing a store
    # path here would pull the browser back into system-path.
    environment.sessionVariables = {
      BROWSER = lib.mkForce "vivaldi";
      DEFAULT_BROWSER = lib.mkForce "vivaldi";
    };

    # Chromium managed policies — most Chromium-based browsers read from here.
    # Vivaldi may or may not pick them up depending on the version (8.x sometimes ignores it).
    programs.chromium = {
      enable = true;
      extraOpts = {
        "PasswordManagerEnabled" = false;
        "BuiltInNotificationsSettings" = 2; # Blocked
        "DefaultPopupsSetting" = 2; # Block popup windows (window.open)
        "MetricsReportingEnabled" = false;
        "SafeBrowsingProtectionLevel" = 1; # Standard
        "SearchSuggestEnabled" = false;
        "SyncDisabled" = false;
        "ShowHomeButton" = true;
        "BookmarkBarEnabled" = false;
        # Force-installed extensions (SurfingKeys/Tampermonkey) make DevTools
        # report "Your organization blocked DevTools on this page" — allow it.
        # Chrome 114+ semantics: 0 = disallowed for force-installed extensions
        # (default), 1 = allowed everywhere, 2 = disallowed everywhere.
        "DeveloperToolsAvailability" = 1; # Allowed everywhere (incl. force-installed extensions)
        # Force-install SurfingKeys/Tampermonkey: Vivaldi downloads and
        # self-heals them on every startup (root fix for recurring
        # "extensions disappeared" — no profile file injection).
        "ExtensionInstallForcelist" = [
          "gfbliohnnapiefjpjlpjnehglfpaknnc;https://clients2.google.com/service/update2/crx" # SurfingKeys (vim-like keybindings)
          "dhdgffkkebhmkfjojejmpbldmpobfkfo;https://clients2.google.com/service/update2/crx" # Tampermonkey (userscript manager)
          "mnjggcdmjocbbbhaepdhchncahnbgone;https://clients2.google.com/service/update2/crx" # SponsorBlock (skip YouTube sponsors/intros)
          "hlepfoohegkhhmjieoechaddaejaokhf;https://clients2.google.com/service/update2/crx" # Refined GitHub (streamline GitHub UI)
          "gebbhagfogifgggkldgodflihgfeippi;https://clients2.google.com/service/update2/crx" # Return YouTube Dislike
          "dnhpnfgdlenaccegplpojghhmaamnnfp;https://clients2.google.com/service/update2/crx" # Augmented Steam (IsThereAnyDeal price history)
        ];

        # Default font: Iosevka everywhere (matches system-wide fontconfig default)
        "StandardFontFamily" = "Iosevka Proportional";
        "SerifFontFamily" = "Iosevka Proportional";
        "SansSerifFontFamily" = "Iosevka Proportional";
        "FixedFontFamily" = "Iosevka Proportional";
        "DefaultFontSize" = 15;
        "DefaultFixedFontSize" = 13;
      };
    };

    # Vivaldi-specific managed policies.
    # Vivaldi 8.x reads from /etc/vivaldi/policies/managed/ but sometimes ignores
    # /etc/chromium/policies/managed/.  Duplicate the relevant policies here.

    environment.etc."vivaldi/policies/managed/vivaldi-fonts.json" = {
      mode = "0444";
      text = builtins.toJSON {
        StandardFontFamily = "Iosevka Proportional";
        SerifFontFamily = "Iosevka Proportional";
        SansSerifFontFamily = "Iosevka Proportional";
        FixedFontFamily = "Iosevka Proportional";
        DefaultFontSize = 15;
        DefaultFixedFontSize = 13;
      };
    };

    environment.etc."vivaldi/policies/managed/devtools.json" = {
      mode = "0444";
      text = builtins.toJSON {
        DeveloperToolsAvailability = 1; # Allowed everywhere (incl. force-installed extensions)
      };
    };

    environment.etc."vivaldi/policies/managed/extensions.json" = {
      mode = "0444";
      text = builtins.toJSON {
        ExtensionInstallForcelist = [
          "gfbliohnnapiefjpjlpjnehglfpaknnc;https://clients2.google.com/service/update2/crx" # SurfingKeys (vim-like keybindings)
          "dhdgffkkebhmkfjojejmpbldmpobfkfo;https://clients2.google.com/service/update2/crx" # Tampermonkey (userscript manager)
          "mnjggcdmjocbbbhaepdhchncahnbgone;https://clients2.google.com/service/update2/crx" # SponsorBlock (skip YouTube sponsors/intros)
          "hlepfoohegkhhmjieoechaddaejaokhf;https://clients2.google.com/service/update2/crx" # Refined GitHub (streamline GitHub UI)
          "gebbhagfogifgggkldgodflihgfeippi;https://clients2.google.com/service/update2/crx" # Return YouTube Dislike
          "dnhpnfgdlenaccegplpojghhmaamnnfp;https://clients2.google.com/service/update2/crx" # Augmented Steam (IsThereAnyDeal price history)
        ];
      };
    };

    # Block popup windows (window.open) and web notifications site-wide.
    # The same settings exist under /etc/chromium via programs.chromium.extraOpts,
    # but Vivaldi 8.x sometimes ignores that dir — duplicate them here where
    # Vivaldi reliably reads policies. BuiltInNotificationsSettings is the current
    # name, DefaultNotificationsSetting the older one; set both.
    environment.etc."vivaldi/policies/managed/popups.json" = {
      mode = "0444";
      text = builtins.toJSON {
        DefaultPopupsSetting = 2; # Block popup windows (window.open)
        DefaultNotificationsSetting = 2; # Block web notifications (older name)
        BuiltInNotificationsSettings = 2; # Block web notifications (current name)
      };
    };

    # Browser UI font override lives in the active CSS mods directory
    # (~/.config/vivaldi/css-mods/ui-font.css → files/vivaldi/ui-font.css,
    # symlinked in modules/user/nix-maid/web/browsing.nix). It sets
    # Iosevka Proportional across the whole browser chrome (Vivaldi's common.css
    # hardcodes Cantarell/Noto Sans for the Linux UI font; the * rule with
    # !important outranks it). Previously this was /etc/vivaldi/custom-ui/
    # (environment.etc, manual Settings activation) — but the oneshot below
    # re-asserts css_ui_mods_directory to ~/.config/vivaldi/css-mods at login,
    # so that directory was never active. One mechanism only now.

    # Vivaldi Preferences surgery, re-applied at login: a running Vivaldi
    # rewrites Preferences from memory on exit, so the oneshot below must run
    # before the browser starts. One script (vivaldi-prefs.py) loads and dumps
    # the profile once and performs all five fixes in order:
    #   1. point the CSS mods dir at the profile mods folder so the compact
    #      address-bar mod loads (css_ui_mods_directory is empty by default and
    #      "Allow for using CSS modifications" must be on); also re-assert the Neg
    #      theme and the hidden panel bar, which Vivaldi drops from memory
    #      (theme reset → grey UI; barVisible=true → the left panel reappears);
    #   2. disable "UI Auto-hide" (Vivaldi 7.9+): toolbars slide out on hover –
    #      reads as random popups. Force the master switch and per-toolbar flags
    #      off; bars keep their manual visibility;
    #   3. unbind Ctrl+W from close-tab so the emacs keys reach web pages (dsh web
    #      composer/terminal; xterm forwards it to zsh as C-w);
    #   4. bind Ctrl+G to close-tab. Vivaldi ships Ctrl+G as "Find Next in Page",
    #      so the script frees that key; Ctrl+F4 keeps working too;
    #   5. set the new tab to the dark newtab extension (vivaldi.tabs.new_page.link
    #      = extension), so Ctrl+T no longer opens the start page and its white
    #      first frame (files/vivaldi-newtab, loaded via --load-extension).
    # The profile fixer is a Rust package now (packages/vivaldi-prefs): the
    # unit needs no interpreter, and the profile path comes from $HOME.
    systemd.user.services.vivaldi-prefs = {
      description = "Re-assert Vivaldi preferences (CSS mods dir, UI auto-hide, Ctrl+W free, Ctrl+G closes the tab, dark new tab)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe pkgs.neg.vivaldi-prefs;
      };
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };

  };
}
