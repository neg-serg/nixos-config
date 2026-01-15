{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.mail; # Tie to mail feature as we're using it for calendars
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.khal ]; # CLI calendar application
      }
      (n.mkHomeFiles {
        ".config/khal/config".text = ''
          [calendars]
          [[calendars_discovery]]
          path = ~/.config/vdirsyncer/calendars/
          type = discover

          [locale]
          timeformat = %H:%M
          dateformat = %d.%m.%Y
          longdateformat = %d.%m.%Y %H:%M
          datetimeformat = %d.%m.%Y %H:%M
          longdatetimeformat = %d.%m.%Y %H:%M
          firstweekday = 0
          default_timezone = ${config.time.timeZone}

          [default]
          show_all_days = False
        '';
      })
    ]
  );
}
