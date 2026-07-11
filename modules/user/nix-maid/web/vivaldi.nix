{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.features.web.vivaldi;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;

  # Extensions to force-install via managed policy
  extensions = [
    "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
    "gfbliohnnapiefjpjlpjnehglfpaknnc" # SurfingKeys (vim-like keybindings)
  ];

  vivaldi-pkg = pkgs.vivaldi.override {
    # Wayland Ozone + Skia renderer (stable colors, no Vulkan video-overlay bug) +
    # VA-API hardware video decoding on AMD (radeonsi). Vulkan is disabled for rendering
    # and video — it causes a white-screen video overlay on Wayland (Chromium bug).
    commandLineArgs = "--ozone-platform-hint=wayland --enable-features=UseSkiaRenderer,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks --disable-features=Vulkan";
    proprietaryCodecs = true;
  };
in
{
  config = mkIf (webEnabled && guiEnabled && cfg.enable) {

    environment.systemPackages = [
      vivaldi-pkg # Vivaldi browser (Chromium-based, with Wayland flags)
    ];

    # Chromium managed policies — Vivaldi reads from /etc/chromium/policies/managed/
    # (Vivaldi is Chromium-based, shares the same policy infrastructure)
    programs.chromium = {
      enable = true;
      inherit extensions;
      extraOpts = {
        "PasswordManagerEnabled" = false;
        "BuiltInNotificationsSettings" = 2; # Blocked
        "MetricsReportingEnabled" = false;
        "SafeBrowsingProtectionLevel" = 1; # Standard
        "SearchSuggestEnabled" = false;
        "SyncDisabled" = false;
        "ShowHomeButton" = true;
        "BookmarkBarEnabled" = false;

        # Default font: Iosevka everywhere (matches system-wide fontconfig default)
        "StandardFontFamily" = "Iosevka";
        "SerifFontFamily" = "Iosevka";
        "SansSerifFontFamily" = "Iosevka";
        "FixedFontFamily" = "Iosevka";
        "DefaultFontSize" = 15;
        "DefaultFixedFontSize" = 13;
      };
    };

    # Vivaldi-specific managed policies (Vivaldi 8.x reads from /etc/vivaldi on some installs)
    # Write a separate copy for Vivaldi to ensure policies are picked up.
    environment.etc."vivaldi/policies/managed/vivaldi-fonts.json" = {
      mode = "0444";
      text = builtins.toJSON {
        StandardFontFamily = "Iosevka";
        SerifFontFamily = "Iosevka";
        SansSerifFontFamily = "Iosevka";
        FixedFontFamily = "Iosevka";
        DefaultFontSize = 15;
        DefaultFixedFontSize = 13;
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
          font-family: "Iosevka" !important;
          font-size: 15px !important;
          font-weight: 600 !important;
        }
      '';
    };
  };
}
