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
# The deck's own `open` fact, one word: `true` / `false` (empty when the scene does not answer).
deck_open() { "$PLEAMAR" --say picker "get open" 2>/dev/null | tail -n 1; }

case ${1:-toggle} in
    toggle)
        # A running deck answers, and the scene decides what a toggle means. When it closed, the
        # process goes with it: a closed scene keeps a 1x1 "keeper" surface and stays resident,
        # which measured 17% of a core, ~100 MB RSS and a few points of GPU with nothing on
        # screen. The unit is on-demand, so the next verb starts it again.
        #
        # The close runs through the scene's own animation, so the fact flips a moment after the
        # `emit` returns — asking once right away reads the *old* value and the unit would never
        # stop (measured). Wait for the value to change, then decide; a toggle the scene swallowed
        # changes nothing, and then the unit stays up, which is the safe direction.
        was="$(deck_open)"
        if say "emit toggle_picker"; then
            for _ in $(seq 1 20); do
                now="$(deck_open)"
                if [ -n "$now" ] && [ "$now" != "$was" ]; then
                    [ "$now" = "false" ] && "$SYSTEMCTL" --user stop pleamar-picker.service
                    break
                fi
                sleep 0.1
            done
            exit 0
        fi
        ;;
    open) ;;
    close)
        say "emit close_picker"
        # Same reason as `toggle`: nothing on screen means nothing to keep running.
        "$SYSTEMCTL" --user stop pleamar-picker.service
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
