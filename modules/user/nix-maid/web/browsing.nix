{
  pkgs,
  lib,
  config,
  yandexBrowserProvider ? null,
  ...
}:
with lib; let
  needYandex = (config.features.web.enable or false) && (config.features.web.yandex.enable or false);
  yandexBrowser =
    if needYandex && yandexBrowserProvider != null
    then yandexBrowserProvider pkgs
    else null;
in {
  imports = [
    ./defaults.nix # Migrated
    # ./floorp.nix # Removed (empty/deleted)
    # ./firefox.nix # Removed (empty/deleted)
    ./librewolf.nix # Migrated
    # ./nyxt.nix # Migrated (moved to parent directory)
  ];

  config = {
    assertions = [
      {
        assertion = (! needYandex) || (yandexBrowser != null);
        message = "Yandex Browser requested but 'yandexBrowser' extraSpecialArg not provided in flake.nix.";
      }
    ];
  };
}
