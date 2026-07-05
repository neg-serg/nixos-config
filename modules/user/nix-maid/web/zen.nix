{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  n = neg;
  cfg = config.features.web.zen;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;
  homeDir = config.users.users.neg.home;
  zenLink = "${homeDir}/.zen";
  zenTarget = "${homeDir}/.config/zen";

  applyZenConfig = pkgs.writeShellScript "apply-zen-config" ''
    set -euo pipefail
    STAGING="${homeDir}/.config/zen/config-staging"
    ZEN_DIR="$HOME/.zen"

    for profile_dir in "$ZEN_DIR"/*.default* "$ZEN_DIR"/*.default-release*; do
      [ -d "$profile_dir" ] || continue
      cp -f "$STAGING/user.js" "$profile_dir/user.js"
      mkdir -p "$profile_dir/chrome"
      cp -f "$STAGING/userChrome.css" "$profile_dir/chrome/userChrome.css"
      mkdir -p "$profile_dir/chrome/true-black-zen-mod"
      cp -f "$STAGING/true-black-zen-mod/theme.json" "$profile_dir/chrome/true-black-zen-mod/theme.json"
      cp -f "$STAGING/true-black-zen-mod/chrome.css" "$profile_dir/chrome/true-black-zen-mod/chrome.css"
    done
  '';
in
{
  config = lib.mkIf (webEnabled && guiEnabled && (cfg.enable or false)) (
    {
      environment.systemPackages = [
        pkgs.zen-browser
      ];

      environment.sessionVariables = {
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_DBUS_REMOTE = "1";
      };

      systemd.user.tmpfiles.rules = [
        "L+ ${zenLink} - - - - ${zenTarget}"
      ];

      systemd.user.services.apply-zen-config = {
        description = "Apply Zen browser user.js and chrome CSS to default profiles";
        after = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        unitConfig = {
          DefaultDependencies = "no";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${applyZenConfig}";
        };
      };
    }
    //
    (n.mkHomeFiles {
    ".config/zen/config-staging/user.js".text = ''
      user_pref("accessibility.typeaheadfind.flashbar", 0);
      user_pref("browser.bookmarks.addedImportButton", false);
      user_pref("browser.bookmarks.restore_default_bookmarks", false);
      user_pref("browser.download.dir", "${homeDir}/dw");
      user_pref("extensions.webextensions.restrictedDomains", "");
      user_pref("general.warnOnAboutConfig", false);
      user_pref("gfx.color_management.enabled", true);
      user_pref("gfx.color_management.enablev4", true);
      user_pref("gfx.color_management.mode", 1);
      user_pref("extensions.autoDisableScopes", 0);
      user_pref("xpinstall.signatures.required", false);
      user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
      user_pref("svg.context-properties.content.enabled", true);
      user_pref("widget.non-native-theme.use-theme-accent", true);

      user_pref("nglayout.initialpaint.delay", 0);
      user_pref("nglayout.initialpaint.delay_in_oopif", 0);
      user_pref("content.notify.interval", 100000);

      user_pref("layout.css.grid-template-masonry-value.enabled", true);
      user_pref("dom.enable_web_task_scheduling", true);
      user_pref("layout.css.has-selector.enabled", true);
      user_pref("dom.security.sanitizer.enabled", true);

      user_pref("gfx.canvas.accelerated.cache-items", 4096);
      user_pref("gfx.canvas.accelerated.cache-size", 512);
      user_pref("gfx.content.skia-font-cache-size", 20);

      user_pref("browser.cache.disk.enable", false);

      user_pref("media.memory_cache_max_size", 65536);
      user_pref("media.cache_readahead_limit", 7200);
      user_pref("media.cache_resume_threshold", 3600);

      user_pref("image.mem.decode_bytes_at_a_time", 32768);

      user_pref("network.buffer.cache.size", 262144);
      user_pref("network.buffer.cache.count", 128);
      user_pref("network.http.max-connections", 1800);
      user_pref("network.http.max-persistent-connections-per-server", 10);
      user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
      user_pref("network.http.pacing.requests.enabled", false);
      user_pref("network.dnsCacheEntries", 1000);
      user_pref("network.dnsCacheExpiration", 86400);
      user_pref("network.dns.max_high_priority_threads", 8);
      user_pref("network.ssl_tokens_cache_capacity", 10240);

      user_pref("network.http.speculative-parallel-limit", 0);
      user_pref("network.dns.disablePrefetch", true);
      user_pref("browser.urlbar.speculativeConnect.enabled", false);
      user_pref("browser.places.speculativeConnect.enabled", false);
      user_pref("network.prefetch-next", false);
      user_pref("network.predictor.enabled", false);
      user_pref("network.predictor.enable-prefetch", false);
    '';

    ".config/zen/config-staging/userChrome.css".text = ''
      /* ===== True Black theme ===== */
      * { scrollbar-color: #333 #000 !important; }

      :root {
        --zen-main-browser-background: #000000 !important;
        --zen-main-browser-background-toolbar: #000000 !important;
        --zen-primary-color: #000000 !important;
        --zen-colors-tertiary: #000000 !important;
        --zen-colors-secondary: #000000 !important;
        --zen-workspaces-strip-background-color: #000000 !important;
        --lwt-accent-color: #000000 !important;
        --lwt-text-color: #cccccc !important;
        --lwt-toolbar-field-background-color: #1a1a1a !important;
        --lwt-toolbar-field-color: #cccccc !important;
        --lwt-toolbar-field-border-color: #000000 !important;
        --lwt-toolbar-field-highlight: #333333 !important;
        --lwt-toolbar-field-highlight-text: #ffffff !important;
        --lwt-sidebar-background-color: #000000 !important;
        --lwt-sidebar-text-color: #cccccc !important;
        --toolbar-bgcolor: #000000 !important;
        --toolbar-color: #cccccc !important;
        --toolbar-field-bgcolor: #1a1a1a !important;
        --toolbar-field-color: #cccccc !important;
        --toolbar-field-border-color: #000000 !important;
        --toolbar-field-focus-bgcolor: #1a1a1a !important;
        --toolbar-field-focus-color: #cccccc !important;
        --toolbar-field-focus-border-color: #333333 !important;
        --toolbar-hover-background: #2a2a2a !important;
        --toolbarbutton-hover-background: #2a2a2a !important;
        --toolbarbutton-active-background: #333333 !important;
        --tab-selected-bgcolor: #0a0a0a !important;
        --tab-hover-background-color: #1a1a1a !important;
        --tab-line-color: #333333 !important;
        --tab-loading-fill: #333333 !important;
        --tabs-border-color: #000000 !important;
        --tab-background-color: #000000 !important;
        --arrowpanel-background: #1a1a1a !important;
        --arrowpanel-color: #cccccc !important;
        --arrowpanel-border-color: #000000 !important;
        --panel-background: #1a1a1a !important;
        --panel-color: #cccccc !important;
        --panel-border-color: #000000 !important;
        --panel-item-hover-bgcolor: #333333 !important;
        --sidebar-background-color: #000000 !important;
        --sidebar-text-color: #cccccc !important;
        --sidebar-border-color: #000000 !important;
        --urlbar-background-color: #1a1a1a !important;
        --urlbar-view-background: #1a1a1a !important;
        --urlbar-color: #cccccc !important;
        --urlbar-border-color: #000000 !important;
        --better-findbar-background-color: #1a1a1a !important;
        --button-bgcolor: #000000 !important;
        --button-hover-bgcolor: #2a2a2a !important;
        --button-active-bgcolor: #333333 !important;
        --button-color: #cccccc !important;
        --button-primary-bgcolor: #333333 !important;
        --button-primary-color: #ffffff !important;
        --icon-color: #cccccc !important;
        --workspace-button-bg: #0a0a0a !important;
      }

      .zen-browser-generic-background { background: #000000 !important; }
      #sidebar-box, #sidebar { background-color: #000000 !important; }
      #zen-sidebar-web-panel { background-color: #000000 !important; }
      #main-window, #browser, #navigator-toolbox { background-color: #000000 !important; }
      #zen-workspaces-strip { background-color: #000000 !important; }

      /* Bottom navbar */
      #zen-appcontent-wrapper { display: flex !important; flex-direction: column !important; }
      #zen-appcontent-navbar-wrapper { order: 2 !important; }
      #zen-tabbox-wrapper { order: 1 !important; }

      /* Sharp corners */
      :root {
        --zen-webview-border-radius: 0px !important;
        --zen-border-radius: 0px !important;
        --zen-element-separation: 0px !important;
      }

      browser { border-radius: 0 !important; }

      :root:not([inDOMFullscreen="true"]) #tabbrowser-tabbox #tabbrowser-tabpanels .browserSidebarContainer {
        border-radius: 0 !important;
        margin: 0 !important;
      }

      #tabbrowser-tabpanels { border: none !important; outline: none !important; padding: 0 !important; margin: 0 !important; border-radius: 0 !important; }

      #nav-bar, #zen-appcontent-navbar-wrapper, #zen-appcontent-navbar-wrapper > * { border-radius: 0 !important; }

      #nav-bar { font-size: 1.15em !important; }
      #nav-bar toolbarbutton, #urlbar-input, #urlbar, .urlbar-input-box { font-size: inherit !important; }

      #zen-appcontent-navbar-wrapper[zen-has-hover],
      #zen-appcontent-navbar-wrapper[has-popup-menu],
      #zen-appcontent-navbar-wrapper[zen-compact-mode-active] { order: 2 !important; }
    '';

    ".config/zen/config-staging/true-black-zen-mod/theme.json".text = ''
      {
        "id": "e8976c92-47dc-4065-bf53-67326dd47007",
        "name": "True Black",
        "description": "Pure black (#000) for every chrome surface",
        "style": { "chrome": "chrome.css" },
        "author": "neg",
        "version": "1.0.0",
        "tags": ["black", "dark", "amoled"]
      }
    '';

    ".config/zen/config-staging/true-black-zen-mod/chrome.css".text = ''
      * { scrollbar-color: #333 #000 !important; }
      :root {
        --zen-main-browser-background: #000000 !important;
        --zen-main-browser-background-toolbar: #000000 !important;
        --zen-primary-color: #000000 !important;
        --zen-colors-tertiary: #000000 !important;
        --zen-colors-secondary: #000000 !important;
        --zen-workspaces-strip-background-color: #000000 !important;
        --lwt-accent-color: #000000 !important;
        --lwt-text-color: #cccccc !important;
        --lwt-toolbar-field-background-color: #1a1a1a !important;
        --lwt-toolbar-field-color: #cccccc !important;
        --lwt-toolbar-field-border-color: #000000 !important;
        --lwt-toolbar-field-highlight: #333333 !important;
        --lwt-toolbar-field-highlight-text: #ffffff !important;
        --lwt-sidebar-background-color: #000000 !important;
        --lwt-sidebar-text-color: #cccccc !important;
        --toolbar-bgcolor: #000000 !important;
        --toolbar-color: #cccccc !important;
        --toolbar-field-bgcolor: #1a1a1a !important;
        --toolbar-field-color: #cccccc !important;
        --toolbar-field-border-color: #000000 !important;
        --toolbar-field-focus-bgcolor: #1a1a1a !important;
        --toolbar-field-focus-color: #cccccc !important;
        --toolbar-field-focus-border-color: #333333 !important;
        --toolbar-hover-background: #2a2a2a !important;
        --toolbarbutton-hover-background: #2a2a2a !important;
        --toolbarbutton-active-background: #333333 !important;
        --tab-selected-bgcolor: #0a0a0a !important;
        --tab-hover-background-color: #1a1a1a !important;
        --tab-line-color: #333333 !important;
        --tab-loading-fill: #333333 !important;
        --tabs-border-color: #000000 !important;
        --tab-background-color: #000000 !important;
        --arrowpanel-background: #1a1a1a !important;
        --arrowpanel-color: #cccccc !important;
        --arrowpanel-border-color: #000000 !important;
        --panel-background: #1a1a1a !important;
        --panel-color: #cccccc !important;
        --panel-border-color: #000000 !important;
        --panel-item-hover-bgcolor: #333333 !important;
        --sidebar-background-color: #000000 !important;
        --sidebar-text-color: #cccccc !important;
        --sidebar-border-color: #000000 !important;
        --urlbar-background-color: #1a1a1a !important;
        --urlbar-view-background: #1a1a1a !important;
        --urlbar-color: #cccccc !important;
        --urlbar-border-color: #000000 !important;
        --better-findbar-background-color: #1a1a1a !important;
        --button-bgcolor: #000000 !important;
        --button-hover-bgcolor: #2a2a2a !important;
        --button-active-bgcolor: #333333 !important;
        --button-color: #cccccc !important;
        --button-primary-bgcolor: #333333 !important;
        --button-primary-color: #ffffff !important;
        --icon-color: #cccccc !important;
        --workspace-button-bg: #0a0a0a !important;
      }
      .zen-browser-generic-background { background: #000000 !important; }
      #sidebar-box, #sidebar { background-color: #000000 !important; }
      #zen-sidebar-web-panel { background-color: #000000 !important; }
      #main-window, #browser, #navigator-toolbox { background-color: #000000 !important; }
      #zen-workspaces-strip { background-color: #000000 !important; }
    '';
  })
);
}
