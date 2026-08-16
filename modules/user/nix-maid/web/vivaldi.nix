{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.features.web.vivaldi;
  webEnabled = config.lib.neg.enabled "web";
  guiEnabled = config.lib.neg.enabled "gui";

  # Extension install strategy — ExtensionInstallForcelist (force-installed via
  # managed policy). The browser itself downloads and (re)installs SurfingKeys +
  # Tampermonkey from the Chrome Web Store on every startup, so there is no
  # file-copying into the profile and no Preferences surgery — nothing to race
  # with, nothing to clobber. Previous approaches (--load-extension, file
  # injection via a systemd oneshot, ExtensionSettings normal_installed) all
  # lost the extensions eventually: a running Vivaldi rewrites Preferences from
  # its in-memory state and purges orphaned extension dirs. Force-installed
  # extensions cannot be removed by the user (only disabled); DevTools stays
  # available via DeveloperToolsAvailability=0 below.

  # Vivaldi bundles its own libffmpeg.so with all codecs (proprietary browser).
  # nixpkgs proprietaryCodecs=true replaces it with an outdated chromium-codecs-ffmpeg-extra
  # snap that lacks av_dynamic_hdr_smpte2094_app5_to_t35 → symbol lookup error.
  # We keep proprietaryCodecs=false (no snap download), but vivaldi-bin has libffmpeg.so
  # as DT_NEEDED and its RUNPATH only covers opt/vivaldi/lib/, not opt/vivaldi/ where
  # the bundled libffmpeg.so lives. So we patch the RUNPATH to include opt/vivaldi/.
  vivaldi-pkg = pkgs.vivaldi.override {
    # Wayland Ozone + Skia renderer (stable colors, no Vulkan video-overlay bug) +
    # VA-API hardware video decoding on AMD (radeonsi). Vulkan is disabled — it causes
    # a white-screen video overlay on Wayland (Chromium bug).
    # --force-color-profile=srgb is needed for fullscreen: Hyprland direct_scanout
    # bypasses compositor color management (cm=auto), so the GPU outputs in native
    # display gamut.  sRGB clamp keeps colors consistent windowed ↔ fullscreen.
    # NOTE: WaylandWpColorManagerV1 used to be disabled here too (wp_color_manager_v1
    # handshake with Hyprland cm=auto can fail on AMD → overbright gamma), but disabling
    # BOTH Vulkan and WaylandWpColorManagerV1 breaks the DevTools frontend: F12 opens an
    # empty/hung window (verified 2026-08-17 — each flag alone is harmless, together they
    # hang the devtools renderer and can crash the browser). So only Vulkan stays disabled
    # (it is needed for the white-screen video overlay bug). If fullscreen gamma drift
    # reappears, fix it via Hyprland color management instead of this flag.
    # VivaldiCssMods: the "Allow for using CSS modifications" experiment flag.
    # It is a native runtime feature flag (vivaldi://experiments → getAllFeatureFlags),
    # NOT a Preferences key — Vivaldi can drop the toggle on restart/upgrade and
    # then silently ignores css_ui_mods_directory (all usercss stops applying).
    # Forcing it via --enable-features keeps the CSS mods active unconditionally.
    # --remote-debugging-port=9222: CDP endpoint for inspecting the browser's own
    # DOM (navbar/toolbars) while debugging usercss selectors. Loopback-only.
    # --remote-allow-origins=*: CDP rejects WebSocket handshakes from unknown
    # origins unless allowed; the debugger connects from a local script.
    commandLineArgs = "--ozone-platform-hint=wayland --force-color-profile=srgb --enable-features=UseSkiaRenderer,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,VivaldiCssMods --disable-features=Vulkan --remote-debugging-port=9222 --remote-allow-origins=*";
    proprietaryCodecs = false;
  };

  # Patch RUNPATH on vivaldi-bin so the NEEDED libffmpeg.so (bundled, opt/vivaldi/)
  # is findable. nixpkgs's libPath only adds opt/vivaldi/lib but Vivaldi ships
  # libffmpeg.so in opt/vivaldi/ directly.
  vivaldi-fixed = vivaldi-pkg.overrideAttrs (old: {
    buildPhase = old.buildPhase + ''
      patchelf --add-rpath "$out/opt/vivaldi" opt/vivaldi/vivaldi-bin
    '';
  });

in
{
  config = mkIf (webEnabled && guiEnabled && cfg.enable) {

    environment.systemPackages = [
      vivaldi-fixed # Vivaldi browser (Chromium-based, with Wayland flags, patched libffmpeg.so rpath)
    ];

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
        "DeveloperToolsAvailability" = 0; # Allowed everywhere
        # Force-install SurfingKeys/Tampermonkey: Vivaldi downloads and
        # self-heals them on every startup (root fix for recurring
        # "extensions disappeared" — no profile file injection).
        "ExtensionInstallForcelist" = [
          "gfbliohnnapiefjpjlpjnehglfpaknnc;https://clients2.google.com/service/update2/crx" # SurfingKeys (vim-like keybindings)
          "dhdgffkkebhmkfjojejmpbldmpobfkfo;https://clients2.google.com/service/update2/crx" # Tampermonkey (userscript manager)
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
        DeveloperToolsAvailability = 0; # Allowed everywhere (blocked by force-installed extensions otherwise)
      };
    };

    environment.etc."vivaldi/policies/managed/extensions.json" = {
      mode = "0444";
      text = builtins.toJSON {
        ExtensionInstallForcelist = [
          "gfbliohnnapiefjpjlpjnehglfpaknnc;https://clients2.google.com/service/update2/crx" # SurfingKeys (vim-like keybindings)
          "dhdgffkkebhmkfjojejmpbldmpobfkfo;https://clients2.google.com/service/update2/crx" # Tampermonkey (userscript manager)
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

    # Browser UI font override via Vivaldi Custom UI Modifications.
    # Managed policies above only affect webpage fonts, not the browser chrome.
    # This CSS overrides the hardcoded Linux UI font-family in Vivaldi's common.css
    # (Cantarell / Noto Sans → Iosevka).
    # To activate: enable "Allow for using CSS modifications" in vivaldi://experiments,
    # then set Settings → Appearance → Custom UI Modifications → /etc/vivaldi/custom-ui/
    environment.etc."vivaldi/custom-ui/vivaldi-ui-font.css" = {
      mode = "0444";
      text = ''
        /* Override Vivaldi browser UI font on Linux — Iosevka, bigger and bolder */
        *, *:before, *:after {
          font-family: "Iosevka Proportional" !important;
          font-size: 15px !important;
          font-weight: 600 !important;
        }
      '';
    };

    # Point Vivaldi's CSS mods directory at the profile mods folder so the
    # compact address bar mod loads. The css_ui_mods_directory pref is empty by
    # default ("Allow for using CSS modifications" must be enabled); setting it
    # via the Preferences file is the declarative way (Settings → Appearance →
    # Custom UI Modifications would do the same). Vivaldi keeps user-set prefs,
    # so this oneshot only rewrites the file when the value is missing/wrong.
    # Also re-asserts the Neg theme and the hidden panel bar: both are plain
    # Preferences values that Vivaldi rewrites from memory on exit/restart and
    # can drop (theme reset → grey/black-and-white UI; barVisible=true → the
    # left panel reappears). Same caveat as the auto-hide service below:
    # re-apply at login.
    systemd.user.services.vivaldi-css-mods-pref =
      let
        prefScript = pkgs.writeText "vivaldi-css-mods-pref.py" ''
          import json, os, sys
          prefs = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
          if not os.path.isfile(prefs):
              sys.exit(0)
          with open(prefs) as f:
              p = json.load(f)

          neg_theme = "6265ce0d-0cec-40c1-8002-ef5c1f962c7a"
          changed = False

          a = p.setdefault("vivaldi", {}).setdefault("appearance", {})
          target = os.path.expanduser("~/.config/vivaldi/css-mods")
          if a.get("css_ui_mods_directory") != target:
              a["css_ui_mods_directory"] = target
              changed = True

          # Neg dark theme must stay selected; if it was dropped, the browser
          # chrome falls back to the default grey theme.
          th = p.setdefault("vivaldi", {}).setdefault("themes", {})
          if th.get("current") != neg_theme:
              th["current"] = neg_theme
              changed = True
          if th.get("current_private") != neg_theme:
              th["current_private"] = neg_theme
              changed = True

          # Hide the panel bar by default for new windows (was visible again
          # after the pref reset).
          wd = p.setdefault("vivaldi", {}).setdefault("panels", {}).setdefault("window_defaults", {})
          if wd.get("barVisible") is not False:
              wd["barVisible"] = False
              changed = True
          if wd.get("contentVisible") is not False:
              wd["contentVisible"] = False
              changed = True

          if changed:
              with open(prefs, "w") as f:
                  json.dump(p, f, indent=1)
              print("css_ui_mods_directory, Neg theme and hidden panel bar re-asserted")
        '';
      in
      {
        description = "Point Vivaldi CSS mods at the profile mods folder; re-assert Neg theme and hidden panel";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe' pkgs.python3 "python3"} ${prefScript}";
        };
        after = [ "graphical-session.target" ];
        wants = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
      };

    # Disable "UI Auto-hide" (Vivaldi 7.9+): toolbars (Tab Bar, Panel, Bookmarks
    # Bar, Status Bar) slide out when the mouse hovers the window edge — reads as
    # random "popups". Force the master switch and the per-toolbar flags off so
    # nothing pops on hover; bars keep their manual visibility (e.g. tab bar stays
    # hidden via vivaldi.tabs.visible). Same caveat as the css-mods service:
    # Vivaldi rewrites Preferences from memory on exit, so re-apply at login.
    systemd.user.services.vivaldi-auto-hide-pref =
      let
        prefScript = pkgs.writeText "vivaldi-auto-hide-pref.py" ''
          import json, os, sys
          prefs = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
          if not os.path.isfile(prefs):
              sys.exit(0)
          with open(prefs) as f:
              p = json.load(f)
          ah = p.setdefault("vivaldi", {}).setdefault("auto_hide", {})
          target = {
              "enabled": False,  # master switch — off = no hover popups
              "panel": False,
              "tab_bar": False,
              "bookmarks_bar": False,
              "status_bar": False,
              "in_fullscreen": False,  # also off in fullscreen (address bar pops on hover otherwise)
          }
          changed = False
          for k, v in target.items():
              if ah.get(k) != v:
                  ah[k] = v
                  changed = True
          if changed:
              with open(prefs, "w") as f:
                  json.dump(p, f, indent=1)
              print("UI Auto-hide disabled:", target)
        '';
      in
      {
        description = "Disable Vivaldi UI Auto-hide (hover popups)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe' pkgs.python3 "python3"} ${prefScript}";
        };
        after = [ "graphical-session.target" ];
        wants = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
      };

  };
}
