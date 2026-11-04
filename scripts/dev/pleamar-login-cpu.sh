#!/usr/bin/env bash
#
# pleamar-login-cpu.sh — what the shell's scenes spent on CPU at login, and what they spend now.
#
# Why it exists: a scene's cgroup counters are cumulative since its unit started, and every
# scene starts at login (`hyprland-session.target`). A live sample therefore shows the average
# over the whole session — by the time anyone looks, the login burst (compiling the `.plm`,
# spawning the workers, the first frames) is already diluted. The burst is the expensive part,
# so the counters have to be read while it is still the whole story.
#
# The instrument is `pleamar-login-cpu.timer` (modules/user/nix-maid/gui/pleamar.nix): it fires
# one minute after the session target and writes one record per login under
# ${XDG_STATE_HOME:-~/.local/state}/pleamar/login-cpu/. A record is that moment's
# `systemctl show` dump plus the clocks it was taken at — the same text this script reads from
# the live manager, so both live and recorded numbers go through one parser. The script joins
# them, and the window and the steady state are told apart:
#
#   login window   CPU each scene used from its start until the record, and that window's rate
#                  in % of one core — the price of starting the shell
#   the session    CPU since the scene started, its average rate, RSS now and peak, restarts,
#                  and — when the record belongs to this login — CPU and rate since it
#
# Reads only: `systemctl --user show`, /proc/uptime and the records. Nothing is written and no
# scene is touched.
#
# Usage: pleamar-login-cpu.sh [--json | --watch SECONDS]
#   (no mode)    the login window, then the session so far
#   --json       the same numbers as one JSON object (a script, or a diff between two logins)
#   --watch N    a live N-second window: what the shell burns right now
#   -h, --help   this text
#
# Exit: 0 read (or nothing running), 2 not a graphical user session or no scenes found.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHELLS="$HERE/../../files/pleamar/shells"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/pleamar/login-cpu"
PROPS=(
  -p Id
  -p ActiveState
  -p CPUUsageNSec
  -p MemoryCurrent
  -p MemoryPeak
  -p NRestarts
  -p ActiveEnterTimestampMonotonic
)

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- arguments ------------------------------------------------------------
mode=report
watch=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) mode=json ;;
    --watch)
      watch=${2:-}
      case "$watch" in
        '' | *[!0-9]* | 0)
          echo "pleamar-login-cpu: --watch needs a positive whole number of seconds" >&2
          exit 2
          ;;
      esac
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "pleamar-login-cpu: unknown argument '$1' (try --help)" >&2
      exit 2
      ;;
  esac
  shift
done

# ---- guards ---------------------------------------------------------------
[ -d "$SHELLS" ] || {
  echo "pleamar-login-cpu: $SHELLS is not there (run it from the repository)" >&2
  exit 2
}
command -v systemctl > /dev/null || {
  echo "pleamar-login-cpu: no systemctl on PATH" >&2
  exit 2
}
session_us=$(systemctl --user show hyprland-session.target \
  -p ActiveEnterTimestampMonotonic --value 2> /dev/null || true)
case "$session_us" in
  '' | *[!0-9]* | 0)
    echo "pleamar-login-cpu: no graphical user session to read (hyprland-session.target)" >&2
    exit 2
    ;;
esac

SCENES=()
for directory in "$SHELLS"/*/; do
  # The trailing slash means a glob match is always a directory; a non-matching glob stays
  # literal, and `if` keeps that from failing the loop (and with it the script) at once.
  if [ -d "$directory" ]; then
    SCENES+=("$(basename "$directory")")
  fi
done
[ "${#SCENES[@]}" -gt 0 ] || {
  echo "pleamar-login-cpu: no scene in $SHELLS" >&2
  exit 2
}
scenes_json=$(printf '%s\n' "${SCENES[@]}" | jq -R -s -c 'split("\n") | map(select(. != ""))')

# The boot clock: it equals CLOCK_MONOTONIC (what ActiveEnterTimestamp* counts in) until the
# machine suspends. A login happens before any suspend can widen the gap, so a recorded window
# is exact; a live rate after a long suspend is understated by the suspended time. A record is
# never wrong that way — its `now` was taken at login.
now_us() { awk '{ printf "%.0f", $1 * 1000000 }' /proc/uptime; }

# A scene's cgroup includes its children (its `pleamar-sysmon`, its CAVA), so one unit row is
# the whole scene, not one process. `systemctl show` prints key=value blocks and has no JSON
# output, so the block walk is here, once, and both the live read and a record go through it.
# Output: id, state, cpu_ns, rss, peak, restarts, start_us — one TSV line per unit.
blocks() {
  awk -F= '
    function flush() {
      if (id != "") print id "\t" state "\t" cpu "\t" rss "\t" peak "\t" restarts "\t" start
      id = ""; state = ""; cpu = ""; rss = ""; peak = ""; restarts = ""; start = ""
    }
    /^[[:space:]]*$/ { flush(); next }
    {
      key = $1
      val = substr($0, index($0, "=") + 1)
      if (key == "Id") id = val
      else if (key == "ActiveState") state = val
      else if (key == "CPUUsageNSec") cpu = val
      else if (key == "MemoryCurrent") rss = val
      else if (key == "MemoryPeak") peak = val
      else if (key == "NRestarts") restarts = val
      else if (key == "ActiveEnterTimestampMonotonic") start = val
    }
    END { flush() }'
}

# The same rows as JSON objects, with a non-numeric value (systemd prints `[not set]` for an
# absent counter) read as zero. One unit of jq per source, so the numbers never reach a jq
# program as strings.
rows_json() {
  jq -R -s -c '
    def num: if test("^[0-9]+$") then tonumber else 0 end;
    split("\n") | map(select(length > 0) | split("\t")
      | { id: .[0], state: .[1], cpu_ns: (.[2] | num), rss: (.[3] | num),
          peak: (.[4] | num), restarts: (.[5] | num), start: (.[6] | num) })'
}

show_units() { systemctl --user show 'pleamar-*.service' "${PROPS[@]}" 2> /dev/null | blocks; }
live_json() { show_units | rows_json; }

# A record: header lines, then `--- units ---`, then the `systemctl show` dump.
rec_meta() { awk -v k="$2" '$1 == k { print $2; exit }' "$1" 2> /dev/null || true; }
rec_units() { sed -n '/^--- units ---$/,$p' "$1" | sed '1d'; }

# ---- which record belongs to this login -----------------------------------
# This login's record if one exists, else the newest from an earlier session — a tool run
# before the next login still shows the last login's numbers, labelled as such.
boot_id=$(cat /proc/sys/kernel/random/boot_id)
record=""
newest=0
older=""
for file in "$STATE"/*.rec; do
  [ -r "$file" ] || continue
  if [ "$(rec_meta "$file" boot)" = "$boot_id" ] \
    && [ "$(rec_meta "$file" session)" = "$session_us" ]; then
    record="$file"
    break
  fi
  mtime=$(stat -c %Y "$file" 2> /dev/null || echo 0)
  if [ "$mtime" -gt "$newest" ]; then
    newest="$mtime"
    older="$file"
  fi
done
[ -n "$record" ] || record="$older"

same_login=false
recorded_at=""
rec_json=null
rec_now=""
if [ -n "$record" ]; then
  recorded_at=$(rec_meta "$record" at)
  rec_now=$(rec_meta "$record" now)
fi
# A record that lost its header (a half-written file, an interrupted login) is no record:
# the numbers below are relative to `now`, and a missing clock is not something to guess at.
case "$rec_now" in
  '' | *[!0-9]*)
    record=""
    recorded_at=""
    ;;
esac
if [ -n "$record" ]; then
  if [ "$(rec_meta "$record" session)" = "$session_us" ]; then
    same_login=true
  fi
  # How far into the session the record was taken: the timer makes it a minute, anything
  # else has to say its age, because a window of ten minutes is not the login burst.
  rec_session=$(rec_meta "$record" session)
  case "$rec_session" in '' | *[!0-9]*) rec_session=0 ;; esac
  rec_age_s=$(((rec_now - rec_session) / 1000000))
  rec_json=$(rec_units "$record" | blocks | rows_json \
    | jq -c --argjson now "$rec_now" '{ now: $now, units: . }')
fi

# ---- --watch: a live window ----------------------------------------------
# A scene that restarted inside the window has a counter that went backwards; the delta is
# clamped to zero, so a total errs low instead of printing a negative cost.
if [ "$watch" -gt 0 ]; then
  before=$(live_json)
  t0=$(now_us)
  sleep "$watch"
  t1=$(now_us)
  after=$(live_json)
  window=$(jq -n --argjson scenes "$scenes_json" --argjson b "$before" --argjson a "$after" \
    --argjson t0 "$t0" --argjson t1 "$t1" '
    def cpu($units; $id):
      (first($units[]? | select(.id == $id)) // null) as $u
      | if $u then $u.cpu_ns else 0 end;
    ($t1 - $t0) / 1e6 as $elapsed
    | [ $scenes[] as $scene
        | ("pleamar-" + $scene + ".service") as $id
        | cpu($b; $id) as $c0
        | cpu($a; $id) as $c1
        | { scene: $scene,
            cpu_s: (if $c1 > $c0 then ($c1 - $c0) / 1e9 else 0 end),
            pct: (if $elapsed > 0 and $c1 > $c0 then ($c1 - $c0) / 1e9 / $elapsed * 100 else 0 end) } ]
    | { window_s: $elapsed,
        total_pct: (if $elapsed > 0 then (map(.cpu_s) | add // 0) / $elapsed * 100 else 0 end),
        rows: (map(select(.cpu_s > 0))) }')
  printf 'pleamar-login-cpu: a %d s window\n' "$(printf '%s' "$window" | jq -r '.window_s | floor')"
  printf '  %-13s %8s %8s\n' scene "cpu(s)" "%core"
  printf '%s' "$window" | jq -r '.rows[] | [.scene, .cpu_s, .pct] | @tsv' \
    | while IFS=$'\t' read -r name cpu pct; do
      printf '  %-13s %8.3f %8.2f\n' "$name" "$cpu" "$pct"
    done
  printf '  %-13s %8s %8.2f\n' total "" "$(printf '%s' "$window" | jq -r '.total_pct')"
  exit 0
fi

# ---- the numbers ----------------------------------------------------------
data=$(jq -n \
  --argjson now "$(now_us)" \
  --argjson session "$session_us" \
  --argjson scenes "$scenes_json" \
  --argjson live "$(live_json)" \
  --argjson rec "$rec_json" '
  def pct($cpu; $up): if $up > 0 then $cpu / $up * 100 else 0 end;
  def recunits: if $rec == null then [] else $rec.units end;

  [ $scenes[] as $scene
    | ("pleamar-" + $scene + ".service") as $id
    | (first($live[]? | select(.id == $id)) // null) as $u
    | (first(recunits[]? | select(.id == $id)) // null) as $r
    | (if $u then $u.start else 0 end) as $start
    | (if $u then $u.cpu_ns else 0 end) as $cpu_ns
    | (if $r then $r.cpu_ns else null end) as $login_ns
    | (if $r then $rec.now - $r.start else null end) as $login_us
    | (if $u and $start > 0 then ($now - $start) / 1e6 else 0 end) as $up
    | {
        scene: $scene,
        active: (($u.state // "inactive") == "active"),
        up_s: $up,
        cpu_s: ($cpu_ns / 1e9),
        pct: pct($cpu_ns / 1e9; $up),
        rss_mb: (if $u then $u.rss / 1048576 else 0 end),
        peak_mb: (if $u then $u.peak / 1048576 else 0 end),
        restarts: (if $u then $u.restarts else 0 end),
        login_cpu_s: (if $login_ns == null then null else $login_ns / 1e9 end),
        login_up_s: (if $login_us == null then null else $login_us / 1e6 end),
        login_pct: (if $login_us == null then null else pct($login_ns / 1e9; $login_us / 1e6) end),
        login_peak_mb: (if $r then $r.peak / 1048576 else null end),
        # A unit that restarted since the record has a different instance: its counters start
        # again at that moment, so a difference would be a small negative. Leave it empty.
        since_cpu_s: (if $login_ns == null or $u == null or $u.start != $r.start then null
                      else ($cpu_ns - $login_ns) / 1e9 end),
        since_pct: (if $login_us == null or $u == null or $u.start != $r.start or $up * 1e6 <= $login_us
                    then null
                    else pct(($cpu_ns - $login_ns) / 1e9; ($up * 1e6 - $login_us) / 1e6) end)
      }
  ] as $rows
  | {
      session_s: (($now - $session) / 1e6),
      scenes: $rows,
      totals: {
        cpu_s: ($rows | map(.cpu_s) | add // 0),
        login_cpu_s: ($rows | map(.login_cpu_s // 0) | add // 0),
        login_window_s: ($rows | map(.login_up_s // 0) | max // 0),
        rss_mb: ($rows | map(.rss_mb) | add // 0)
      }
    }
')

if [ "$mode" = json ]; then
  printf '%s\n' "$data" | jq --arg record "$record" --arg at "$recorded_at" \
    --argjson same "$same_login" '
    { record: (if $record == "" then null else $record end),
      recorded_at: (if $at == "" then null else $at end),
      record_is_this_login: $same } + .'
  exit 0
fi

if ! printf '%s' "$data" | jq -e 'any(.scenes[]; .active)' > /dev/null; then
  echo "pleamar-login-cpu: no pleamar scene is running in this session"
  exit 0
fi

active_count=$(printf '%s' "$data" | jq -r '[.scenes[] | select(.active)] | length')
read -r total_cpu session_s total_login total_window total_rss < <(
  printf '%s' "$data" | jq -r '.totals as $t | .session_s as $s |
    "\($t.cpu_s) \($s) \($t.login_cpu_s) \($t.login_window_s) \($t.rss_mb)"'
)
printf 'pleamar-login-cpu: session %.0f s · %s of %d scene(s) running · %.2f s CPU in total (%.2f %% of a core since login)\n' \
  "$session_s" "$active_count" "${#SCENES[@]}" "$total_cpu" \
  "$(awk -v c="$total_cpu" -v s="$session_s" 'BEGIN { printf "%.2f", (s > 0 ? c / s * 100 : 0) }')"
stopped=$(printf '%s' "$data" | jq -r '[.scenes[] | select((.active | not) and .cpu_s > 0.001) | .scene] | join(", ")')
if [ -n "$stopped" ]; then
  printf '  not running now (CPU from earlier in the session): %s\n' "$stopped"
fi

if [ "$same_login" = true ]; then
  # A record taken by hand hours in is a window, but not the login one — say which it is
  # instead of letting the label do the lying.
  if [ "$rec_age_s" -le 180 ]; then
    printf '\nlogin window — record %s, %s s into the session\n' "$recorded_at" "$rec_age_s"
  else
    printf '\nrecord window — %s, taken %s s into the session (not the login burst)\n' \
      "$recorded_at" "$rec_age_s"
  fi
  printf '  %-13s %8s %8s %8s %8s\n' scene "up(s)" "cpu(s)" "%core" "peak"
  printf '%s' "$data" | jq -r '.scenes[] | select(.login_cpu_s != null) |
      [.scene, .login_up_s, .login_cpu_s, .login_pct, .login_peak_mb] | @tsv' \
    | while IFS=$'\t' read -r name up cpu pct peak; do
      printf '  %-13s %8.1f %8.3f %8.2f %7.1fM\n' "$name" "$up" "$cpu" "$pct" "$peak"
    done
  printf '  %-13s %8s %8.3f %8.2f\n' total "" "$total_login" \
    "$(awk -v c="$total_login" -v w="$total_window" 'BEGIN { printf "%.2f", (w > 0 ? c / w * 100 : 0) }')"
elif [ -n "$record" ]; then
  printf '\nlogin window — no record of this login (the newest is %s, an earlier session)\n' "$recorded_at"
else
  printf '\nlogin window — not recorded yet (pleamar-login-cpu.timer takes one a minute after the session target)\n'
fi

printf '\nthe session so far\n'
if [ "$same_login" = true ]; then
  printf '  %-13s %8s %8s %8s %8s %8s %4s %10s %8s\n' \
    scene "up(s)" "cpu(s)" "%core" "rss" "peak" "#rst" "since(s)" "since %"
  printf '%s' "$data" | jq -r '.scenes[] | select(.active) |
      [.scene, .up_s, .cpu_s, .pct, .rss_mb, .peak_mb, .restarts,
       (.since_cpu_s | if . == null then "-" else ((. * 1000 | round) / 1000 | tostring) end),
       (.since_pct | if . == null then "-" else ((. * 100 | round) / 100 | tostring) end)] | @tsv' \
    | while IFS=$'\t' read -r name up cpu pct rss peak restarts since since_pct; do
      printf '  %-13s %8.1f %8.3f %8.2f %7.1fM %7.1fM %4s %10s %8s\n' \
        "$name" "$up" "$cpu" "$pct" "$rss" "$peak" "$restarts" "$since" "$since_pct"
    done
else
  printf '  %-13s %8s %8s %8s %8s %8s %4s\n' scene "up(s)" "cpu(s)" "%core" "rss" "peak" "#rst"
  printf '%s' "$data" | jq -r '.scenes[] | select(.active) |
      [.scene, .up_s, .cpu_s, .pct, .rss_mb, .peak_mb, .restarts] | @tsv' \
    | while IFS=$'\t' read -r name up cpu pct rss peak restarts; do
      printf '  %-13s %8.1f %8.3f %8.2f %7.1fM %7.1fM %4s\n' \
        "$name" "$up" "$cpu" "$pct" "$rss" "$peak" "$restarts"
    done
fi
printf '  %-13s %8s %8.3f %8.2f %7.1fM\n' total "" "$total_cpu" \
  "$(awk -v c="$total_cpu" -v s="$session_s" 'BEGIN { printf "%.2f", (s > 0 ? c / s * 100 : 0) }')" \
  "$total_rss"
