{
  config,
  pkgs,
  lib,
  negLib,
  faProvider ? null,
  ...
}:
lib.mkIf (config.features.web.enable && config.features.web.floorp.enable) (let
  common = import ./mozilla-common-lib.nix {inherit lib pkgs config faProvider negLib;};
  # Floorp upstream source package is deprecated in nixpkgs >= 12.x; always use floorp-bin.
  floorpPkg = pkgs.floorp-bin;
  profileId = "bqtlgdxw.default";

  shimmerEnabled = config.features.web.floorp.shimmer.enable;
  shimmer = pkgs.fetchFromGitHub {
    owner = "nuclearcodecat";
    repo = "shimmer";
    rev = "main";
    sha256 = "0ypwzyfbavdm4za8y0r2yz4b5aaw7g2j0q6n1ppixpr5q8m5ia1p";
  };
in
  lib.mkMerge [
    (common.mkBrowser {
      name = "floorp";
      package = floorpPkg;
      # Floorp uses flat profile tree; keep explicit id
      inherit profileId;
      # Keep navbar on top for Floorp.
      # Rationale:
      # - Floorp ships heavy UI theming (Lepton‑style tweaks); bottom pinning adds brittle CSS
      #   overrides and regresses with upstream changes (urlbar popup, engine badges, panels).
      # - Extension panels and some popups mis‑position when the navbar is fixed to bottom;
      #   stock top navbar avoids those edge cases.
      # - We keep minimal, safe tweaks (findbar polish, compact tabs) and skip bottom pinning.
      # Opt‑in (unsupported): set bottomNavbar = true and maintain custom CSS locally.
      bottomNavbar = false;
      # Return to stock UI (no injected userChrome tweaks)
      vanillaChrome = true;
      userChromeExtra = lib.optionalString shimmerEnabled ''
        @import "shimmer/userChrome.css";
      '';
      # Convenience tweaks: remove sponsored tiles on New Tab and
      # disable trending/Quicksuggest items in the urlbar.
      settingsExtra = {
        # Activity Stream (New Tab) — no sponsored content
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        # Hide Top Sites row entirely
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showTopSites" = false;
        # Hide Highlights section
        "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
        "browser.newtabpage.activity-stream.showHighlights" = false;
        # Hide Top Stories (Pocket recommendations), in addition to policies
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        # Hide Weather (if present in this build)
        "browser.newtabpage.activity-stream.showWeather" = false;
        "browser.newtabpage.activity-stream.feeds.section.weather" = false;
        "browser.newtabpage.activity-stream.feeds.weather" = false;

        # URL bar suggestions — disable Firefox Suggest/Quicksuggest including trending
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.urlbar.quicksuggest.sponsoredEnabled" = false;
        "browser.urlbar.quicksuggest.nonSponsoredEnabled" = false;
        # Feature gates used by newer builds
        "browser.urlbar.merino.enabled" = false;
        "browser.urlbar.trending.featureGate" = false;
        # Keep scenario offline if some bits slip through in certain versions
        "browser.urlbar.quicksuggest.scenario" = "offline";

        # Stronger content blocking and native file picker via portals
        "browser.contentblocking.category" = "strict";
        "widget.use-xdg-desktop-portal.file-picker" = 1;
      };
      # Enterprise policies: reduce telemetry/noise and enable DoH
      policiesExtra = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        CaptivePortal = false;
        DNSOverHTTPS = {
          Enabled = true;
          Locked = false;
        };
      };
    })
    {
      home.sessionVariables = {
        MOZ_DBUS_REMOTE = "1";
        MOZ_ENABLE_WAYLAND = "1";
      };
    }
    (lib.mkIf shimmerEnabled {
      home.file.".floorp/${profileId}/chrome/shimmer".source = shimmer;
    })
  ])
