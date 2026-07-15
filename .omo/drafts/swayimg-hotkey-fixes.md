# Draft: swayimg-hotkey-fixes

**intent**: clear
**review_required**: false
**status**: awaiting-approval

## Key Findings

### Root Cause: API mismatch between upstream artemsen/swayimg and neg-serg/swayimg fork

| API | Upstream (table) | Fork (tuple) |
|-----|------------------|--------------|
| `get_position()` | `{x=..., y=...}` | `x, y` |
| `get_window_size()` | `{width=..., height=...}` | `width, height` |
| `get_mouse_pos()` | `{x=..., y=...}` | `x, y` |

The fork switched from Lua tables to tuples. The init.lua safe wrapper `get_pos()` was written for the upstream table API. On the fork:
```lua
local pos = swayimg.viewer.get_position()  -- pos = x (first return value, a number)
pos.x  -- nil (numbers have no .x property)
-- wrapper always returns {x=0, y=0}
```

**Result**: ALL panning starts from (0,0), never from current position. After first pan, position becomes (-50,0) etc. But if image fits window, fixup_position() immediately resets to center.

### Secondary issues found:
1. Slideshow panning `p.x-50` where `p` is a number → Lua error (caught, silently breaks)
2. `Ctrl-Shift-comma` on US layout → XKB produces `less` keysym, not `comma` → binding never matches
3. `bind_reset()` removes zoom (`+`/`-`), reset (`BackSpace`), mouse scroll → never restored
4. Gallery missing `Left`/`Right` arrow bindings
5. `fixup_position()` with `free_move=false` (default) forbids panning when image fits window

### Fork has `enable_freemove(bool)` API — can fix #5 from Lua

### Decisions
- Fix tuple unpacking in all `get_position()` calls (both viewer and slideshow)
- Add `enable_freemove(true)` to viewer init
- Add `Ctrl-Shift-less` binding alongside `Ctrl-Shift-comma`
- Restore zoom/reset/scroll bindings lost by `bind_reset()`
- Add `Left`/`Right` to gallery
- Not touching: `get_window_size()` and `get_mouse_pos()` — not currently used in hotkeys

### Pending action
Write `.omo/plans/swayimg-hotkey-fixes.md` with exact task batches.
