# Per-window keyboard layout switching for Hyprland.
# us for hotkey-heavy window classes, ru for everything else.
set -u

hyprctl_bin='@hyprctlBin@'
awk_bin='@awkBin@'
sleep_bin='@sleepBin@'

us_classes='@usClasses@'
us_idx='@usIdx@'
ru_idx='@ruIdx@'
poll_sec='@pollSec@'

# `hyprctl activewindow` lists the focused window with a TAB-indented
# "class:" line — match optional leading whitespace.
focused_class() {
  "$hyprctl_bin" activewindow 2> /dev/null | "$awk_bin" -F': ' '/^[ \t]*class:/ {print $2; exit}'
}

current=""
while :; do
  class="$(focused_class)"
  if [ "$class" != "$current" ]; then
    current="$class"
    case " $us_classes " in
      *" $class "*) idx="$us_idx" ;;
      *) idx="$ru_idx" ;;
    esac
    # switchxkblayout takes the layout INDEX directly as the command
    # ("set" is not a keyword); `all` keeps every keyboard (kanata's
    # virtual device included) on the same layout. Verified against
    # Hyprland 0.55.4 (src/debug/HyprCtl.cpp switchXKBLayoutRequest).
    "$hyprctl_bin" switchxkblayout all "$idx" 2> /dev/null || true
  fi
  "$sleep_bin" "$poll_sec"
done
