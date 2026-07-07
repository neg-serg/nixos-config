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
      };
    };
  };
}
