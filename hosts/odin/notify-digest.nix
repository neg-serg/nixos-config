# Daily 08:00 Telegram morning digest for odin (auto-imported from hosts/odin/).
#
# Composes ONE compact Russian message (weekday header, ZFS pool fill, disk
# usage for / and /zero, failed units) and posts it to the Telegram chat from
# secrets/telegram.sops.yaml. api.telegram.org is only reachable through the
# user sing-box socks proxy (127.0.0.1:10808), so the send retries a few times.
#
# Everything is gated on config.odin.telegram.enable (see
# hosts/odin/telegram.nix); without the secret file the whole unit stays
# disabled.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  systemdUser = import ../../lib/systemd-user.nix { inherit lib; };

  telegramDigestScript = pkgs.writeShellApplication {
    name = "telegram-digest";
    runtimeInputs = [
      pkgs.coreutils # date, cat, df for the digest body
      pkgs.inetutils # hostname of this machine
      pkgs.systemd # systemctl --failed for the failed-units check
      pkgs.zfs # zpool list for pool fill/health
    ];
    text = builtins.readFile (
      pkgs.replaceVars ./notify/digest.sh {
        sender = config.odin.telegram.sender;
      }
    );
  };
in
lib.mkIf config.odin.telegram.enable (
  systemdUser.mkOneshotTimer {
    name = "telegram-digest";
    description = "Send the daily 08:00 Telegram morning digest";
    timerDescription = "Daily 08:00 Telegram morning digest";
    script = lib.getExe telegramDigestScript;
    onCalendar = "*-*-* 08:00:00";
    stateDirectory = "telegram-digest";
  }
)
