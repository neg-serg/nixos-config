{
  lib,
  pkgs,
  config,

  ...
}:
with lib;
let
  cfg = config.features.web;

  browsers = import ./browsers-table.nix {
    inherit lib pkgs;
    nyxt4 = null;
  }; # Updated import path
  browser =
    let
      key = cfg.default or "floorp";
    in
    lib.attrByPath [ key ] browsers browsers.floorp;
in
{
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
      in
      {
        BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open"); # Set of command line tools that assist applications with a...
        DEFAULT_BROWSER = db.bin or (lib.getExe' pkgs.xdg-utils "xdg-open"); # Set of command line tools that assist applications with a...
      }
    );
  };
}
