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
    "gighmmpiobklfepjocanfajhashmkbed" # AdBlock
    "gmbmikajjgocabecnoocmodnpiogccbe" # Dark Reader
    "clngdbkpkpeebahjckkjfobafhncgmne" # Stylus
    "oldceeleldhonbafppcapldpdifcinji" # LanguageTool
    "liecbpablbhkpakedmddhodofcncejka" # Keepa
    "gfbliohnnapiefjpjlpjnehglfpaknnc" # SurfingKeys (vim-like keybindings)
  ];

  vivaldi-pkg = pkgs.vivaldi.override {
    commandLineArgs = "--ozone-platform-hint=wayland";
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
  };
}
