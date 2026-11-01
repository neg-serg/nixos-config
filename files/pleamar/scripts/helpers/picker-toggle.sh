#!/usr/bin/env bash
# pleamar-picker — the wallpaper deck's command line (scene `picker`, shells/picker/picker.plm).
#
#     pleamar-picker [toggle|open|close|reload|current]
#
#   toggle   open the deck, or close it if it is open (the compositor bind's verb)
#   open     open it, starting the scene if it is not running
#   close    close it (nothing happens when it is not running)
#   reload   read the wallpaper folder again
#   current  the wallpaper that was set last, one path (the same file the theme pipeline reads)
#
# The scene is an on-demand unit (`pleamar-picker.service`, not in autostart), so a fresh session
# has no picker process: the first verb that needs it starts the unit and waits for its socket,
# and every later one is a single `pleamar --say`.
set -u

PLEAMAR=${PLEAMAR:-$(command -v pleamar || echo /run/current-system/sw/bin/pleamar)}
SYSTEMCTL=${SYSTEMCTL:-$(command -v systemctl || echo /run/current-system/sw/bin/systemctl)}

say() { "$PLEAMAR" --say picker "$1" >/dev/null 2>&1; }

case ${1:-toggle} in
    toggle)
        # A running deck answers, and the scene decides what a toggle means.
        say "emit toggle_picker" && exit 0
        ;;
    open) ;;
    close)
        say "emit close_picker"
        exit 0
        ;;
    reload)
        say "emit reload"
        exit 0
        ;;
    current)
        cat "${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/wallpaper-path" 2>/dev/null
        exit 0
        ;;
    *)
        echo "usage: pleamar-picker [toggle|open|close|reload|current]" >&2
        exit 2
        ;;
esac

# Not running yet: start the unit and wait for the socket to answer (a scene takes a moment to
# come up, and its first frame longer).
"$SYSTEMCTL" --user start pleamar-picker.service || exit 1
for _ in $(seq 1 30); do
    say "emit open_picker" && exit 0
    sleep 0.1
done

echo "pleamar-picker: the wallpaper deck did not come up" >&2
exit 1
