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
    "gfbliohnnapiefjpjlpjnehglfpaknnc" # SurfingKeys (vim-like keybindings)
  ];

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
    # --disable-features=WaylandWpColorManagerV1: Chromium's wp_color_manager_v1
    # protocol handshake with Hyprland cm=auto can fail on AMD, causing overbright
    # gamma and incorrect colors (vs Firefox which doesn't use this protocol).
    commandLineArgs = "--ozone-platform-hint=wayland --force-color-profile=srgb --enable-features=UseSkiaRenderer,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks --disable-features=Vulkan,WaylandWpColorManagerV1";
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

    # Vivaldi-specific managed policies.
    # Vivaldi 8.x reads from /etc/vivaldi/policies/managed/ but sometimes ignores
    # /etc/chromium/policies/managed/.  Duplicate the relevant policies here.
    environment.etc."vivaldi/policies/managed/extensions.json" = {
      mode = "0444";
      text = builtins.toJSON {
        ExtensionInstallForcelist = extensions;
      };
    };

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
