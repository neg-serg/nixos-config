{
  lib,
  config,
  pkgs,
  ...
}:
# Morning Telegram calendar reminder. Each day at 07:30 (Europe/Moscow) the
# oneshot unit lists the local user (neg) khal calendar events for "today";
# if there are any, it posts a single "📅 Сегодня:" message to the Telegram
# chat from secrets/telegram.sops.yaml via the shared sender in
# hosts/odin/telegram.nix, otherwise it exits silently.
#
# Auto-imported from hosts/odin/*.nix.
#
# Gating:
#   - khal is only present when features.mail.enable is set (see
#     modules/user/nix-maid/sys/khal.nix);
#   - the whole stack is inert without secrets/telegram.sops.yaml
#     (config.odin.telegram.enable).
let
  mailOn = config.features.mail.enable or false;
in
{
  config = lib.mkIf (mailOn && config.odin.telegram.enable) (
    let
      systemdUser = import ../../lib/systemd-user.nix { inherit lib; };

      # Extracted to ./notify/telegram-calendar-reminder.py (linted as Python);
      # the shared sender path is substituted at build time.
      calendarScript = pkgs.replaceVars ./notify/telegram-calendar-reminder.py {
        sender = config.odin.telegram.sender;
      };

      # Runs khal as the user that owns the calendars (neg) and posts a
      # Telegram message through the sing-box socks proxy when today has
      # events. Telegram/network hiccups must not fail the unit, so any
      # delivery problem exits 0 after the retry window.
      script = pkgs.writeShellApplication {
        name = "telegram-calendar-reminder";
        runtimeInputs = [
          pkgs.python3 # event parsing / JSON handling
          pkgs.coreutils # runuser environment
        ];
        text = ''
          # khal/config discovered config, calendar files and cache live in the
          # neg home; run khal under that uid so it may read/write them.
          exec python3 ${calendarScript}
        '';
      };
    in
    systemdUser.mkOneshotTimer {
      name = "telegram-calendar-reminder";
      description = "Send today's khal calendar events to Telegram in the morning";
      timerDescription = "Daily 07:30 morning calendar reminder";
      script = "${lib.getExe script}";
      onCalendar = "*-*-* 07:30:00";
    }
  );
}
