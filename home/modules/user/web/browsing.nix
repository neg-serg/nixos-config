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
    ./defaults.nix
    ./floorp.nix
    ./firefox.nix
    ./librewolf.nix
    ./nyxt.nix
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
