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
        ".config/khal/config".text = ''
          [calendars]
          [[calendars_discovery]]
          path = ~/.config/vdirsyncer/calendars/
          type = discover

          # Per-calendar color and priority overrides
          # After vdirsyncer syncs your calendars, add entries like:
          # [[calendars]]
          # path = ~/.config/vdirsyncer/calendars/Personal/
          # color = light green
          # priority = 10
          # [[calendars]]
          # path = ~/.config/vdirsyncer/calendars/Work/
          # color = dark blue
          # priority = 5

          # [palette] — uncomment to override calendar colors
          # highlight = black on green

          [locale]
          timeformat = %H:%M
          dateformat = %d.%m.%Y
          longdateformat = %d.%m.%Y %H:%M
          datetimeformat = %d.%m.%Y %H:%M
          longdatetimeformat = %d.%m.%Y %H:%M
          firstweekday = 0
          default_timezone = ${config.time.timeZone}

          [default]
          timedelta = 30m
          show_all_days = True

          [keybindings]
          search = /
          external_edit = e
          duplicate = d
          save = ctrl s

          [view]
          agenda_event_format = {calendar-color}{cancelled}{start-end-time-style} {title}{repeat-symbol}{reset}
          agenda_day_format = {bold}{name} · {date-long}{reset}
          monthdisplay = firstfullweek
        '';
      })
    ]
  );
}
