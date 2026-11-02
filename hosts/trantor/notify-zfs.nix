{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
# ZFS pool health + scrub-completion Telegram watcher for trantor.
#
# Every 10 minutes enumerates the ZFS pools, parses `zpool status` for the
# pool state, per-vdev READ/WRITE/CKSUM error counts and the last completed
# scrub, and (only on a transition, to avoid alert spam) posts a Telegram
# message:
#   - problems appeared           -> "⚠️ ZFS <pool>: <problems>"
#   - problems cleared            -> "✅ ZFS <pool>: recovered"
#   - a NEW monthly scrub finish  -> "🧹 ZFS scrub <pool> finished: <N> ..."
#   - snapshot staleness / USEDSNAP pressure / missing datasets (see
#     modules/system/zfs-snapshots.nix for the policy it audits)
#   - NVMe SMART problems (critical_warning, temperature, spare, wear,
#     media errors) per /dev/nvme*n1 — services.smartd is off on this host
# Telegram delivery goes through the shared sender (hosts/trantor/telegram.nix),
# which owns the sing-box socks-proxy retry.
let
  systemdUser = neg.systemdUser lib;

  # State keeps, per pool, the last observed health (ok/problems) and the last
  # completed scrub date+errors so the script only alerts on real changes.
  stateDir = "/var/lib/telegram-zfs-watch";
  stateFile = "${stateDir}/state.json";

  # Snapshot checks follow the sanoid policy itself (single source of truth:
  # services.sanoid.datasets), so the watcher never audits a dataset that
  # modules/system/zfs-snapshots.nix does not snapshot.
  snapshotDatasets = lib.optionals config.features.system.zfsSnapshots.enable (
    lib.attrNames config.services.sanoid.datasets
  );

  # Rust watcher (pkgs.neg.telegram-notify): the thresholds, the sanoid
  # datasets and the tool paths come from the environment this wrapper exports.
  # NVMe health: smartd stays off on this host, so the watcher reads the
  # drives' SMART log itself; thresholds are deliberately drive-agnostic.
  watchScript = pkgs.writeShellScript "telegram-zfs-watch" ''
    export ZFS_WATCH_SENDER=${lib.getExe config.trantor.telegram.sender}
    export ZFS_WATCH_STATE_DIR=${stateDir}
    export ZFS_WATCH_STATE_FILE=${stateFile}
    # Hourly cadence + slack for one missed run.
    export ZFS_WATCH_SNAPSHOT_DATASETS="${lib.concatStringsSep " " snapshotDatasets}"
    export ZFS_WATCH_SNAPSHOT_MAX_AGE_HOURS=3
    export ZFS_WATCH_USEDSNAP_PERCENT=20
    export ZFS_WATCH_NVME=${lib.getExe pkgs.nvme-cli}
    export ZFS_WATCH_NVME_GLOB="/dev/nvme*n1"
    export ZFS_WATCH_NVME_MAX_TEMP_C=75
    export ZFS_WATCH_NVME_MIN_SPARE=10
    export ZFS_WATCH_NVME_MAX_USED=90
    exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-zfs-watch"} "$@"
  '';

in
# Telegram is gated on config.trantor.telegram.enable (see hosts/trantor/telegram.nix).
(lib.mkIf config.trantor.telegram.enable (
  systemdUser.mkOneshotTimer {
    name = "telegram-zfs-watch";
    description = "Watch ZFS pools, snapshots and NVMe SMART, alert to Telegram";
    timerDescription = "Check ZFS pools, snapshots and NVMe health every 10 minutes";
    script = "${watchScript}";
    onCalendar = "*-*-* *:0/10:00";
    restartSec = 30;
    stateDirectory = "telegram-zfs-watch";
  }
))
