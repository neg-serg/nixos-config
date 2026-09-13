{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.mail; # Tie to mail feature as we're using it for calendars
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.khal ]; # CLI calendar application
      }
      (neg.mkHomeFiles {
        ".config/khal/config".text =
          builtins.replaceStrings [ "@TIMEZONE@" ] [ "${config.time.timeZone}" ]
            (builtins.readFile (config.lib.neg.path "files/config/khal/config"));
      })
    ]
  );
}
