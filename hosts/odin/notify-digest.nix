# Daily 08:00 Telegram morning digest for odin (auto-imported from hosts/odin/).
#
# Composes ONE compact Russian message (weekday header, ZFS pool fill, disk
# usage for / and /zero, failed units) and posts it to the Telegram chat from
# secrets/telegram.sops.yaml. api.telegram.org is only reachable through the
# user sing-box socks proxy (127.0.0.1:10808), so the send retries a few times.
#
# Everything is gated on secrets/telegram.sops.yaml existing; without the secret
# file the whole unit stays disabled (same pattern as the other Telegram units
# in hosts/odin/services.nix).
{ config, lib, pkgs, inputs, ... }:

let
  telegramDigestScript = pkgs.writeShellApplication {
    name = "telegram-digest";
    runtimeInputs = [
      pkgs.curl # HTTP(S) client for the Telegram Bot API
      pkgs.coreutils # date, seq, sleep, cat, df
      pkgs.inetutils # hostname of this machine
      pkgs.procps # uptime -p for the human-readable uptime line
      pkgs.systemd # systemctl --failed for the failed-units check
      pkgs.zfs # zpool list for pool fill/health
    ];
    text = ''
      set -euo pipefail

      TOKEN="$(cat ${config.sops.secrets."telegram/bot-token".path})"
      CHAT_ID="$(cat ${config.sops.secrets."telegram/chat-id".path})"

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
      msg="$msg$nl🖥 $(hostname) · аптайм: $(uptime -p)"

      # --- ZFS pools ---------------------------------------------------------
      msg="$msg$nl$nl💾 Пулы ZFS:"
      if zfs_out="$(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null)"; then
        while IFS=$'\t' read -r pname psize palloc pfree pcap phealth; do
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

      # --- send as a single Telegram message, retrying for a while ------------
      for _ in $(seq 1 12); do
        if curl -sf -o /dev/null \
          --proxy socks5h://127.0.0.1:10808 \
          --data-urlencode "chat_id=$CHAT_ID" \
          --data-urlencode "text=$msg" \
          "https://api.telegram.org/bot$TOKEN/sendMessage"; then
          exit 0
        fi
        sleep 5
      done
      echo "telegram-digest: could not deliver the digest after 12 attempts" >&2
      exit 1
    '';
  };
in
lib.mkIf (builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml")) {
  sops.secrets."telegram/bot-token" = {
    sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
    key = "bot-token";
    owner = "root";
    mode = "0400";
  };
  sops.secrets."telegram/chat-id" = {
    sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
    key = "chat-id";
    owner = "root";
    mode = "0400";
  };

  systemd.services."telegram-digest" = {
    description = "Send the daily 08:00 Telegram morning digest";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
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
