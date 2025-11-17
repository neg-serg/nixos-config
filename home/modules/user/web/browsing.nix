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

  config = mkMerge [
    {
      assertions = [
        {
          assertion = (! needYandex) || (yandexBrowser != null);
          message = "Yandex Browser requested but 'yandexBrowser' extraSpecialArg not provided in flake.nix.";
        }
      ];
    }
    (mkIf config.features.web.enable {
      # Collect package groups and flatten via mkEnabledList to reduce scattered optionals
      home.packages = config.lib.neg.pkgsList (
        let
          groups = {
            core = [
              pkgs.passff-host # native host for PassFF extension
            ];
            yandex = lib.optionals (yandexBrowser != null) [
              yandexBrowser.yandex-browser-stable # Yandex Browser (proprietary)
            ];
          };
          flags = {
            core = true;
            yandex = (yandexBrowser != null) && (config.features.web.yandex.enable or false);
          };
        in
          config.lib.neg.mkEnabledList flags groups
      );
    })
  ];
}
