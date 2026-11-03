#!/usr/bin/env bash
#
# check-pleamar-health.sh — a read-only check-up of the running shell.
#
# What it looks at (nothing is written and nothing is pressed):
#   scenes    one process per scene, and what each holds: fds, threads, RSS
#   helpers   the helpers a live scene keeps appear once (a leaked second copy is
#             the usual cause of a scene that "answered twice")
#   bindings  Hyprland bindings that would run the same action twice, and keys
#             that carry several actions by design (a one-shot plus the submap
#             reset, or a press and a release — Hyprland's own "multiple binds
#             to one key")
#   journal   panics from pleamar since boot, and core dumps for it
#
# Usage: check-pleamar-health.sh [REPO_ROOT]   (default: two levels up from here)
#
# Exit: 0 all well, 1 warnings, 2 something could not be read.
set -euo pipefail

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
SHELLS="$REPO_ROOT/files/pleamar/shells"
if [ ! -d "$SHELLS" ]; then
  echo "pleamar-health: $SHELLS is not there (pass the repository root)" >&2
  exit 2
fi

warnings=0
warn() {
  printf '  warn %s\n' "$*"
  warnings=$((warnings + 1))
}
row() {
  printf '  %-13s %7s %5s %7s %6s\n' "$@"
}

# ---- scenes ---------------------------------------------------------------
echo "pleamar-health: scenes"
row scene pid fds threads rss
running=0
SCENE_PIDS=""
for directory in "$SHELLS"/*/; do
  scene=$(basename "$directory")
  pids=$(pgrep -f -- "pleamar --scene .*/shells/$scene/" || true)
  count=$(printf '%s\n' "$pids" | sed '/^$/d' | wc -l)
  if [ "$count" -gt 1 ]; then
    warn "$scene runs $count times (pids $(echo "$pids" | tr '\n' ' '))"
    continue
  fi
  [ "$count" -eq 1 ] || continue
  running=$((running + 1))
  pid=$(printf '%s\n' "$pids" | head -n 1)
  fds=$(fd --max-depth 1 . "/proc/$pid/fd" 2> /dev/null | wc -l)
  threads=$(awk '/^Threads:/{print $2}' "/proc/$pid/status" 2> /dev/null || echo '?')
  rss_kb=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2> /dev/null || echo 0)
  row "$scene" "$pid" "$fds" "$threads" "$((rss_kb / 1024))M"
  SCENE_PIDS="$SCENE_PIDS $scene:$pid"
done
[ "$running" -gt 0 ] || echo "  (no scene is running)"
echo "  $running scene(s) up"

# ---- helpers: a scene starts each of its own once -------------------------
# Not "one in the whole session": the bar and the panels each keep a `pleamar-sysmon`
# of their own, which is the design. What must not happen is one scene starting the
# same helper twice (a leaked copy is the usual cause of a card that answers twice).
echo "pleamar-health: helpers"
checking=0
for pair in $SCENE_PIDS; do
  scene=${pair%%:*}
  pid=${pair##*:}
  duplicates=$(for child in $(ps -o pid= --ppid "$pid" 2> /dev/null); do
    cat "/proc/$child/comm" 2> /dev/null || true
  done | sort | uniq -d)
  if [ -n "$duplicates" ]; then
    while read -r helper; do
      warn "$scene started $helper more than once"
    done <<< "$duplicates"
  else
    printf '  ok   %s: one of each\n' "$scene"
  fi
  checking=$((checking + 1))
done
[ "$checking" -gt 0 ] || echo "  (no scene is running)"

# ---- duplicate composer bindings -----------------------------------------
echo "pleamar-health: bindings"
if command -v hyprctl > /dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v jq > /dev/null 2>&1; then
  entries=$(hyprctl binds -j 2> /dev/null | jq -r '.[] | "\(.modmask)\t\(.key)\t\(.submap // "")\t\(.release)\t\(.dispatcher)"' || true)
  # The same bind twice (same modifiers, key, submap, release *and* dispatcher)
  # would run one action twice — that is a mistake.
  exact=$(printf '%s\n' "$entries" | sort | uniq -d)
  if [ -n "$exact" ]; then
    warn "$(printf '%s\n' "$exact" | wc -l) binding(s) registered twice with the same dispatcher (both would run)"
    printf '%s\n' "$exact" | awk -F'\t' '{ printf "       key %s (mods %s%s) %s\n", $2, $1, ($3 == "" ? "" : " in " $3), $5 }'
  else
    # Several binds on one key with different dispatchers is Hyprland's
    # supported "multiple binds to one key": this config's one-shots are the
    # action plus `submap reset` (`binde_reset`), and M1+GRAVE is a press and
    # a release. Worth a line, not a warning.
    repeated=$(printf '%s\n' "$entries" | awk -F'\t' '
            { key = $1 FS $2 FS $3 FS $4; count[key]++ }
            END { for (k in count) if (count[k] > 1) print k }
        ')
    if [ -n "$repeated" ]; then
      echo "  note $(printf '%s\n' "$repeated" | wc -l) key(s) carry more than one action by design (one-shot + submap reset, or press + release)"
    else
      echo "  ok   no duplicate bindings"
    fi
  fi
else
  echo "  skip no Hyprland session (HYPRLAND_INSTANCE_SIGNATURE)"
fi

# ---- what went wrong since boot ------------------------------------------
echo "pleamar-health: journal"
if command -v journalctl > /dev/null 2>&1; then
  panics=$(journalctl --user -b --no-pager 2> /dev/null | rg -c 'pleamar\[[0-9]+\]: .*(panicked|fatal)' || true)
  if [ "${panics:-0}" -gt 0 ]; then
    warn "pleamar logged $panics panic/fatal line(s) since boot (journalctl --user -b | rg panicked)"
  else
    echo "  ok   no panics"
  fi
else
  echo "  skip no journalctl"
fi
if command -v coredumpctl > /dev/null 2>&1; then
  cores=$(coredumpctl --no-pager list 2> /dev/null | rg -c 'pleamar' || true)
  if [ "${cores:-0}" -gt 0 ]; then
    warn "$cores core dump(s) for pleamar this boot (coredumpctl list pleamar)"
  else
    echo "  ok   no core dumps"
  fi
else
  echo "  skip no coredumpctl"
fi

if [ "$warnings" -gt 0 ]; then
  echo "pleamar-health: $warnings warning(s)"
  exit 1
fi
echo "pleamar-health: all well"
exit 0
