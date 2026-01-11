{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  yandexBrowserProvider ? null,
  ...
}:
with lib;
let
  n = neg impurity;
  needYandex = (config.features.web.enable or false) && (config.features.web.yandex.enable or false);
  yandexBrowser =
    if needYandex && yandexBrowserProvider != null then yandexBrowserProvider pkgs else null;
in
{
  imports = [
    ./defaults.nix
    ./librewolf.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (n.mkHomeFiles {
      ".config/surfingkeys.js".source = "${pkgs.surfingkeys-pkg}/share/surfingkeys/surfingkeys.js";
    })
    {
      assertions = [
        {
          assertion = (!needYandex) || (yandexBrowser != null);
          message = "Yandex Browser requested but 'yandexBrowser' extraSpecialArg not provided in flake.nix.";
        }
      ];
    }
  ];
}
