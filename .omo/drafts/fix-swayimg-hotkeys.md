---
slug: fix-swayimg-hotkeys
status: awaiting-approval
intent: unclear
review_required: true
pending-action: write .omo/plans/fix-swayimg-hotkeys.md
approach: Audit every keybinding in init.lua against the swayimg Lua API (neg-serg fork), fix functional bugs, reconcile Latin/Russian layout inconsistencies, fill missing navigation gaps across viewer/gallery/slideshow modes, and update docs.
---

# Draft: fix-swayimg-hotkeys

## Components (topology ledger)
| id | outcome (one line) | status | evidence path |
|---|---|---|---|
| C1 | Fix antialiasing toggle (always-on bug) — `enable_antialiasing()` returns void | active | `init.lua:131-134`, API: returns void |
| C2 | Fix gallery Russian `т`/`з` calling invalid `select("next"/"prev")` | active | `init.lua:419-420`, API `gdir_t` |
| C3 | Reconcile gallery Latin `n`/`p` (grid right/left) vs Russian intent (file-level) | active | `init.lua:292-293` vs `419-420` |
| C4 | Add missing slideshow navigation (n/p, BackSpace, arrows) | active | `init.lua:437-504` |
| C5 | Add Russian layout duplicates for rotate keys | active | `init.lua:193-208` — only Latin |
| C6 | Verify and fix `Ctrl-less` key-name validity on US/QWERTY | active | `<` is Shift+comma physically |
| C7 | Update `docs/howto/swayimg-hotkeys.md` for all fixes | active | `docs/howto/swayimg-hotkeys.md` |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
|---|---|---|---|
| Antialiasing toggle: API has no getter | Track state in Lua module-level variable | Only way to implement toggle; TODO comment confirms plan | Yes |
| Gallery `n`/`p` semantics | Change to next/prev file (sequential), matching viewer. Grid stays on hjkl | Currently `n`/`p` = grid right/left — inconsistent with viewer n/p = next/prev file | Yes |
| Slideshow navigation | Mirror viewer: n/p = next/prev, BackSpace = prev, arrows = pan, i = info | Slideshow is near-unusable; viewer is the reference | Yes |
| `Ctrl-less` fix | Replace with `Ctrl-Shift-comma` for rotate-ccw | On US layout `<` is Shift+comma; explicit modifier is unambiguous | Yes |
| Rotate Russian layout | `Ctrl-б`(rot-left), `Ctrl-Shift-б`(rot-ccw), `Ctrl-ю`(rot-right), `Ctrl-.`(rot-180) | Follows ЙЦУКЕН physical positions; consistent with existing Ctrl bindings | Yes |

## Findings (cited)

### Bug 1 — Antialiasing toggle always enables
`init.lua:131-134` + `247`:
```lua
-- TODO: query state when API supports it
swayimg.enable_antialiasing(not swayimg.enable_antialiasing(true))
```
API: `swayimg.enable_antialiasing(enable)` returns **void**. `not nil == true`. Pressing `a`/`ф` always enables, never disables.

### Bug 2 — Gallery `select("next"/"prev")` invalid
`init.lua:419-420`:
```lua
key2g({"т"}, function() swayimg.gallery.select("next") end)
key2g({"з"}, function() swayimg.gallery.select("prev") end)
```
API `gdir_t`: `"first"|"last"|"up"|"down"|"left"|"right"|"pgup"|"pgdown"`. `"next"`/`"prev"` silently fail.

### Bug 3 — Gallery n/p semantic mismatch
- Latin `n` (292): `select("right")` — grid
- Latin `p` (293): `select("left")` — grid
- Russian `т` (419): `select("next")` — invalid, intent was file-level
- Russian `з` (420): `select("prev")` — invalid, intent was file-level
- Viewer `n` (114): `open("next")` — file-level. Gallery Latin is inconsistent.

### Gap 4 — Slideshow minimal
Only has: q, f, s, d, Ctrl-d, range ops, Space toggle. Missing n/p, BackSpace, arrows, i.

### Gap 5 — Rotate: no Russian layout
Only Latin bindings (193-208). All other categories have `key2()` Russian duplicates.

### Risk 6 — `Ctrl-less` key
US layout `<` = `Shift+,`. `Ctrl-less` may not fire. Explicit `Ctrl-Shift-comma` is unambiguous.

## Scope IN
- `files/gui/swayimg/init.lua` — all hotkey fixes
- `docs/howto/swayimg-hotkeys.md` — table updates

## Scope OUT
- No changes to `swayimg-actions.sh`
- No Nix packaging changes
- No Hyprland WM binding changes
- No new features — fixes and gap-filling only

## Approval gate
status: awaiting-approval
