{
  lib,
  pkgs,
  config,
  yandexBrowserProvider ? null,
  ...
}:
with lib; let
  cfg = config.features.web;
  needYandex = (cfg.enable or false) && (cfg.yandex.enable or false);
  yandexBrowser =
    if needYandex && yandexBrowserProvider != null
    then yandexBrowserProvider pkgs
    else null;
  browsers = import ./browsers-table.nix {
    inherit lib pkgs yandexBrowser;
    nyxt4 = null;
  }; # Updated import path
  browser = let key = cfg.default or "floorp"; in lib.attrByPath [key] browsers browsers.floorp;
in {
  config = {
    # Expose derived default browser under lib.neg for reuse
    lib.neg.web = mkIf cfg.enable {
      defaultBrowser = browser;
      inherit browsers;
    };

    # Provide sane defaults for BROWSER env var
    environment.sessionVariables = mkIf cfg.enable (
      let
        db = browser;
      in {
        BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open");
        DEFAULT_BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open");
      }
    );
  };
}
