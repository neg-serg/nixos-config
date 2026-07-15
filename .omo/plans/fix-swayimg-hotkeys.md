# fix-swayimg-hotkeys - Work Plan

## TL;DR (For humans)
<!-- Fill LAST -->

**What you'll get:** <fill last>

**Why this approach:** <fill last>

**What it will NOT do:** <fill last>

**Effort:** Short
**Risk:** Low — single config file, no packaging changes, no runtime dependencies changed
**Decisions I made for you:** <fill last>

Your next move: approve or request changes. Full execution detail follows.

---

> TL;DR (machine): Short, Low risk, fix 5 bugs + 5 gaps in swayimg init.lua hotkeys, update docs

## Scope
### Must have
- Fix antialiasing toggle → track state in Lua variable (API `enable_antialiasing()` returns void, no getter)
- Fix gallery Russian `т`/`з` → replace invalid `select("next"/"prev")` with `select("right"/"left")`
- Fix viewer Russian `о`/`д` navigation swap (о сейчас pan-right, д pan-down — перепутаны местами)
- Add missing Russian `П` for `G` (last file) — viewer + gallery
- Add slideshow navigation: n/p, BackSpace, arrows, information, Return/Escape
- Add Russian layout duplicates for ALL 4 rotate keys — и viewer, и gallery
- Fix `Ctrl-less` → `Ctrl-Shift-comma` — и viewer, и gallery (оба имеют этот баг)
- Update `docs/howto/swayimg-hotkeys.md` tables for viewer/gallery/slideshow

### Must NOT have
- No changes to `swayimg-actions.sh` (actions logic is separate)
- No Nix packaging or module wiring changes
- No Hyprland WM binding changes
- No new feature categories — only fixes and gap-filling within existing categories
- No removal of any existing keybinding (only add missing, fix broken)

## Verification strategy
> Zero human intervention — all verification is agent-executed.
- Test decision: tests-after — verify Lua syntax, key-name consistency, API contract compliance
- Evidence: `.omo/evidence/task-<N>-fix-swayimg-hotkeys.md`

## Execution strategy
### Parallel execution waves
Wave 1: Fix functional bugs (T1, T2, T3) — independent
Wave 2: Fill gaps (T4, T5, T6, T7) — depends on wave 1 for context
Wave 3: Docs update (T8) — depends on waves 1-2

### Dependency matrix
| Todo | Depends on | Can parallelize with |
| --- | --- | --- |
| T1 (antialiasing) | none | T2, T3 |
| T2 (gallery т/з fix) | none | T1, T3 |
| T3 (viewer о/д swap) | none | T1, T2 |
| T4 (slideshow nav) | T1, T2 | T5, T6, T7 |
| T5 (П for last) | T1, T2 | T4, T6, T7 |
| T6 (Russian rotate keys) | T1, T2 | T4, T5, T7 |
| T7 (Ctrl-less cleanup) | T6 | T4, T5 |
| T8 (docs) | T1-T7 | none |

## Todos

- [x] 1. Fix antialiasing toggle — add Lua state variable
  What to do: Add `local aa_enabled = true` at module top (after line 35, near other module-level state). Change viewer Latin `on_key("a", ...)` (line 131-134) to: `aa_enabled = not aa_enabled; swayimg.enable_antialiasing(aa_enabled)`. Change viewer Russian `key2({"ф"}, ...)` (line 247) to same pattern. Remove TODO comment from both locations.
  Must NOT do: Do not change key names `a`/`ф`. Do not touch gallery or slideshow antialiasing (they don't have it).
  Parallelization: Wave 1 | Blocked by: none | Can parallelize with: T2, T3
  References: `init.lua:131-134`, `init.lua:247`, neg-serg/swayimg fork API: `swayimg.enable_antialiasing(enable)` returns void (no getter)
  Acceptance criteria: `luajit -p files/gui/swayimg/init.lua` exits 0. Grep for `aa_enabled` finds exactly 3 occurrences: declaration + 2 toggles. No remaining `TODO.*query state` comment.
  QA: Happy — `grep -c "aa_enabled" init.lua` returns 3. Failure — `enable_antialiasing(true)` still hardcoded in toggle handlers → fail. Evidence: `.omo/evidence/task-1-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Fix antialiasing toggle with state variable`

- [x] 2. Fix gallery Russian `т`/`з` — invalid select values
  What to do: Replace `select("next")` → `select("right")` and `select("prev")` → `select("left")` in `key2g({"т"}, ...)` (line 419) and `key2g({"з"}, ...)` (line 420). Matches Latin `n`/`p` bindings (lines 292-293: grid right/left). Gallery API `gdir_t`: `first|last|up|down|left|right|pgup|pgdown` — does NOT have `next`/`prev`/`next_dir`/`prev_dir`. Grid movement is the only gallery navigation.
  Must NOT do: Do not change Latin n/p (stay right/left — correct grid behavior). Do not attempt `next_dir`/`prev_dir` — not in gdir_t.
  Parallelization: Wave 1 | Blocked by: none | Can parallelize with: T1, T3
  References: `init.lua:419-420`, neg-serg/swayimg fork API `gdir_t`: `"first"|"last"|"up"|"down"|"left"|"right"|"pgup"|"pgdown"`
  Acceptance criteria: `grep -E 'select\("(next|prev)"\)' init.lua` returns ZERO matches. `key2g({"т"}, ...)` shows `select("right")`, `key2g({"з"}, ...)` shows `select("left")`.
  QA: Happy — no invalid select values. Failure — any `select("next")` or `select("prev")` remains → fail. Evidence: `.omo/evidence/task-2-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Fix gallery Russian select from invalid next/prev to right/left`

- [x] 3. Fix viewer Russian `о`/`д` navigation swap
  What to do: Swap the pan actions on `о` and `д` in viewer Russian section. Currently: `о`=pan-right (line 238), `д`=pan-down (line 240). Fix: `о`→pan-down (matches j physical position), `д`→pan-right (matches l physical position). Also fix `О` (uppercase) which currently maps to pan-down → should map to pan-right (to match `J` which is a down-alt). Actually, `J` in viewer Latin = pan-down (line 108). So `О` (uppercase о at J position) should stay as pan-down — it's correct! Only `о` and `д` lowercase need swapping.
  After fix:
  - `о` → pan-down (y+50) — matches j physical position
  - `д` → pan-right (x+50) — matches l physical position
  This makes viewer consistent with gallery Russian (lines 414-418) which already has the correct mapping.
  Must NOT do: Do not change `р`/`л`/`О` (already correct). Do not change gallery Russian navigation (already correct).
  Parallelization: Wave 1 | Blocked by: none | Can parallelize with: T1, T2
  References: `init.lua:237-241` (viewer Russian arrows), `init.lua:414-421` (gallery Russian arrows — correct reference), `init.lua:78-108` (Latin arrows)
  Acceptance criteria: `key2({"о"}, ...)` → y+50 (down). `key2({"д"}, ...)` → x+50 (right). `key2({"О"}, ...)` → y+50 (down) — unchanged.
  QA: Happy — `grep -A2 'key2({"о"}' init.lua | head -1` shows `y+50`. `grep -A2 'key2({"д"}' init.lua | head -1` shows `x+50`. Failure — swap still present → fail. Evidence: `.omo/evidence/task-3-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Fix viewer Russian о/д navigation swap`

- [x] 4. Add slideshow navigation keys
  What to do: After `swayimg.slideshow.on_key("q", ...)` (line 444), add these bindings mirroring viewer:
  - `n` → `slideshow.open("next")`
  - `p` → `slideshow.open("prev")`
  - `BackSpace` → `slideshow.open("prev")`
  - `h`/`Left` → pan left (`set_abs_position(x-50, y)`)
  - `l`/`Right` → pan right (`set_abs_position(x+50, y)`)
  - `k`/`Up` → pan up (`set_abs_position(x, y-50)`)
  - `j`/`Down` → pan down (`set_abs_position(x, y+50)`)
  - `i` → `swayimg.text.show()`
  - `Return`/`Escape` → `swayimg.set_mode("gallery")`
  Add Russian `key2s()` duplicates (after existing key2s block at line 494):
  - `т`→`slideshow.open("next")`, `з`→`slideshow.open("prev")`
  - `р`→pan-left, `о`→pan-down, `л`→pan-up, `д`→pan-right
  - `ш`→`text.show()`
  Must NOT do: Do not remove existing slideshow bindings (f, q, s, d, Ctrl-d, range ops, Space toggle).
  Parallelization: Wave 2 | Blocked by: T1, T2 | Can parallelize with: T5, T6
  References: Viewer nav `init.lua:78-126`, slideshow API: `open(vdir_t)`, `get_position()`, `set_abs_position()`, `text.show()`, `set_mode()`
  Acceptance criteria: `grep -c "slideshow.on_key" init.lua` returns ≥22 (currently 13). Russian `key2s` has ≥8 calls for nav keys.
  QA: Happy — each new binding verified by grep. Failure — slideshow still lacks n/p or arrows → fail. Evidence: `.omo/evidence/task-4-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Add navigation keys to slideshow mode`

- [x] 5. Add missing Russian `П` for `G` (last file)
  What to do: In viewer Russian section (after line 244 area), add: `key2({"П"}, function() swayimg.viewer.open("last") end)` — `П` is Shift+п at G physical position, same logic as how `G` (Shift+g) = last file.
  In gallery Russian section (after line 414 area), add: `key2g({"П"}, function() swayimg.gallery.select("last") end)`.
  Must NOT do: Do not change existing `п`→`open("first")`/`select("first")` — both correct.
  Parallelization: Wave 2 | Blocked by: T1, T2 | Can parallelize with: T4, T6
  References: `init.lua:113` (Latin `G`), `init.lua:113-114` (viewer `g`+`G`), `init.lua:277-278` (gallery `g`+`G`), `init.lua:243-244` (viewer Russian `п`→first)
  Acceptance criteria: Viewer: `key2({"П"}, ...)` calls `open("last")`. Gallery: `key2g({"П"}, ...)` calls `select("last")`. Both after their respective `п`→first bindings.
  QA: Happy — grep confirms both П bindings. Failure — either missing → fail. Evidence: `.omo/evidence/task-5-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Add Russian П for last-file (G equivalent) in viewer and gallery`

- [x] 6. Add Russian layout duplicates for ALL rotate keys (viewer + gallery)
  What to do: 
  **Viewer (after line 208):** Add `key2()` block:
  - `key2({"Ctrl-б"}, ...)` → rotate-left (б at comma position)
  - `key2({"Ctrl-Shift-б"}, ...)` → rotate-ccw (Shift+б = <)
  - `key2({"Ctrl-ю"}, ...)` → rotate-right (ю at period position)
  - `key2({"Ctrl-."}, ...)` → rotate-180 (. at slash position on ЙЦУКЕН)
  
  **Gallery (after last gallery rotate key, ~line 374):** Add `key2g()` block with same 4 bindings.
  
  Each calls `exec(actions .. " rotate-{left,ccw,right,180} " .. cp(img['path']))` with `local img = swayimg.{viewer,gallery}.current_image()`.
  Must NOT do: Do not remove or change existing Latin rotate bindings (viewer lines 193-208, gallery lines 359-374).
  Parallelization: Wave 2 | Blocked by: T1, T2 | Can parallelize with: T4, T5
  References: `init.lua:193-208` (viewer Latin rotate), `init.lua:237-260` (viewer Russian section pattern), `init.lua:359-374` (gallery Latin rotate), `init.lua:412-435` (gallery Russian section pattern)
  Acceptance criteria: Each of 4 rotate actions appears 6 times: Latin viewer + Russian viewer + Latin gallery + Russian gallery + key2 wrapper + key2g wrapper = 6. Actually: `rotate-left` appears 2× Latin (viewer+gallery) + 2× Russian (key2+key2g) = 4 total. Check: `grep -c "rotate-left" init.lua` returns 4.
  QA: Happy — each rotate action has 4 bindings (2 Latin + 2 Russian). Failure — any <4 → fail. Evidence: `.omo/evidence/task-6-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Add Russian layout duplicates for rotate keys in viewer and gallery`

- [x] 7. Fix .Ctrl-less. → `Ctrl-Shift-comma` everywhere (viewer + gallery)
  What to do: Replace `Ctrl-less` with `Ctrl-Shift-comma` in ALL locations:
  - Viewer Latin rotate-ccw (line 197)
  - Gallery Latin rotate-ccw (line ~367)
  - Viewer Russian rotate-ccw (`Ctrl-Shift-б`, from T6)
  - Gallery Russian rotate-ccw (`Ctrl-Shift-б`, from T6)
  On US/QWERTY, `<` = Shift+comma. `Ctrl-Shift-comma` is the unambiguous modifier+keyname.
  Must NOT do: Do not touch other rotate key names — `Ctrl-comma`, `Ctrl-period`, `Ctrl-slash` are standard.
  Parallelization: Wave 2 | Blocked by: T6 | Can parallelize with: none (depends on T6 for Russian bindings)
  References: `init.lua:197-198` (viewer), `init.lua:~367` (gallery), US layout: `<` = `Shift+,`
  Acceptance criteria: `grep "Ctrl-less" init.lua` returns nothing. Rotate-ccw uses `Ctrl-Shift-comma` (Latin) and `Ctrl-Shift-б` (Russian) in both modes.
  QA: Happy — zero `Ctrl-less` matches. Failure — any `Ctrl-less` remains → fail. Evidence: `.omo/evidence/task-7-fix-swayimg-hotkeys.md`
  Commit: Y | `[swayimg] Fix rotate-ccw Ctrl-less to Ctrl-Shift-comma in viewer + gallery`

- [x] 8. Update docs/howto/swayimg-hotkeys.md
  What to do: Update all three mode tables:
  - View: antialiasing toggle fix noted, `Ctrl+<` → `Ctrl+Shift+,`, Russian rotates added, `П` for last-file, `о`/`д` fixed
  - Gallery: Russian т/з corrected to right/left, Russian rotates added, `П` for last-file
  - Slideshow: full navigation section (n/p, BackSpace, arrows, hjkl, i, Return/Escape)
  Strikethrough `Ctrl-less` everywhere, replace with `Ctrl+Shift+,`
  Must NOT do: Keep existing markdown table format; do not restructure
  Parallelization: Wave 3 | Blocked by: T1-T7 | Can parallelize with: none
  References: `docs/howto/swayimg-hotkeys.md:19-79`, `init.lua` all changed lines
  Acceptance criteria: No `Ctrl-less` in docs. Slideshow has ≥10 key rows. Gallery shows Russian right/left (not next/prev). Rotate section shows 2 keys per action (Latin + Russian).
  QA: grep docs for all changes. Failure — any stale `Ctrl-less` or `select("next")` → fail. Evidence: `.omo/evidence/task-8-fix-swayimg-hotkeys.md`
  Commit: Y | `[docs] Update swayimg hotkey reference for all fixed bindings`

## Final verification wave
- [x] F1. Plan compliance — all 8 todos complete
- [x] F2. Code quality — `luajit -p init.lua` passes; no `Ctrl-less`; no `select("next"/"prev")` in gallery; no `TODO.*query state`
- [x] F3. Manual QA — read final init.lua top-to-bottom; verify all changes consistent across modes
- [x] F4. Scope fidelity — only `init.lua` and `swayimg-hotkeys.md` modified

## Commit strategy
Squash: `[swayimg] Fix hotkeys: antialiasing, gallery nav, viewer о/д, slideshow nav, П, rotate Russian layout, Ctrl-less`

Or individual:
1. `[swayimg] Fix antialiasing toggle with state variable`
2. `[swayimg] Fix gallery Russian select from invalid next/prev to right/left`
3. `[swayimg] Fix viewer Russian о/д navigation swap`
4. `[swayimg] Add navigation keys to slideshow mode`
5. `[swayimg] Add Russian П for last-file in viewer and gallery`
6. `[swayimg] Add Russian rotate duplicates in viewer and gallery`
7. `[swayimg] Fix rotate-ccw Ctrl-less to Ctrl-Shift-comma throughout`
8. `[docs] Update swayimg hotkey reference`

## Success criteria
- Antialiasing toggles on/off (not always-on)
- Gallery Russian т/з work (valid select values)
- Viewer Russian о/д match gallery (физически правильные позиции)
- Slideshow has usable navigation keys
- `П` opens last file in viewer and gallery (both layouts)
- All 4 rotate actions work in both layouts in both modes
- `Ctrl-Shift-comma` is used everywhere (no `Ctrl-less`)
- Docs accurately reflect all bindings
- Zero regressions to existing working bindings
