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
  telegramDigestScript = pkgs.writeShellApplication {
    name = "telegram-digest";
    runtimeInputs = [
      pkgs.coreutils # date, cat, df for the digest body
      pkgs.inetutils # hostname of this machine
      pkgs.systemd # systemctl --failed for the failed-units check
      pkgs.zfs # zpool list for pool fill/health
    ];
    text = ''
      set -euo pipefail

      SEND=${config.odin.telegram.sender}/bin/telegram-send

      nl=$'\n'

      # Russian weekday from the numeric day-of-week (1=Mon .. 7=Sun).
      case "$(date '+%u')" in
        1) wd="понедельник" ;;
        2) wd="вторник" ;;
        3) wd="среда" ;;
        4) wd="четверг" ;;
        5) wd="пятница" ;;
        6) wd="суббота" ;;
        7) wd="воскресенье" ;;
      esac

      # --- header -----------------------------------------------------------
      msg="📋 Сводка: $wd, $(date '+%d.%m.%Y %H:%M %Z')"
        # Human uptime from /proc/uptime (portable — `uptime -p` flag support differs between procps and GNU coreutils' uptime on PATH).
        read -r up_s _ </proc/uptime
        up_s=$(( ''${up_s%.*} ))
        d=$(( up_s/86400 )); h=$(( (up_s%86400)/3600 )); m=$(( (up_s%3600)/60 ))
        if [ "$d" -gt 0 ]; then up_str="''${d}д ''${h}ч ''${m}м"
        elif [ "$h" -gt 0 ]; then up_str="''${h}ч ''${m}м"
        else up_str="''${m}м"; fi
        msg="$msg$nl🖥 $(hostname) · аптайм: $up_str"

      # --- ZFS pools ---------------------------------------------------------
      msg="$msg$nl$nl💾 Пулы ZFS:"
      if zfs_out="$(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null)"; then
        while IFS=$'\t' read -r pname psize palloc _pfree pcap phealth; do
          [ -n "$pname" ] || continue
          msg="$msg$nl  • $pname: $palloc/$psize · $pcap · $phealth"
        done <<< "$zfs_out"
      else
        msg="$msg$nl  (zpool недоступен)"
      fi

      # --- disk usage for / and /zero ----------------------------------------
      msg="$msg$nl$nl🖴 Диски:"
      disk_out="$(df -h --output=target,size,used,avail,pcent / /zero 2>/dev/null \
        || df -h --output=target,size,used,avail,pcent / 2>/dev/null \
        || df -h /)"
      while read -r mnt dsize dused davail dpcent; do
        case "$mnt" in
          /*) msg="$msg$nl  • $mnt: $dused/$dsize · свободно $davail · $dpcent" ;;
        esac
      done <<< "$disk_out"

      # --- failed units ------------------------------------------------------
      msg="$msg$nl$nl⚠️ Сбойные юниты:"
      if failed="$(systemctl --failed --no-legend --plain 2>/dev/null)"; then
        if [ -z "$failed" ]; then
          msg="$msg$nl  ✅ нет упавших юнитов"
        else
          while IFS= read -r fline; do
            [ -n "$fline" ] || continue
            unit=''${fline%% *}
            msg="$msg$nl  • $unit"
          done <<< "$failed"
        fi
      else
        msg="$msg$nl  (systemctl недоступен)"
      fi

      # --- send as a single Telegram message (sender retries ~1 min) --------
      # The digest header carries its own timestamp; keep the plain format.
      TELEGRAM_SEND_PLAIN=1 "$SEND" "$msg"
    '';
  };
in
lib.mkIf config.odin.telegram.enable {
  systemd.services."telegram-digest" = {
    description = "Send the daily 08:00 Telegram morning digest";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "telegram-digest";
      ExecStart = "${lib.getExe telegramDigestScript}";
      # A missed digest is not an incident, but retry transient send failures.
      Restart = "on-failure";
      RestartSec = 60;
    };
  };

  systemd.timers."telegram-digest" = {
    description = "Daily 08:00 Telegram morning digest";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # No Persistent=true: on VM snapshot restores / boot catch-ups this would
      # fire late "catch-up" digests; a missed one is fine.
      OnCalendar = "*-*-* 08:00:00";
      Unit = "telegram-digest.service";
    };
  };
}
