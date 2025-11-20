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
  needYandex = (cfg.enable or false) && (cfg.yandex.enable or false);
  yandexBrowser =
    if needYandex && yandexBrowserProvider != null
    then yandexBrowserProvider pkgs
    else null;
  browsers = import ./browsers-table.nix {inherit lib pkgs yandexBrowser nyxt4;};
  browser = let key = cfg.default or "floorp"; in lib.attrByPath [key] browsers browsers.floorp;
in {
  config = {
    # Expose derived default browser under lib.neg for reuse
    lib.neg.web = mkIf cfg.enable {
      defaultBrowser = browser;
      inherit browsers;
    };

    # Provide common env defaults (can be overridden elsewhere if needed)
    home.sessionVariables = mkIf cfg.enable (
      let
        db = browser;
      in {
        BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open");
        DEFAULT_BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open");
      }
    );

    # Provide minimal sane defaults for common browser handlers
    xdg.mimeApps = mkIf cfg.enable (
      let
        db = browser;
      in {
        enable = true;
        defaultApplications = {
          "text/html" = db.desktop or "floorp.desktop";
          "x-scheme-handler/http" = db.desktop or "floorp.desktop";
          "x-scheme-handler/https" = db.desktop or "floorp.desktop";
          "x-scheme-handler/about" = db.desktop or "floorp.desktop";
          "x-scheme-handler/unknown" = db.desktop or "floorp.desktop";
        };
      }
    );
  };
}
