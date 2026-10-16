set -euo pipefail

SEND=@sender@/bin/telegram-send

# The digest runs as a system service (root), so the user manager has to be
# named explicitly: a bare `systemctl --user` would query root's own
# (nonexistent) manager. Filled in by notify-digest.nix, e.g. "neg@.host".
UM=@userManager@

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
read -r up_s _ < /proc/uptime
up_s=$((${up_s%.*}))
d=$((up_s / 86400))
h=$(((up_s % 86400) / 3600))
m=$(((up_s % 3600) / 60))
if [ "$d" -gt 0 ]; then
  up_str="${d}д ${h}ч ${m}м"
elif [ "$h" -gt 0 ]; then
  up_str="${h}ч ${m}м"
else up_str="${m}м"; fi
msg="$msg$nl🖥 $(hostname) · аптайм: $up_str"

# --- ZFS pools ---------------------------------------------------------
msg="$msg$nl$nl💾 Пулы ZFS:"
if zfs_out="$(zpool list -H -o name,size,alloc,free,cap,health 2> /dev/null)"; then
  while IFS=$'\t' read -r pname psize palloc _pfree pcap phealth; do
    [ -n "$pname" ] || continue
    msg="$msg$nl  • $pname: $palloc/$psize · $pcap · $phealth"
  done <<< "$zfs_out"
else
  msg="$msg$nl  (zpool недоступен)"
fi

# --- disk usage for / and /zero ----------------------------------------
msg="$msg$nl$nl🖴 Диски:"
disk_out="$(df -h --output=target,size,used,avail,pcent / /zero 2> /dev/null \
  || df -h --output=target,size,used,avail,pcent / 2> /dev/null \
  || df -h /)"
while read -r mnt dsize dused davail dpcent; do
  case "$mnt" in
    /*) msg="$msg$nl  • $mnt: $dused/$dsize · свободно $davail · $dpcent" ;;
  esac
done <<< "$disk_out"

# --- failed units ------------------------------------------------------
msg="$msg$nl$nl⚠️ Сбойные юниты:"
if failed="$(systemctl --failed --no-legend --plain 2> /dev/null)"; then
  if [ -z "$failed" ]; then
    msg="$msg$nl  ✅ нет упавших юнитов"
  else
    while IFS= read -r fline; do
      [ -n "$fline" ] || continue
      unit=${fline%% *}
      msg="$msg$nl  • $unit"
    done <<< "$failed"
  fi
else
  msg="$msg$nl  (systemctl недоступен)"
fi

# --- failed user units -------------------------------------------------
# The digest is a system service (root), so the user manager is addressed via
# --machine: listenbrainz-mpd and the other per-user services are not covered
# by the system `systemctl --failed` above.
if userfailed="$(systemctl --user --machine "$UM" --failed --no-legend --plain 2> /dev/null)"; then
  if [ -n "$userfailed" ]; then
    msg="$msg$nl  👤 пользовательские:"
    while IFS= read -r uline; do
      [ -n "$uline" ] || continue
      uunit=${uline%% *}
      msg="$msg$nl    • $uunit"
    done <<< "$userfailed"
  fi
fi

# --- scrobbling --------------------------------------------------------
# listenbrainz-mpd (user unit) and koito (system unit, the local hub).
lb_state="$(systemctl --user --machine "$UM" is-active listenbrainz-mpd.service 2> /dev/null || true)"
koito_state="$(systemctl is-active koito.service 2> /dev/null || true)"
msg="$msg$nl$nl🎧 Скробблинг: listenbrainz-mpd: ${lb_state:-unknown} · koito: ${koito_state:-unknown}"

# --- send as a single Telegram message (sender retries ~1 min) --------
# The digest header carries its own timestamp; keep the plain format.
TELEGRAM_SEND_PLAIN=1 "$SEND" "$msg"

# --- mirror onto the local BBS board ----------------------------------
# @minibbsPost@ is the minibbs-post helper (empty when the board is disabled).
# One thread per day: the subject is the date, the body is the same message.
# The helper never exits non-zero, so the Telegram send above stays the only
# delivery path that can fail this unit.
MINIBBS_POST="@minibbsPost@"
if [ -n "$MINIBBS_POST" ]; then
  printf '%s\n' "$msg" | "$MINIBBS_POST" digest digest "Сводка $(date '+%d.%m.%Y')" || true
fi
