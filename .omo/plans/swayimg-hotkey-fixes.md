# Plan: swayimg-hotkey-fixes

## TL;DR (For humans)

Чиним хоткеи swayimg. Основная проблема: форк `neg-serg/swayimg` возвращает из `get_position()` кортеж `x, y`, а `init.lua` ожидает таблицу `{x=..., y=...}`. Из-за этого все панорамирование стартует с (0,0) вместо текущей позиции, а в slideshow-режиме падает с ошибкой. Дополнительно: `Ctrl-Shift-comma` не работает на US-раскладке (XKB keysym mismatch), zoom/reset/scroll не восстановлены после `bind_reset()`, gallery без стрелок влево/вправо, и перемещение блокируется `fixup_position()` когда картинка влезает в окно (чинится через `enable_freemove(true)` из форка).

Все изменения — только в `files/gui/swayimg/init.lua`. Никаких ручных действий не требуется.

## Changes

**File**: `files/gui/swayimg/init.lua`

1. **Fix `get_pos()` wrapper** (line 32-35): распаковывать кортеж вместо доступа по ключу
2. **Fix slideshow panning** (lines 517-524, 539-542): распаковывать кортеж, защита от nil
3. **Fix `Ctrl-Shift-comma`** (line 200): добавить `"Ctrl-Shift-less"` как дополнительный биндинг для US-раскладки
4. **Add `enable_freemove(true)`** (after line 72): разрешить перемещение когда картинка влезает в окно
5. **Restore zoom/reset bindings** (+/-/BackSpace): добавить `on_key` для `"="`, `"plus"`, `"minus"`, `"BackSpace"` (reset)
6. **Add Left/Right to gallery** (after line 294): добавить `on_key("Left"...)` и `on_key("Right"...)` как алиасы для `select("left")` / `select("right")`
7. **Restore mouse scroll panning** (after viewer bindings): добавить `on_input` или via Lua (scroll не привязан через Lua API, только через C++ bind_input — не восстанавливаем, т.к. нет `on_scroll` в Lua API)

## Todos

### [x] Todo 1: Fix `get_pos()` wrapper and slideshow panning

**WHERE**: `files/gui/swayimg/init.lua`
**HOW**: 
- Line 33: `local pos = swayimg.viewer.get_position()` → `local x, y = swayimg.viewer.get_position()`
- Line 34: `return { x = pos.x or 0, y = pos.y or 0 }` → `return { x = x or 0, y = y or 0 }`
- Lines 517-524: rewrite each from `local p = swayimg.slideshow.get_position() ... p.x-50` to `local px, py = swayimg.slideshow.get_position() ... (px or 0)-50`
- Lines 539-542: same pattern for Russian key slideshow panning

**Acceptance**: After fix, viewer panning accumulates position correctly (pressing `j` 3 times moves 150px down, not 50px from origin). Slideshow panning doesn't crash.

**Commit**: `[gui/swayimg] Fix get_pos() tuple unpacking for fork API change`

### [x] Todo 2: Add `enable_freemove(true)` 

**WHERE**: `files/gui/swayimg/init.lua`
**HOW**: After `swayimg.viewer.set_default_scale("optimal")` (line 66), add `swayimg.viewer.enable_freemove(true)` — this allows panning even when the scaled image fits entirely within the window. Without this, `fixup_position()` centers the image and discards any manual position.

**Acceptance**: On any image (including small ones), pressing h/j/k/l moves the image. On fullscreen large images, panning still works as before.

**Commit**: `[gui/swayimg] Enable freemove for consistent panning regardless of image size`

### [x] Todo 3: Fix `Ctrl-Shift-comma` binding

**WHERE**: `files/gui/swayimg/init.lua`
**HOW**: On line 200, `swayimg.viewer.on_key("Ctrl-Shift-comma", ...)` — for US layout, when Shift is held, the comma key produces XKB keysym `XKB_KEY_less`, not `XKB_KEY_comma`. The binding never matches. Fix: add a parallel binding for `"Ctrl-Shift-less"` (without removing the existing one, as it may work on some layouts/keyboards). Apply same fix for gallery (line 372) and viewer Russian duplicate already exists.

**Acceptance**: Ctrl+Shift+, on US layout triggers rotate-ccw.

**Commit**: `[gui/swayimg] Fix Ctrl-Shift-comma binding for US XKB layout`

### [x] Todo 4: Restore zoom and reset bindings

**WHERE**: `files/gui/swayimg/init.lua`
**HOW**: After existing viewer bindings, add:
```lua
-- Zoom (restored after bind_reset)
swayimg.viewer.on_key("Equal", function() local s = swayimg.viewer.get_scale() swayimg.viewer.set_abs_scale(s + s/10) end)
swayimg.viewer.on_key("Shift-equal", function() local s = swayimg.viewer.get_scale() swayimg.viewer.set_abs_scale(s + s/10) end)
swayimg.viewer.on_key("Minus", function() local s = swayimg.viewer.get_scale() swayimg.viewer.set_abs_scale(s - s/10) end)
swayimg.viewer.on_key("BackSpace", function() swayimg.viewer.reset_scale() end)
```
(Check available names: `"="` vs `"Equal"`, `"-"` vs `"Minus"` — use XKB names consistent with rest of config.)

**Acceptance**: +/- zoom in/out, BackSpace resets scale to default.

**Commit**: `[gui/swayimg] Restore zoom and reset bindings lost after bind_reset()`

### [x] Todo 5: Add Left/Right arrow bindings to gallery

**WHERE**: `files/gui/swayimg/init.lua`
**HOW**: After gallery `Up`/`Down` bindings (line 293-294), add:
```lua
swayimg.gallery.on_key("Left", function() swayimg.gallery.select("left") end)
swayimg.gallery.on_key("Right", function() swayimg.gallery.select("right") end)
```

**Acceptance**: In gallery mode, Left and Right arrows navigate the thumbnail grid.

**Commit**: `[gui/swayimg] Add missing Left/Right arrow bindings to gallery`

### [-] Todo 6: Update documentation

**WHERE**: `docs/howto/swayimg-hotkeys.md`
**HOW**: Update the key table to reflect:
- Arrow keys work in both viewer AND gallery now
- `Ctrl+Shift+,` note about US layout fix
- New `enable_freemove` behavior

**Commit**: `[docs] Update swayimg hotkey docs with fixes and gallery arrows`

## Dependency Matrix

| Todo | Depends on |
|------|-----------|
| 1 | — |
| 2 | — |
| 3 | — |
| 4 | 1 (uses same area of file) |
| 5 | — |
| 6 | 1-5 (documents final state) |

All todos are independent except 6 (documents after fixes) and 4 (edit in same region as 1 — merge carefully).

## Verification

1. Open swayimg with a small image (< window size): panning keys move the image off-center
2. Open swayimg with a large image (> window size): panning works and accumulates properly
3. Slideshow mode: panning keys work without errors
4. Ctrl+Shift+, on US layout: triggers rotate-ccw
5. +/- zoom, BackSpace reset work
6. Gallery: Left/Right arrows work
7. `nixos-rebuild switch` (or `just build`) succeeds
