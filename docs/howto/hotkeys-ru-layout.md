# Hotkeys and the Russian layout: inventory and fix plan

> Status: **implemented** — P0 (Hyprland), P1 (kitty/mpv/SurfingKeys), P2 (zellij/yazi/rmpc); mutt
> and rustmission are **not fixable via config** (confirmed from the source — see "Validation");
> btop/ghostty are known issues. The RU duplicates are additive (the US layout is unaffected);
> exception — kitty's Emacs scroll layer was moved from Ctrl+Shift to Ctrl+Alt to remove a conflict
> with `kitty_mod+b/f/p`.

## TL;DR

- **Hyprland (WM) hotkeys already work under both layouts.** Why: `kb_layout = "us,ru"` — `us` is
  first, and `input:resolve_binds_by_sym` is unset (defaults to `false`), so binds are matched
  against the **first** layout's symbol (us), not the active one. Everything breaks only if the
  layouts are reordered (`ru,us`) or `resolve_binds_by_sym = true` is enabled.
- **Main victims of the RU layout** are programs that match hotkeys against the active layout's
  keysym with no fallback:
  - `kitty` — every `kitty_mod` (Ctrl+Shift+letter) and `Ctrl+letter` shortcut from
    `files/kitty/key.conf`;
  - `mpv` — letter keys (`p i r t v f l h L H m j s`, etc.);
  - SurfingKeys in Vivaldi — vim navigation (`j k h l t d u w o e b v s H L F`, etc.);
  - TUI programs in the terminal (zellij, mutt, yazi, rustmission, rmpc, khal, broot, tig) — "bare"
    letters and `Alt+letter`.
- **Already fixed:** swayimg (JCUKEN duplicates in `init.lua`), neovim (langmap + langmapper.nvim).
- **Always works:** `Ctrl+letter` inside the terminal (zsh, zellij, mutt, etc.) — the terminal sends
  control bytes based on the physical key; the layout has no effect.

## Mechanics: why it breaks at all

A keyboard event carries two identifiers:

- **keycode** — the physical key (e.g. `KEY_D` = 40). Independent of the layout.
- **keysym** — the character the key produces in the **active** layout (`d` in us, `в` in ru).

A hotkey bound to a Latin letter is matched by keysym. Under the RU layout the keysym becomes
Cyrillic and the match fails. What happens next depends on the layer:

| Layer                                              | Behavior under RU                                                                                                                                                                                                                                           |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Hyprland (binds)**                               | ✅ Binds are matched against the keysym of the **first** layout (`us`), because `resolve_binds_by_sym = false` (default) and the translation state is built from `kb_layout` with group 0. All `SUPER+d`, `M4+SHIFT+r` and submaps work under both layouts. |
| **Qt apps**                                        | ✅ `Ctrl+letter` works (Qt takes the Latin key from group 0 while a modifier is pressed). ❌ Bare letters and `Alt+letter` are matched by the actual character.                                                                                             |
| **GTK apps**                                       | ✅ `Ctrl+letter` mostly works (falls back to the keyval of group 0). ❌ Bare letters break.                                                                                                                                                                 |
| **Electron/Chromium** (Vivaldi, Obsidian, VS Code) | ✅ `Ctrl+letter` works (Chromium accelerators are derived from the physical key/US keycode). ❌ Modifier-free binds (vim style) match `event.key` → Cyrillic.                                                                                               |
| **kitty**                                          | ❌ Own shortcuts are matched against the **active** layout's keysym (see kovidgoyal/kitty#2000 — official workaround: duplicates like `map ctrl+CYRILLIC_ES ...`).                                                                                          |
| **ghostty**                                        | ⚠️ Known bugs even with `Ctrl+letter` under RU (ghostty-org/ghostty#3513, #3584); fixed in newer versions by moving to W3C key-code binds (#7320).                                                                                                          |
| **TUIs in the terminal**                           | ✅ `Ctrl+letter` — the terminal turns it into a control byte (0x00–0x1F) from the physical key. ❌ A letter without a modifier / `Alt+letter` — the app receives a Cyrillic character.                                                                      |
| **Games (SDL)**                                    | ✅ Physical key scan codes — the layout has no effect.                                                                                                                                                                                                      |

## Validation: what was checked and where

| Claim                                                                                        | How it was verified                                                                                                                                                                                                                                                                        | Result           |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------- |
| Hyprland binds resolve against the **first** layout                                          | Source at the pinned revision `36b2e0cf`: `KeybindManager.cpp` — `xkb_state_key_get_one_sym(m_resolveBindsBySym ? m_xkbSymState : m_xkbTranslationState, KEYCODE)`; `m_xkbTranslationState = xkb_state_new(keymap)` (group 0); `ConfigValues.cpp` — `resolve_binds_by_sym` default `false` | ✅               |
| kitty matches shortcuts against the **active** layout's keysym; `CYRILLIC_*` names are valid | `kitty/key_names.py` (names parsed through `xkb_keysym_from_name`); the maintainer's official workaround in kovidgoyal/kitty#2000 (`map ctrl+CYRILLIC_ES send_text all \x03`)                                                                                                              | ✅               |
| mpv matches the "translated" text of the active layout; literal Unicode keys in input.conf   | mpv `DOCS/man/input.rst`: "`<key>` is either the literal character … (ASCII or Unicode)", "mpv uses input translated by the current OS keyboard layout, rather than physical scan codes"                                                                                                   | ✅               |
| zellij accepts Cyrillic keys in its config                                                   | `zellij-utils/src/data.rs` — `BareKey::from_str`: any single char; matching via `KeyCode::Char(c)` (`input/mod.rs`)                                                                                                                                                                        | ✅               |
| In the terminal `Ctrl+letter` = a control byte from the physical key                         | Standard terminal behavior (kitty without the keyboard protocol sends the control byte from the keycode)                                                                                                                                                                                   | ✅               |
| Chromium/Electron: `Ctrl+letter` from the physical key                                       | Known, widely documented behavior (accelerator = US `KeyboardCode` from `DomCode`)                                                                                                                                                                                                         | ✅ (empirically) |
| yazi accepts Cyrillic keys (lowercase)                                                       | `yazi-config/src/keymap/key.rs` — `Key::from_str`: any single char; uppercase implies SHIFT → an uppercase Cyrillic letter will not match                                                                                                                                                  | ✅ (lowercase)   |
| rmpc accepts Cyrillic keys                                                                   | `rmpc/src/config/keys/key.rs` — winnow `any` (any Unicode char), case → SHIFT                                                                                                                                                                                                              | ✅               |
| neomutt does **not** accept Cyrillic keys                                                    | `key/keymap.c` — `parse_keys`: `*d = (unsigned char) *s` (byte); a UTF-8 char (2 bytes) binds to its first byte and breaks input                                                                                                                                                           | ❌ not fixable   |
| rustmission does **not** accept Cyrillic keys                                                | intuitils `keybindings.rs`: `if key.len() == 1` (byte length); Cyrillic = 2 bytes → parse error                                                                                                                                                                                            | ❌ not fixable   |

## Inventory from the config

Legend: ✅ works / ❌ breaks / ⚠️ partial or needs checking.

| Program                       | What happens under the RU layout                                                              | Status                | File                                                                          |
| ----------------------------- | --------------------------------------------------------------------------------------------- | --------------------- | ----------------------------------------------------------------------------- |
| Hyprland (all binds, submaps) | binds resolve against the first layout — work                                                 | ✅                    | `files/gui/hypr/hyprland.lua`                                                 |
| greetd / Hyprland greeter     | `us,ru`, starts in us; no binds                                                               | ✅                    | `modules/user/session/greetd.nix`                                             |
| swayimg                       | JCUKEN duplicates for all actions                                                             | ✅ (fixed)            | `files/gui/swayimg/init.lua`                                                  |
| neovim                        | langmap + langmapper.nvim                                                                     | ✅ (fixed)            | `files/nvim/lua/00-settings.lua`, `files/nvim/lua/plugins/keymap/langmap.lua` |
| espanso                       | `ALT+SPACE` — no letters; `:date` triggers are text                                           | ✅                    | `modules/user/nix-maid/cli/espanso.nix`                                       |
| vicinae                       | `Ctrl+letter` binds (Qt fallback)                                                             | ✅ (check manually)   | `modules/user/nix-maid/apps/vicinae.nix`                                      |
| kitty                         | `kitty_mod+letter` (Ctrl+Shift), `Ctrl+s>l/p/h`, `kitty_mod+,/.`/grave/`[`/`]`, `Alt+n`, etc. | ❌                    | `files/kitty/key.conf`                                                        |
| mpv                           | `p i r t v f l h L H m j s A`, `Ctrl+h/l/H`, `Alt+I/U`, `>`/`<` (RU duplicates `Ю`/`Б`)       | ✅ (fixed)            | `modules/user/nix-maid/apps/mpv/input.nix`                                    |
| SurfingKeys (Vivaldi)         | vim keys `j k h l t d u w o e b v s H L F J+,`; the **hint letter set** (`asdfghjkl`) too     | ❌                    | `files/surfingkeys.js`                                                        |
| zellij                        | `Alt+h/j/k/l`; in resize/tab/scroll modes: `h j k l n r`                                      | ✅ (fixed)            | `files/gui/zellij/config.kdl`                                                 |
| mutt                          | `j k g G R u gg`, macros with letters; arrows work                                            | ❌ (not fixable)      | `modules/user/nix-maid/mutt-conf/04-bindings.mutt`                            |
| yazi                          | `g d f p` and `h j k l` navigation                                                            | ✅ (fixed, lowercase) | `modules/user/nix-maid/cli/yazi.nix`                                          |
| rustmission                   | `h l k j H L`                                                                                 | ❌ (not fixable)      | `files/config/rustmission/keymap.toml`                                        |
| rmpc                          | `p s q u w b f o z r y a d g G j k h l n N m M`, etc.                                         | ✅ (fixed)            | `files/rmpc/config.ron`                                                       |
| khal                          | `e` (edit), `d` (duplicate)                                                                   | ❌                    | `modules/user/nix-maid/sys/khal.nix`                                          |
| btop                          | toggles `d n m c f` — **keys are hardcoded, not remappable via config**                       | ❌ (not fixable)      | `modules/user/nix-maid/cli/monitoring.nix`                                    |
| broot / tig / amfora          | letter binds                                                                                  | ❌                    | (standard configs)                                                            |
| nethack                       | letter commands (game)                                                                        | ❌                    | `modules/user/nix-maid/fun/nethack.nix`                                       |
| zsh vi-mode                   | `h/j/k/l` in command mode                                                                     | ❌                    | `modules/user/nix-maid/cli/shells.nix`                                        |
| satty (screenshots)           | single letters (GTK, no modifier)                                                             | ⚠️                    | —                                                                             |
| ghostty                       | config deployed, **package not installed**; known `Ctrl+letter` bugs under RU                 | ⚠️                    | `files/cli/ghostty/config`                                                    |
| Vivaldi / Obsidian (Chromium) | system `Ctrl+letter` ✅; extension letter binds ❌                                            | ⚠️                    | —                                                                             |

### kitty specifics (`files/kitty/key.conf`)

`kitty_mod = ctrl+shift`. Under RU all maps containing Latin letters break, as do the symbols that
change position under RU (`,` → `б`, `.` → `ю`, `` ` `` → `ё`, `[` → `х`, `]` → `ъ`):

- `kitty_mod+v` (paste), `kitty_mod+z/x` (scroll_to_prompt)
- `kitty_mod+q` (close_tab), `kitty_mod+w` (close_window)
- `kitty_mod+b/f/]/[` (window movement), `kitty_mod+comma/period` (tabs)
- `kitty_mod+grave` (move_window_to_top), `kitty_mod+l` (next_layout)
- `kitty_mod+p/u/e/h/o` (hints / scrollback), `kitty_mod+s>f/w/l/p/h` (neghints)
- `Ctrl+s>w/l/p/h` (neghints to stdout), `Ctrl+alt+s` (screen scrollback), `alt+n` (new_tab)
- `kitty_mod+t` (new_tab — restored, the standard ctrl+shift+t), `kitty_mod+alt+t` (set_tab_title —
  the RU duplicate is generated with `alt`, i.e. `ctrl+shift+alt+т`)
- `kitty_mod+r>r` / `r>e` / `r>w`, `kitty_mod+a>1/d/l/m` (opacity)
- `kitty_mod+/` (search) — **US-only**: under RU `/`→`.` and it conflicts with `kitty_mod+.`
  (move_tab_forward), unreachable as a standalone hotkey (same for `>`/`<`)
- The Emacs scroll layer (`scroll_line_down/up`, `scroll_page_down/up`) was remapped to
  **Ctrl+Alt+n/p/f/b** so it does not conflict with `kitty_mod+b/f/p` (Ctrl+Shift)
- `mouse_map ctrl+shift+right` — layout-independent (modifiers+button) ✅

Not broken: `insert`, `delete`, `escape`, `f2`, `backspace`, `equal/minus`, `ctrl+left/right`,
`kitty_mod+backspace`.

### mpv specifics (`input.nix`)

Breaks: `p` (pause), `i` (top bar), `r/t` (subtitles), `v` (subtitle visibility), `F` (fullscreen),
`l/h/L/H` (seek), `m` (mute), `A` (audio track), `R` (window-scale), `j/s` (subtitles),
`Alt+I`/`Alt+U` (AI upscale), `>`/`<` (next/prev) — RU duplicates: `Ю`/`Б` (in JCUKEN `Shift+period`
gives `Ю`, `Shift+comma` gives `Б`; the `>`/`<` chars are absent from the layout, but the physical
keys are the same). `Ctrl+h/l/H` (speed) — also breaks (these are mpv shortcuts, not terminal
control bytes). `space`, `0/9`, `WHEEL_*`, `Alt+0/1/2`, `Ctrl+enter` — layout-independent ✅.

### SurfingKeys specifics (`files/surfingkeys.js`)

Modifier-free vim navigation: `j k h l` (scroll), `t` (new tab), `d` (close), `u` (restore), `w`
(tab list), `o` (address bar), `e` (next tab), `b/v/s` (scroll), `H/L` (back/forward), `F` (open in
a new tab), `J`/`,`+letter (sites), `]`/`[` (video speed), etc. — all of it is matched via
`event.key` → Cyrillic. Limitation: hints mode (`f`) accepts only `hintChars = "asdfghjkl"` — under
RU the hint letter set breaks and cannot be fixed via config (a US layout is needed for hints). The
same applies to `kitten hints --alphabet wersdfa` in kitty.

URL exceptions: `settings.blocklistPattern` disables SurfingKeys entirely on `mail.google.com`,
`docs.google.com`, `discord.com` and `app.slack.com`. The dsh web GUI (`127.0.0.1:3080` /
`localhost:3080`) used to be listed too (it had its own shortcuts and Tab autocomplete), but the GUI
was removed in 2026-09 and the port-scoped entries were dropped, so other loopback pages (e.g.
`localhost:5173`) keep SurfingKeys. Check: `check-surfingkeys`.

## Fix plan (by priority)

### P0 — Hyprland: pin the invariants (no risk)

**File:** `files/gui/hypr/hyprland.lua` (the `input` section, `kb_layout` line).

Add a comment and (optionally) an explicit value so the invariant cannot be lost:

```lua
-- Keyboard layouts: `us` MUST stay first. Binds are resolved against the FIRST
-- layout (input:resolve_binds_by_sym = false is the default), so `us,ru` keeps
-- all binds working in both layouts. Switching: M4+S.
kb_layout = "us,ru", kb_variant = "", kb_model = "", kb_options = "", kb_rules = "",
resolve_binds_by_sym = false,
```

**Check:** `hyprctl getoption input:resolve_binds_by_sym` → `false`; under the RU layout check
`M4+d`, `M4+w`, `M4+SHIFT+r`, submaps (`M4+M1+r`, `M4+minus`).

### P1 — kitty (the main terminal, the most frequent scenario)

**File:** `files/kitty/key.conf` — the `Russian layout duplicates (ЙЦУКЕН)` block is **generated**
from `lib/ru-keys.nix` (`kittyRuBinds` in `shells.nix`) and uses **literal Cyrillic characters**
(`map ctrl+shift+м …`) — exactly like kitty's Latin binds.

> ⚠️ Fix (2026-08): the original plan used `CYRILLIC_*` keysym names — on this system they **do not
> work**: kitty resolves them via `xkb_keysym_from_name`, and `libxkbcommon` fails to load (no ld
> cache), so the names are silently dropped as "unknown key" (case matters too: `Cyrillic_em`, not
> `CYRILLIC_EM`). Literal characters are parsed without the library and matched by the same
> mechanism as Latin binds: a Cyrillic keysym event carries the character itself (confirmed by kitty
> tests, `kitty_tests/keys.py`).

Below is a historical example (do not apply as is):

```
# --- Russian layout duplicates (ЙЦУКЕН) ---
map ctrl+shift+CYRILLIC_EM      paste_from_clipboard        # kitty_mod+v  (v→м)
map ctrl+shift+CYRILLIC_YA      scroll_to_prompt -1         # kitty_mod+z  (z→я)
map ctrl+shift+CYRILLIC_CHE     scroll_to_prompt 1          # kitty_mod+x  (x→ч)
map ctrl+shift+CYRILLIC_SHORTI  close_tab                   # kitty_mod+q  (q→й)
map ctrl+shift+CYRILLIC_TSE     close_window                # kitty_mod+w  (w→ц)
map ctrl+shift+CYRILLIC_BE      move_tab_backward           # kitty_mod+,  (,→б)
map ctrl+shift+CYRILLIC_YU      move_tab_forward            # kitty_mod+.  (.→ю)
map ctrl+shift+CYRILLIC_I       move_window_backward        # kitty_mod+b  (b→и)
map ctrl+shift+CYRILLIC_A       move_window_forward         # kitty_mod+f  (f→а)
map ctrl+shift+CYRILLIC_IO      move_window_to_top          # kitty_mod+`  (`→ё)
map ctrl+shift+CYRILLIC_HARDSIGN next_window                # kitty_mod+]  (]→ъ)
map ctrl+shift+CYRILLIC_HA      previous_window             # kitty_mod+[  ([→х)
map ctrl+shift+CYRILLIC_DE      next_layout                 # kitty_mod+l  (l→д)
map ctrl+shift+CYRILLIC_GHE     kitten unicode_input        # kitty_mod+u  (u→г)
map ctrl+shift+CYRILLIC_U       neghints --type=url         # kitty_mod+e  (e→у)
map ctrl+shift+CYRILLIC_ER      kitty_scrollback_nvim       # kitty_mod+h  (h→р)
map ctrl+shift+CYRILLIC_SHCHA   kitty_scrollback_nvim --env KSB_OPEN_GF=1 # kitty_mod+o (o→щ)
map ctrl+shift+CYRILLIC_IE      set_tab_title               # kitty_mod+t  (t→е)
map ctrl+shift+CYRILLIC_YERU>Cyrillic_A       neghints --program @        # kitty_mod+s>f (s→ы, f→а)
map ctrl+shift+CYRILLIC_YERU>Cyrillic_TSE    neghints --type word --program @   # >w (w→ц)
map ctrl+shift+CYRILLIC_YERU>Cyrillic_DE     neghints --type line --program @   # >l (l→д)
map ctrl+shift+CYRILLIC_YERU>Cyrillic_ZE     neghints --type path --program @   # >p (p→з)
map ctrl+shift+CYRILLIC_YERU>Cyrillic_ER     neghints --type hash --program @   # >h (h→р)
map Ctrl+CYRILLIC_YERU>Cyrillic_TSE          neghints --type word --program -   # Ctrl+s>w
map Ctrl+CYRILLIC_YERU>Cyrillic_DE           neghints --type line --program -
map Ctrl+CYRILLIC_YERU>Cyrillic_ZE           neghints --type path --program -
map Ctrl+CYRILLIC_YERU>Cyrillic_ER           neghints --type hash --program -
map Ctrl+alt+CYRILLIC_YERU      kitty_scrollback_nvim --config screen  # Ctrl+alt+s
map alt+CYRILLIC_TE             new_tab                     # alt+n  (n→т)
map ctrl+shift+CYRILLIC_KA>Cyrillic_KA   load_config_file            # kitty_mod+r>r (r→к)
map ctrl+shift+CYRILLIC_KA>Cyrillic_U    debug_config                # kitty_mod+r>e (e→у)
map ctrl+shift+CYRILLIC_EF>1    set_background_opacity 1    # kitty_mod+a>1 (a→ф)
map ctrl+shift+CYRILLIC_EF>Cyrillic_VE   set_background_opacity default   # >d (d→в)
map ctrl+shift+CYRILLIC_EF>Cyrillic_DE   set_background_opacity -0.1      # >l (l→д)
map ctrl+shift+CYRILLIC_EF>Cyrillic_SOFTSIGN set_background_opacity +0.1  # >m (m→ь)
```

If the block feels bulky — the minimum: paste, close_tab/close_window, tab/window switching,
scroll_to_prompt, `kitty_mod+grave` (move_window_to_top).

**Check:** `kitty +kitten debug_keyboard` under RU (compare the keysym names), then walk through the
duplicates one by one.

### P1 — mpv

**File:** `modules/user/nix-maid/apps/mpv/input.nix` — add Cyrillic duplicates (literal characters;
mpv accepts "literal character … (ASCII or Unicode)"):

```
# --- Russian layout duplicates (ЙЦУКЕН) ---
з cycle pause; script-binding uosc/flash-pause-indicator           # p
ш script-message-to uosc flash-top-bar                             # i
к add sub-pos -1                                                   # r
е add sub-pos +1                                                   # t
м cycle sub-visibility 1                                           # v
А cycle fullscreen 1                                               # F
д seek +5; script-binding uosc/flash-timeline                      # l
р seek -5; script-binding uosc/flash-timeline                      # h
Д seek +60; script-binding uosc/flash-timeline                     # L
Р seek -60; script-binding uosc/flash-timeline                     # H
ь no-osd cycle mute; script-binding uosc/flash-volume              # m
Ф cycle audio 1                                                    # A
К cycle_values window-scale 2 0.5 1                                # R
о cycle sub                                                        # j
ы cycle sub                                                        # s
Ctrl+р multiply speed 1/1.1                                        # Ctrl+h
Ctrl+д multiply speed 1.1                                          # Ctrl+l
Ctrl+Р set speed 1.0                                               # Ctrl+H
Alt+ш vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1   # Alt+I
Alt+г run "/bin/sh" "-c" "~/.local/bin/ai-upscale-video \"$path\""                          # Alt+U
```

`>`/`<` (next/prev) — RU duplicates on `Ю`/`Б` were added (in JCUKEN
`shift+`.`/`,`give`Ю`/`Б`). `Alt+0/1/2\` — digits are the same under RU, no duplicates needed.

**Check:** `mpv --input-test` under RU (the name of the pressed key), then `p`/`l`/`h`/`F`/`Alt+I`.

### P1 — SurfingKeys

**File:** `files/surfingkeys.js` — after the existing `map`/`mapkey` calls add a compact "langmap"
block (the rhs of `api.map` is a key sequence that is dispatched into commands without recreating a
DOM event, so Cyrillic on the lhs does not loop):

```js
// Russian layout: Cyrillic → Latin commands (ЙЦУКЕН)
const ru2en = { 'й':'q','ц':'w','у':'e','к':'r','е':'t','н':'y','г':'u','ш':'i','щ':'o','з':'p',
  'х':'[','ъ':']','ф':'a','ы':'s','в':'d','а':'f','п':'g','р':'h','о':'j','л':'k','д':'l',
  'ж':';','э':"'",'я':'z','ч':'x','с':'c','м':'v','и':'b','т':'n','ь':'m','б':',','ю':'.' };
Object.entries(ru2en).forEach(([ru, en]) => api.map(ru, en));
```

Alternative (if `api.map(ru, en)` does not work for some reason — test it in the browser console):
point duplicates `api.mapkey('о', 'Scroll down', ...)` for the most-used keys.

**Limitations (not fixable by script):** the hint letter set in hints mode (`f`) is only `asdfghjkl`
(a US layout is needed); `settings.hintChars` can optionally be replaced with layout-independent
digits/symbols.

**Check:** under RU in the browser: `о`/`р`/`л`/`д` — scroll, `е` — new tab, `в` — close, `г` —
restore.

### P2 — zellij ✅ (Cyrillic in the config confirmed from the source)

**File:** `files/gui/zellij/config.kdl` — duplicates added (letters only; Ctrl binds untouched):
`Alt+р/о/л/д` (MoveFocus), resize `р/о/л/д`, tab `д/р/т/к`, scroll `о/л`.

**Check:** zellij → RU → `Alt+р/о/л/д`; `Ctrl+b` → resize → `р/о/л/д`; tab/scroll modes.

### P2 — mutt ❌ (not fixable via config)

Verified against the neomutt source (`key/keymap.c`): `parse_keys` decomposes the key into **bytes**
(`*d = (unsigned char) *s`), and a Cyrillic character is 2 bytes of UTF-8. A binding like
`bind pager о ...` would bind the byte `0xD0` (the first byte of any Cyrillic character) and **break
Cyrillic input** in mutt. We do not add duplicates. Arrow navigation (the default) works under RU;
the letter binds (`j k g G R u`) remain US-only — known issue.

### P2 — yazi ✅ / rustmission ❌ / rmpc ✅

- **yazi** (`modules/user/nix-maid/cli/yazi.nix`): duplicates added — navigation `о/л/р/д`
  (j/k/h/l), `п п` (gg → top), `в` (d → yank), `п ы / п я / п к / п з` (g s / g z / g r / g p), `з`
  (p → smart-paste). Verified against the source (`Key::from_str` accepts any single char);
  **lowercase only** — an uppercase Cyrillic letter carries SHIFT and will not match.
- **rustmission** (`files/config/rustmission/keymap.toml`): ❌ not fixable — the intuitils parser
  checks `key.len() == 1` (bytes); Cyrillic (2 bytes) → parse error for keymap.toml. Navigation
  remains US-only — known issue.
- **rmpc** (`files/rmpc/config.ron`): duplicates added (global/navigation/queue). Verified against
  the source (`winnow any` — any Unicode char; case → SHIFT). Uppercase Cyrillic duplicates
  (`Д/Щ/З/Г/К/Ф/П/О/Л/Т/С`) work.
- **khal** (`modules/user/nix-maid/sys/khal.nix`): `e→у`, `d→в` — optional (rarely used).
- **broot / tig**: standard configs — optional, same technique.
- **btop**: keys are **hardcoded**, not remappable via config — arrow navigation works, the letter
  toggles (`d n m c f`) are unavailable under RU; accept it or replace it.
- **nethack / zsh vi-mode / satty**: not fixed (games/edge cases), recorded as known issue.

### P2 — ghostty ✅ (decision: keep it with a note)

The package is not installed (kitty is the main terminal). Decision made: **keep** it as a migration
reference, with a note in the header of `files/cli/ghostty/config` and in the module
`modules/user/nix-maid/cli/ghostty.nix`: "do not use with RU until the version with W3C key-code
binds (#7320)". If ghostty is ever needed — remove the note after checking.

### P3 — system-level (optional)

- A single source of the EN↔JCUKEN correspondence (table below) so the duplicates in
  kitty/mpv/surfingkeys are generated consistently, as already done in `files/gui/swayimg/init.lua`
  via `key2()`.
- Gradually move important hotkeys to non-letter ("physical") keys so duplicates do not multiply
  endlessly.

## Changes made (by file)

| File                                                                | Change                                                                                                                       |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `files/gui/hypr/hyprland.lua`                                       | P0: comment about the invariants + explicit `resolve_binds_by_sym = false`                                                   |
| `files/kitty/key.conf`                                              | P1: Latin binds; RU duplicates are **generated** and appended from `lib/ru-keys.nix` (see "Duplicate generation")            |
| `modules/user/nix-maid/cli/shells.nix`                              | P1: `kittyRuBinds` data + `key.conf` generation; kitty config is deployed per file                                           |
| `modules/user/nix-maid/apps/mpv/input.nix`                          | P1: Cyrillic duplicates (pause/seek/fullscreen/mute/subtitles/upscale)                                                       |
| `files/surfingkeys.js`                                              | P1: langmap block `ru2en` + `api.map`                                                                                        |
| `files/gui/zellij/config.kdl`                                       | P2: `Alt+р/о/л/д` duplicates, resize/tab/scroll                                                                              |
| `modules/user/nix-maid/cli/yazi.nix`                                | P2: navigation and custom-bind duplicates — **generated** from `lib/ru-keys.nix` (`neg.ruKeys.mkRuKeys`)                     |
| `files/rmpc/config.ron`                                             | P2: global/navigation/queue duplicates (incl. uppercase)                                                                     |
| `files/cli/ghostty/config`, `modules/user/nix-maid/cli/ghostty.nix` | P2: "do not use with RU" note (config kept as a migration reference)                                                         |
| `lib/ru-keys.nix`                                                   | **new**: qwerty→JCUKEN table + generators (`mkRuKeys`, `kittySeq`, `mkKittyLines`, `mkLangmap`) — the single source of truth |
| `lib/ru-keys-tests.nix`, `flake/checks.nix`                         | **new**: `ru-keys` check (table completeness, bijection, golden for langmap/kitty lines)                                     |
| `modules/user/nix-maid/hyprland/ru-layout.nix`                      | **new**: layout-daemon — layout by active window (us in kitty/mpv, ru in the rest)                                           |
| `docs/howto/hotkeys-ru-layout.md`, `docs/howto/index.md`            | this document                                                                                                                |

"Not fixable via config" (mutt, rustmission, btop) is now **fixed automatically** by the
layout-daemon (see "Layout-daemon") — we do not touch the configs of these programs; the compositor
sets their layout.

## Layout-daemon: per-window layout (`features.input.ruHotkeys`)

The problem exists only because the ru layout is active in kitty/mpv at the moment a hotkey is
pressed. The `ru-layout` daemon (systemd-user, `hyprland-session.target`) watches the active window
and switches the XKB group **on focus change**:

- classes from `features.input.ruHotkeys.usClasses` (default `kitty`, `mpv`) → `us`;
- everything else (browser, chats, …) → `ru` (typing-first).

This fixes **all** TUI programs and everything that cannot be fixed via config at once: mutt,
rustmission, btop, tig, broot, khal, zsh vi-mode, kitty-hints — they need no duplicates because the
layout is already us. The rules apply only when the window changes: a manual `M4+S` inside a window
is not rolled back until the focus leaves it. Group indices (`usLayoutIndex`/`ruLayoutIndex`) follow
the `kb_layout = us,ru` invariant.

Enable: `features.input.ruHotkeys.enable = true` (enabled on odin). Check:
`systemctl --user status ru-layout`; in kitty press `M4+S` → in the neighboring window the layout
switches back to us by itself, in the browser to ru.

## Duplicate generation (refactor, `lib/ru-keys.nix`)

Handwritten Cyrillic duplicates are scattered across configs and silently drift out of sync with the
Latin binds. With `lib/ru-keys.nix` all duplicates are **generated** from a single table (qwerty →
JCUKEN):

- modules receive it as `neg.ruKeys` (via `lib/neg-helpers.nix`, specialArgs);
- `neg.ruKeys.mkRuKeys [ "j" ]` → `[ "о" ]` (yazi and similar apps with key lists);
- `neg.ruKeys.mkKittyLines [{ mod; keys; action; }]` → `map ctrl+shift+CYRILLIC_* …` lines (kitty:
  `kittyRuBinds` data in `modules/user/nix-maid/cli/shells.nix`);
- `neg.ruKeys.mkLangmap` reproduces the neovim langmap byte-for-byte (golden test).

Rule: do not write new duplicates by hand — add the bind to the data and/or extend the generator.
The `nix eval .#checks.x86_64-linux.ru-keys` check (and `nix flake check`) catches table desync.

Migration state (handwritten duplicates → generators):

- **done**: kitty (`kittyRuBinds` in `shells.nix`), yazi (`mkRuKeys`), mpv (`mpvRuBinds`), zellij
  (`zellijRuBinds` in `hosts/odin/default.nix`), rmpc (`rmpcRuBinds` in `sys/media.nix`),
  SurfingKeys (`skRu2en` in `web/browsing.nix`); neovim langmap cross-checked against the
  `mkLangmap` golden test.
- **still manual**: swayimg `init.lua` — its binds are inline-lua closures; generation would only
  move the duplication into data without a gain. The duplicates there work and are already verified.

Generation also fixed three old errors in the handwritten duplicates: rmpc navigation `D` → `В` (was
`в`), mpv `Alt+I`/`Alt+U` → `Alt+Ш`/`Alt+Г` (they were lowercase and did not match under Shift);
SurfingKeys received the missing `/` key (`'.'→'/'`).

## Commit order (repo style: `[scope] subject`)

1. `[docs] Document hotkey behavior under Russian keyboard layout` — this doc + index.md.
1. `[gui/hyprland] Pin keyboard-layout invariants (us first, resolve_binds_by_sym=false)` — P0.
1. `[cli/kitty] Add Russian-layout duplicates for kitty shortcuts` — P1 kitty.
1. `[media/audio] Add Russian-layout duplicates for mpv input` — P1 mpv.
1. `[web/vivaldi] Add Russian-layout langmap to SurfingKeys` — P1 surfingkeys.
1. `[cli/zellij] Add Russian-layout duplicates to keybinds` — P2 zellij.
1. `[cli/yazi] Add Russian-layout duplicates to yazi keymap` — P2 yazi.
1. `[media/audio] Add Russian-layout duplicates to rmpc keybinds` — P2 rmpc.
1. (opt.) `[nix-maid] Drop unused ghostty config` — P2 ghostty.

Each commit is self-contained and revertible; the duplicates are additive and do not break the US
layout. Pre-commit check: `nix flake check` / building the relevant modules is not required (the
changes touch only config files, not Nix expressions), but `hyprctl reload` and restarting
kitty/zellij/rmpc are needed to apply them.

## Acceptance

- US layout: nothing broke (the duplicates are additive; `hyprctl binds` shows no conflicts).
- RU layout:
  - Hyprland: `M4+*` binds work as before (`hyprctl getoption input:resolve_binds_by_sym` = false).
  - kitty: paste, closing tabs/windows, switching tabs/windows, scroll_to_prompt.
  - mpv: `з/ш/д/р/А/Ф` (pause/top bar/seek/fullscreen/audio), `Alt+ш/г` (upscale).
  - SurfingKeys: scroll/tabs/navigation.
  - zellij: `Alt+р/о/л/д`, resize/tab/scroll modes.
  - yazi: `о/л/р/д` navigation, `п п` (top), `в` (yank).
  - rmpc: `з/й/ы` (pause/quit/stop), `о/л/р/д` navigation, uppercase duplicates.
- Known issues (not fixable via config): mutt (j/k/g/macros), rustmission (h/l/k/j), btop (toggles),
  ghostty (not installed), SurfingKeys/kitty hints mode, `>`/`<` in mpv and rmpc.

## Appendix: JCUKEN ↔ Latin ↔ keysym

| Latin | RU  | Keysym (xkb)      | Latin            | RU    | Keysym (xkb)      |
| ----- | --- | ----------------- | ---------------- | ----- | ----------------- |
| q     | й   | Cyrillic_shorti   | z                | я     | Cyrillic_ya       |
| w     | ц   | Cyrillic_tse      | x                | ч     | Cyrillic_che      |
| e     | у   | Cyrillic_u        | c                | с     | Cyrillic_es       |
| r     | к   | Cyrillic_ka       | v                | м     | Cyrillic_em       |
| t     | е   | Cyrillic_ie       | b                | и     | Cyrillic_i        |
| y     | н   | Cyrillic_en       | n                | т     | Cyrillic_te       |
| u     | г   | Cyrillic_ghe      | m                | ь     | Cyrillic_softsign |
| i     | ш   | Cyrillic_sha      | ,                | б     | Cyrillic_be       |
| o     | щ   | Cyrillic_shcha    | .                | ю     | Cyrillic_yu       |
| p     | з   | Cyrillic_ze       | \`               | ё     | Cyrillic_io       |
| \[    | х   | Cyrillic_ha       | '                | э     | Cyrillic_e        |
| \]    | ъ   | Cyrillic_hardsign | ;                | ж     | Cyrillic_zhe      |
| a     | ф   | Cyrillic_ef       | /                | .     | period            |
| s     | ы   | Cyrillic_yeru     | -                | -     | minus (same)      |
| d     | в   | Cyrillic_ve       | =                | =     | equal (same)      |
| f     | а   | Cyrillic_a        | Space            | space | space (same)      |
| g     | п   | Cyrillic_pe       | Enter/Tab/arrows |       | same              |
| h     | р   | Cyrillic_er       | Esc/F1–F12       |       | same              |
| j     | о   | Cyrillic_o        |                  |       |                   |
| k     | л   | Cyrillic_el       |                  |       |                   |
| l     | д   | Cyrillic_de       |                  |       |                   |

Under the RU layout the characters `>`, `<`, `~` do not exist (in us they are on their own keys):
direct binds on `>`/`<` are unreachable, so for mpv duplicates were added on `Ю`/`Б` (the same
physical keys); `~` can only be remapped.

## Links

- Hyprland wiki, "Switchable keyboard layouts" / `resolve_binds_by_sym`:
  https://wiki.hypr.land/Configuring/Uncommon-tips-&-tricks/
- Hyprland source at the pinned revision `36b2e0cf`: `src/managers/KeybindManager.cpp`
  (`updateXKBTranslationState`, `onKeyEvent`), `src/config/values/ConfigValues.cpp`
  (`input:resolve_binds_by_sym`, default `false`).
- kovidgoyal/kitty#2000 — handling non-Latin layouts, the `CYRILLIC_*` workaround:
  https://github.com/kovidgoyal/kitty/issues/2000
- mpv `DOCS/man/input.rst` — "Key names": literal Unicode key, matched against the current layout.
- zellij `zellij-utils/src/data.rs` — `BareKey::from_str` (any single char).
- ghostty-org/ghostty#3513 ("Ctrl+D not working on Russian layout") and #3584 (CSI `82;5u`):
  https://github.com/ghostty-org/ghostty/issues/3513
- ghostty-org/ghostty#7320 — switching to W3C key code binds (Breaking Change):
  https://github.com/ghostty-org/ghostty/pull/7320
