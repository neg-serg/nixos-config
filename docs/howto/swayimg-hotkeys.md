# swayimg Custom Hotkeys

Custom bindings for swayimg live in `modules/media/images/swayimg/conf/bindings.conf` and call
`~/.local/bin/swayimg-actions.sh`. The tables below list every non-default shortcut that runs this
helper script. Unless noted otherwise, the bindings act on the file that is currently highlighted in
the given mode.

The helper now detaches from swayimg immediately, so long-running moves or wallpaper renders do not
freeze the viewer. Every action also posts a short status message (overlay in the bottom-right
corner) describing what is happening — e.g., how many files were moved and where they went. Set
`SWAYIMG_ACTIONS_SYNC=1` before calling the script if you ever need to run it synchronously from a
terminal.

Enable verbose logging with `SWAYIMG_ACTIONS_DEBUG=1` before launching swayimg to capture clipboard
failures (such as `wl-copy` errors) in `~/tmp/swayimg-actions.log`. Use
`SWAYIMG_ACTIONS_DEBUG=stderr` to mirror the same lines to the terminal; entries still land in the
log file either way so you can read them later via `tail -f ~/tmp/swayimg-actions.log`.

## Viewer Mode

| Key | Script action | Effect | | --- | ------------- | ------ | | `Ctrl+1` | `wall-mono` | Convert
the current image to two colors and send it to `swww` as the wallpaper. | | `Ctrl+2` | `wall-fill` |
Scale/crop the image to fill the monitor (center crop) and set it as wallpaper. | | `Ctrl+3` |
`wall-full` | Same as `wall-fill`; retained for muscle memory. | | `Ctrl+4` | `wall-tile` | Render a
screen-sized tiled pattern from the image and set it as wallpaper. | | `Ctrl+5` | `wall-center` |
Center the image on the wallpaper canvas with black borders. | | `Ctrl+w` | `wall-cover` | Cover the
monitor with the image (crop as needed) and set it as wallpaper. | | `Ctrl+c` | `cp` | Copy the file
into a directory picked via the rofi prompt. | | `c` | `copyname` | Copy the absolute file path to
the clipboard and show `pic-notify` when available. | | `Ctrl+d`, `d` |
`mv … $HOME/trash/1st-level/pic` | Move the file into the staged trash folder. | | `v` | `mv` | Move
the file into a directory selected via the rofi prompt. | | `Ctrl+comma` | `rotate-left` | Rotate
the file 270° using ImageMagick (`mogrify`). | | `Ctrl+less` | `rotate-ccw` | Rotate the file 90°
counter-clockwise. | | `Ctrl+period` | `rotate-right` | Rotate the file 90° clockwise. | |
`Ctrl+slash` | `rotate-180` | Rotate the file 180°. | | `r` | `repeat` | Replay the last `mv`/`cp`
destination (uses the cached directory recorded by `proc`). | | `Shift+m` | `range-mark` | Mark the
current file as the start/end anchor for range operations. | | `Shift+r` | `range-clear` | Drop the
saved range anchor. | | `Shift+d` | `range-trash` | Move every file between the mark and the current
file into the staged trash. | | `Shift+v` | `range-mv` | Prompt for a directory and move the marked
range there. | | `Shift+c` | `range-cp` | Prompt for a directory and copy the marked range there. |

## Gallery Mode

| Key | Script action | Effect | | --- | ------------- | ------ | | `c` | `copyname` | Copy the
highlighted file’s absolute path to the clipboard. | | `Ctrl+c` | `cp` | Copy the highlighted file
into a rofi-selected directory. | | `Ctrl+d`, `d` | `mv … $HOME/trash/1st-level/pic` | Send the
highlighted file to the staged trash. | | `r` | `repeat` | Repeat the previous `mv`/`cp` to its
cached destination. | | `v` | `mv` | Move the highlighted file via a rofi prompt. | | `Ctrl+comma` |
`rotate-left` | Rotate the highlighted file 270°. | | `Ctrl+less` | `rotate-ccw` | Rotate the
highlighted file 90° counter-clockwise. | | `Ctrl+period` | `rotate-right` | Rotate the highlighted
file 90° clockwise. | | `Ctrl+slash` | `rotate-180` | Rotate the highlighted file 180°. | | `Ctrl+1`
| `wall-mono` | Push the highlighted image to `swww` in monochrome mode. | | `Ctrl+2` | `wall-fill`
| Fill the monitor with the highlighted image and set it as wallpaper. | | `Ctrl+3` | `wall-full` |
Alias for `wall-fill`. | | `Ctrl+4` | `wall-tile` | Tile the highlighted image and set it as
wallpaper. | | `Ctrl+5` | `wall-center` | Center the highlighted image on the wallpaper canvas. | |
`Ctrl+w` | `wall-cover` | Cover the monitor with the highlighted image and set it as wallpaper. | |
`Shift+m` | `range-mark` | Mark the current tile as the start/end anchor for range moves. | |
`Shift+r` | `range-clear` | Drop the saved range anchor. | | `Shift+d` | `range-trash` | Move the
marked range (inclusive) into the staged trash. | | `Shift+v` | `range-mv` | Prompt for a directory
and move the marked range there. | | `Shift+c` | `range-cp` | Prompt for a directory and copy the
marked range there. |

## Slideshow Mode

| Key | Script action | Effect | | --- | ------------- | ------ | | `Ctrl+d` |
`mv … $HOME/trash/1st-level/pic` | Move the current slide into the staged trash folder. | |
`Shift+m` | `range-mark` | Mark the slide as a range anchor (carried into other modes). | |
`Shift+r` | `range-clear` | Drop the saved range anchor. | | `Shift+d` | `range-trash` | Move the
inclusive range between the mark and the current slide to trash. | | `Shift+v` | `range-mv` | Prompt
for a directory and move the marked range there. | | `Shift+c` | `range-cp` | Prompt for a directory
and copy the marked range there. |

### Notes

- All file moves/copies are blocked on VCS directories by `_is_vcs_path` to keep repo trees intact.
- Wallpaper helpers rely on `swww`. The script starts the daemon on demand and serializes calls via
  a lock directory so multiple instances do not collide.
- Range actions require launching swayimg via `sx` (or the `swayimg-first.sh` wrapper) so that the
  helper can read the per-session playlist and cache the range anchor under
  `$XDG_DATA_HOME/swayimg/<session>.{list,range}`.
