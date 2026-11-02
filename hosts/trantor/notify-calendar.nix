{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
# Morning Telegram calendar reminder. Each day at 07:30 (Europe/Moscow) the
# oneshot unit lists the local user (neg) khal calendar events for "today";
# if there are any, it posts a single "📅 Today:" message to the Telegram
# chat from secrets/telegram.sops.yaml via the shared sender in
# hosts/trantor/telegram.nix, otherwise it exits silently.
#
# Auto-imported from hosts/trantor/*.nix.
#
# Gating:
#   - khal is only present when features.mail.enable is set (see
#     modules/user/nix-maid/sys/khal.nix);
#   - the whole stack is inert without secrets/telegram.sops.yaml
#     (config.trantor.telegram.enable).
let
  mailOn = config.features.mail.enable or false;
in
{
  config = lib.mkIf (mailOn && config.trantor.telegram.enable) (
    let
      systemdUser = neg.systemdUser lib;

      # The reminder is a Rust package: it runs khal as the user that owns the
      # calendars (neg), formats today's events and hands the message to the
      # shared socks-proxy sender. Telegram/network hiccups must not fail the
      # unit, so any delivery problem exits 0 after the retry window.
      # The sender path is handed over in the environment (the binary has no
      # build-time substitution), which the wrapper supplies.
      script = pkgs.writeShellScript "telegram-calendar-reminder" ''
        export TELEGRAM_SENDER=${lib.getExe config.trantor.telegram.sender}
        exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-calendar-reminder"} "$@"
      '';
    in
    systemdUser.mkOneshotTimer {
      name = "telegram-calendar-reminder";
      description = "Send today's khal calendar events to Telegram in the morning";
      timerDescription = "Daily 07:30 morning calendar reminder";
      script = "${script}";
      onCalendar = "*-*-* 07:30:00";
    }
  );
}
