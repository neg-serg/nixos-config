{
  pkgs,
  lib,
  config,

  yandexBrowserProvider ? null,
  ...
}:
let
  webEnabled = config.features.web.enable or false;
  yandexEnabled = config.features.web.yandex.enable or false;
  enabled = webEnabled && yandexEnabled;

  yandexInput = if yandexBrowserProvider != null then yandexBrowserProvider pkgs else null;
  yandexPkgRaw = if yandexInput != null then yandexInput.yandex-browser-stable else null;
  yandexPkg =
    if yandexPkgRaw != null then
      yandexPkgRaw.overrideAttrs (old: {
        version = "25.10.1.1173-1";
        src = pkgs.fetchurl {
          url = "http://repo.yandex.ru/yandex-browser/deb/pool/main/y/yandex-browser-stable/yandex-browser-stable_25.10.1.1173-1_amd64.deb";
          hash = "sha256-MewVX1C6DsnE1IQTIurZsZZCmSbt7a7gxMm0yqk3qmQ=";
        };
        meta = (old.meta or { }) // {
          insecure = false;
          knownVulnerabilities = [ ];
        };
      })
    else
      null;
in
{
  # nixpkgs.config.permittedInsecurePackages moved to flake/pkgs-config.nix

  # Using mkMerge for the conditional configuration part
  environment.systemPackages = lib.mkIf (enabled && yandexPkg != null) [ yandexPkg ];

  programs.chromium = lib.mkIf enabled {
    enable = true;
    extraOpts = {
      "PasswordManagerEnabled" = false;
      "BuiltInNotificationsSettings" = 2; # Blocked
      "MetricsReportingEnabled" = false;
      "SafeBrowsingProtectionLevel" = 1; # Standard
      "SearchSuggestEnabled" = false;
      "SyncDisabled" = true; # Yandex specific
      "ExtensionInstallForcelist" = [
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
        "gighmmpiobklfepjocanfajhashmkbed" # AdBlock
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
        "gmbmikajjgocabecnoocmodnpiogccbe" # Dark Reader
        "clngdbkpkpeebahjckkjfobafhncgmne" # Stylus
        "pkehgijimnmhlpjocpleijbhhmbhiclc" # Sidebery placeholder
        "oldceeleldhonbafppcapldpdifcinji" # LanguageTool
        "liecbpablbhkpakedmddhodofcncejka" # Keepa
      ];
      "ShowHomeButton" = true;
      "BookmarkBarEnabled" = false;
    };
  };
}
