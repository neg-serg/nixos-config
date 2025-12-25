{lib, ...}: let
  # Common extension list for all Chromium browsers
  commonExtensions = [
    "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
    "gighmmpiobklfepjocanfajhashmkbed" # AdBlock
    "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
    "gmbmikajjgocabecnoocmodnpiogccbe" # Dark Reader
    "clngdbkpkpeebahjckkjfobafhncgmne" # Stylus
    "pkehgijimnmhlpjocpleijbhhmbhiclc" # Sidebery placeholder
    "oldceeleldhonbafppcapldpdifcinji" # LanguageTool
    "liecbpablbhkpakedmddhodofcncejka" # Keepa
  ];

  # Helper to build the final module result
  mkChromiumModule = {
    browserName,
    package,
    config,
    extraPolicies ? {},
    extraPackages ? [],
  }: let
    webCfg = config.features.web;
    browserCfg = webCfg.${browserName} or {enable = false;};
    enabled = webCfg.enable && browserCfg.enable;
  in
    lib.mkIf enabled {
      environment.systemPackages = [package] ++ extraPackages;

      programs.chromium = {
        enable = true;
        extraOpts =
          {
            "PasswordManagerEnabled" = false;
            "BuiltInNotificationsSettings" = 2; # Blocked
            "MetricsReportingEnabled" = false;
            "SafeBrowsingProtectionLevel" = 1; # Standard
            "SearchSuggestEnabled" = false;
            "SyncDisabled" = false;
            "ExtensionInstallForcelist" = commonExtensions;
            "ShowHomeButton" = true;
            "BookmarkBarEnabled" = false;
          }
          // extraPolicies;
      };
    };
in {
  inherit mkChromiumModule;
}
