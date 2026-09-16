{
  lib,
  config,
  pkgs,
  ...
}:
# ZFS pool health + scrub-completion Telegram watcher for odin.
#
# Every 10 minutes enumerates the ZFS pools, parses `zpool status` for the
# pool state, per-vdev READ/WRITE/CKSUM error counts and the last completed
# scrub, and (only on a transition, to avoid alert spam) posts a Telegram
# message:
#   - problems appeared           -> "⚠️ ZFS <pool>: <problems>"
#   - problems cleared            -> "✅ ZFS <pool>: recovered"
#   - a NEW monthly scrub finish  -> "🧹 ZFS scrub <pool> закончен: <N> ..."
# Telegram delivery goes through the shared sender (hosts/odin/telegram.nix),
# which owns the sing-box socks-proxy retry.
let
  systemdUser = import ../../lib/systemd-user.nix { inherit lib; };

  # State keeps, per pool, the last observed health (ok/problems) and the last
  # completed scrub date+errors so the script only alerts on real changes.
  stateDir = "/var/lib/telegram-zfs-watch";
  stateFile = "${stateDir}/state.json";

  watchScript = pkgs.replaceVars ./notify/telegram-zfs-watch.py {
    sender = config.odin.telegram.sender;
    inherit stateDir stateFile;
  };
in
# Telegram is gated on config.odin.telegram.enable (see hosts/odin/telegram.nix).
(lib.mkIf config.odin.telegram.enable (
  systemdUser.mkOneshotTimer {
    name = "telegram-zfs-watch";
    description = "Watch ZFS pool health and scrub completions, alert to Telegram";
    timerDescription = "Check ZFS pool health and scrubs every 10 minutes";
    script = "${pkgs.python3}/bin/python3 ${watchScript}";
    onCalendar = "*-*-* *:0/10:00";
    restartSec = 30;
    stateDirectory = "telegram-zfs-watch";
  }
))
