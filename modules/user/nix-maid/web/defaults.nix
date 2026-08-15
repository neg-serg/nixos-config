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
  }; # Updated import path
  # Select the record named by features.web.default; {} (→ xdg-open fallback)
  # when unset or unknown. Previously hardcoded to {} — the option was set on
  # the host but never read. NB: `or` after an attrpath only covers *missing*
  # attributes, so null must be guarded explicitly (browsers.${null} is an
  # eval error, not a lookup miss).
  browser = if (cfg.default or null) == null then { } else (browsers.${cfg.default} or { });
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
