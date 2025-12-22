{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.mail; # Tie to mail feature as we're using it for calendars
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [pkgs.khal];

    users.users.neg.maid.file.home = {
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

        [default]
        default_calendar = default
        show_all_days = False
      '';
    };
  }
