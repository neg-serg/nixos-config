{
  lib,
  pkgs,
  config,
  yandexBrowserProvider ? null,
  nyxt4 ? null,
  ...
}:
with lib; let
  cfg = config.features.web;
  key = cfg.default or "floorp";
  needYandex = (cfg.enable or false) && (cfg.yandex.enable or false);
  yandexBrowser =
    if needYandex && yandexBrowserProvider != null
    then yandexBrowserProvider pkgs
    else null;
  browsers = import ./browsers-table.nix {inherit lib pkgs yandexBrowser nyxt4;};
in
  lib.attrByPath [key] browsers browsers.floorp
