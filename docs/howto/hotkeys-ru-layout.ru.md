# Хоткеи и русская раскладка: инвентаризация и план починки

> Статус: **реализовано** — P0 (Hyprland), P1 (kitty/mpv/SurfingKeys), P2 (zellij/yazi/rmpc);
> mutt и rustmission конфигом **не чинятся** (подтверждено по исходникам — см. «Валидация»);
> btop/ghostty — known issues. Все изменения аддитивны (US-раскладка не затронута).

## TL;DR

- **Хоткеи Hyprland (WM) уже работают в обеих раскладках.** Причина: `kb_layout = "us,ru"` —
  `us` стоит первой, а `input:resolve_binds_by_sym` не задан (по умолчанию `false`), т.е. бинды
  сопоставляются с символом **первой** раскладки (us), а не активной. Ломается всё только если
  переставить раскладки (`ru,us`) или включить `resolve_binds_by_sym = true`.
- **Главные жертвы RU-раскладки** — программы, которые матчат хоткеи по keysym активной
  раскладки без fallback:
  - `kitty` — все `kitty_mod` (Ctrl+Shift+буква) и `Ctrl+буква`-шорткаты из `files/kitty/key.conf`;
  - `mpv` — буквенные клавиши (`p i r t v f l h L H m j s` и т.д.);
  - SurfingKeys в Vivaldi — vim-навигация (`j k h l t d u w o e b v s H L F` и т.д.);
  - TUI-программы в терминале (zellij, mutt, yazi, rustmission, rmpc, khal, broot, tig) —
    «голые» буквы и `Alt+буква`.
- **Уже починено:** swayimg (дубли ЙЦУКЕН в `init.lua`), neovim (langmap + langmapper.nvim).
- **Всегда работает:** `Ctrl+буква` внутри терминала (zsh, zellij, mutt и пр.) — терминал шлёт
  управляющие байты по физической клавише, раскладка не влияет.

## Механика: почему вообще ломается

Клавиатурное событие несёт два идентификатора:

- **keycode** — физическая клавиша (например, `KEY_D` = 40). Не зависит от раскладки.
- **keysym** — символ, который клавиша даёт в **активной** раскладке (`d` в us, `в` в ru).

Хоткей, заданный латинской буквой, матчится по keysym. В RU-раскладке keysym становится
кириллическим, и матч не срабатывает. Дальше всё зависит от слоя:

| Слой | Поведение под RU |
|---|---|
| **Hyprland (бинды)** | ✅ Бинды сопоставляются с keysym **первой** раскладки (`us`), т.к. `resolve_binds_by_sym = false` (дефолт) и состояние перевода строится от `kb_layout` с группой 0. Все `SUPER+d`, `M4+SHIFT+r` и сабмапы работают в обеих раскладках. |
| **Qt-приложения** | ✅ `Ctrl+буква` работает (Qt берёт латинскую клавишу из группы 0 при нажатом модификаторе). ❌ «Голые» буквы и `Alt+буква` матчатся по фактическому символу. |
| **GTK-приложения** | ✅ `Ctrl+буква` в основном работает (fallback на keyval группы 0). ❌ «Голые» буквы — ломаются. |
| **Electron/Chromium** (Vivaldi, Obsidian, VS Code) | ✅ `Ctrl+буква` работает (акселераторы Chromium считаются от физической клавиши/US keycode). ❌ Бинды без модификатора (vim-стиль) матчатся по `event.key` → кириллица. |
| **kitty** | ❌ Свои шорткаты матчит по keysym **активной** раскладки (см. kovidgoyal/kitty#2000 — официальный воркэраунд: дубли `map ctrl+CYRILLIC_ES ...`). |
| **ghostty** | ⚠️ Известные баги даже с `Ctrl+буква` под RU (ghostty-org/ghostty#3513, #3584); лечится в новых версиях переходом на W3C key-code бинды (#7320). |
| **TUI в терминале** | ✅ `Ctrl+буква` — терминал превращает в управляющий байт (0x00–0x1F) по физической клавише. ❌ Буква без модификатора / `Alt+буква` — приложение получает кириллический символ. |
| **Игры (SDL)** | ✅ Сканкоды физических клавиш — раскладка не влияет. |

## Валидация: что проверено и где

| Утверждение | Как проверено | Итог |
|---|---|---|
| Бинды Hyprland резолвятся по **первой** раскладке | Исходник зафиксированной ревизии `36b2e0cf`: `KeybindManager.cpp` — `xkb_state_key_get_one_sym(m_resolveBindsBySym ? m_xkbSymState : m_xkbTranslationState, KEYCODE)`; `m_xkbTranslationState = xkb_state_new(keymap)` (группа 0); `ConfigValues.cpp` — `resolve_binds_by_sym` default `false` | ✅ |
| kitty матчит шорткаты по keysym **активной** раскладки, имена `CYRILLIC_*` валидны | `kitty/key_names.py` (разбор имён через `xkb_keysym_from_name`); официальный воркэраунд мейнтейнера в kovidgoyal/kitty#2000 (`map ctrl+CYRILLIC_ES send_text all \x03`) | ✅ |
| mpv матчит «переведённый» текст активной раскладки; литеральные Unicode-клавиши в input.conf | `mpv DOCS/man/input.rst`: «`<key>` is either the literal character … (ASCII or Unicode)», «mpv uses input translated by the current OS keyboard layout, rather than physical scan codes» | ✅ |
| zellij принимает кириллические ключи в конфиге | `zellij-utils/src/data.rs` — `BareKey::from_str`: любой одиночный char; матчинг — `KeyCode::Char(c)` (`input/mod.rs`) | ✅ |
| В терминале `Ctrl+буква` = управляющий байт по физической клавише | Стандартное поведение терминалов (kitty без keyboard-протокола шлёт control-байт от keycode) | ✅ |
| Chromium/Electron: `Ctrl+буква` по физической клавише | Известное, широко задокументированное поведение (accelerator = US `KeyboardCode` от `DomCode`) | ✅ (эмпирически) |
| yazi принимает кириллические ключи (строчные) | `yazi-config/src/keymap/key.rs` — `Key::from_str`: любой одиночный char; uppercase подразумевает SHIFT → кириллическая заглавная не сматчится | ✅ (строчные) |
| rmpc принимает кириллические ключи | `rmpc/src/config/keys/key.rs` — winnow `any` (любой Unicode-char), регистр → SHIFT | ✅ |
| neomutt **не** принимает кириллические ключи | `key/keymap.c` — `parse_keys`: `*d = (unsigned char) *s` (байт); UTF-8-символ (2 байта) привяжется к первому байту и сломает ввод | ❌ не чинится |
| rustmission **не** принимает кириллические ключи | intuitils `keybindings.rs`: `if key.len() == 1` (байтовая длина); кириллица = 2 байта → ошибка парсинга | ❌ не чинится |

## Инвентаризация по конфигу

Легенда: ✅ работает / ❌ ломается / ⚠️ частично или требует проверки.

| Программа | Что с RU-раскладкой | Статус | Файл |
|---|---|---|---|
| Hyprland (все бинды, сабмапы) | бинды по первой раскладке — работают | ✅ | `files/gui/hypr/hyprland.lua` |
| greetd / Hyprland-греетер | `us,ru`, старт с us; биндов нет | ✅ | `modules/user/session/greetd.nix` |
| swayimg | дубли ЙЦУКЕН для всех действий | ✅ (починено) | `files/gui/swayimg/init.lua` |
| neovim | langmap + langmapper.nvim | ✅ (починено) | `files/nvim/lua/00-settings.lua`, `files/nvim/lua/plugins/keymap/langmap.lua` |
| espanso | `ALT+SPACE` — без букв; триггеры `:date` — текст | ✅ | `modules/user/nix-maid/cli/espanso.nix` |
| vicinae | бинды `Ctrl+буква` (Qt fallback) | ✅ (проверить руками) | `modules/user/nix-maid/apps/vicinae.nix` |
| kitty | `kitty_mod+буква` (Ctrl+Shift), `Ctrl+s>l/p/h`, `kitty_mod+,/.`/grave/`[`/`]`, `Alt+n` и пр. | ❌ | `files/kitty/key.conf` |
| mpv | `p i r t v f l h L H m j s A`, `Ctrl+h/l/H`, `Alt+I/U`, `>`/`<` (в RU их вообще нет) | ❌ | `modules/user/nix-maid/apps/mpv/input.nix` |
| SurfingKeys (Vivaldi) | vim-клавиши `j k h l t d u w o e b v s H L F J+,`; **набор hint-букв** (`asdfghjkl`) тоже | ❌ | `files/surfingkeys.js` |
| zellij | `Alt+h/j/k/l`; в режимах resize/tab/scroll: `h j k l n r` | ✅ (починено) | `files/gui/zellij/config.kdl` |
| mutt | `j k g G R u gg`, макросы с буквами; стрелки работают | ❌ (не чинится) | `modules/user/nix-maid/mutt-conf/04-bindings.mutt` |
| yazi | `g d f p` и навигация `h j k l` | ✅ (починено, строчные) | `modules/user/nix-maid/cli/yazi.nix` |
| rustmission | `h l k j H L` | ❌ (не чинится) | `files/config/rustmission/keymap.toml` |
| rmpc | `p s q u w b f o z r y a d g G j k h l n N m M` и др. | ✅ (починено) | `files/rmpc/config.ron` |
| khal | `e` (edit), `d` (duplicate) | ❌ | `modules/user/nix-maid/sys/khal.nix` |
| btop | тумблеры `d n m c f` — **клавиши захардкожены, конфигом не ремапятся** | ❌ (не чинится) | `modules/user/nix-maid/cli/monitoring.nix` |
| broot / tig / amfora | буквенные бинды | ❌ | (стандартные конфиги) |
| nethack | буквенные команды (игра) | ❌ | `modules/user/nix-maid/fun/nethack.nix` |
| zsh vi-mode | `h/j/k/l` в командном режиме | ❌ | `modules/user/nix-maid/cli/shells.nix` |
| satty (скриншоты) | одиночные буквы (GTK, без модификатора) | ⚠️ | — |
| ghostty | конфиг развёрнут, **пакет не установлен**; известные баги `Ctrl+буква` под RU | ⚠️ | `files/cli/ghostty/config` |
| Vivaldi / Obsidian (Chromium) | системные `Ctrl+буква` ✅; буквенные бинды расширений ❌ | ⚠️ | — |

### Конкретика по kitty (`files/kitty/key.conf`)

`kitty_mod = ctrl+shift`. Под RU ломаются все мапы с латинскими буквами, а также знаки,
меняющие положение в RU (`,` → `б`, `.` → `ю`, `` ` `` → `ё`, `[` → `х`, `]` → `ъ`):

- `kitty_mod+v` (paste), `kitty_mod+z/x` (scroll_to_prompt)
- `kitty_mod+q` (close_tab), `kitty_mod+w` (close_window)
- `kitty_mod+b/f/]/[` (движение по окнам), `kitty_mod+comma/period` (табы)
- `kitty_mod+grave` (move_window_to_top), `kitty_mod+l` (next_layout)
- `kitty_mod+p/u/e/h/o` (hints / scrollback), `kitty_mod+s>f/w/l/p/h` (neghints)
- `Ctrl+s>w/l/p/h` (neghints в stdout), `Ctrl+alt+s` (screen scrollback), `alt+n` (new_tab)
- `kitty_mod+r>r` / `r>e`, `kitty_mod+a>1/d/l/m` (opacity), `kitty_mod+t` (title)
- `mouse_map ctrl+shift+right` — не зависит от раскладки (модификаторы+кнопка) ✅

Не ломаются: `insert`, `delete`, `escape`, `f2`, `backspace`, `equal/minus`, `ctrl+left/right`,
`kitty_mod+backspace`.

### Конкретика по mpv (`input.nix`)

Ломаются: `p` (пауза), `i` (топбар), `r/t` (субтитры), `v` (видимость субтитров), `F`
(fullscreen), `l/h/L/H` (сик), `m` (mute), `A` (аудиодорожка), `R` (window-scale), `j/s`
(субтитры), `Alt+I`/`Alt+U` (AI-апскейл), `>`/`<` (next/prev) — в RU-раскладке символов `>`
и `<` нет вовсе, так что эти бинды недостижимы и их нужно переназначить. `Ctrl+h/l/H` (speed) —
тоже ломаются (это шорткаты mpv, а не управляющие байты терминала). `space`, `0/9`, `WHEEL_*`,
`Alt+0/1/2`, `Ctrl+enter` — не зависят от раскладки ✅.

### Конкретика по SurfingKeys (`files/surfingkeys.js`)

Vim-навигация без модификаторов: `j k h l` (скролл), `t` (новая вкладка), `d` (закрыть),
`u` (восстановить), `w` (список вкладок), `o` (адресная строка), `e` (следующая вкладка),
`b/v/s` (скролл), `H/L` (назад/вперёд), `F` (открыть в новой вкладке), `J`/`,`+буква
(сайты), `]`/`[` (скорость видео) и т.д. — всё это матчится по `event.key` → кириллица.
Ограничение: режим hints (`f`) принимает только `hintChars = "asdfghjkl"` — под RU набор
hint-букв ломается и конфигом не чинится (нужна US-раскладка для хинтов). То же касается
`kitten hints --alphabet wersdfa` в kitty.

Исключения по URL: `settings.blocklistPattern` полностью отключает SurfingKeys на
dsh web GUI (`127.0.0.1:3080` / `localhost:3080` — там свои шорткаты и Tab-автокомплит),
а также на `mail.google.com`, `docs.google.com`, `discord.com`, `app.slack.com`.
Порт ограничен, чтобы другие loopback-страницы (например, `localhost:5173`) сохраняли
SurfingKeys. Проверка: `check-surfingkeys`.

## План починки (по приоритетам)

### P0 — Hyprland: зафиксировать инварианты (без риска)

**Файл:** `files/gui/hypr/hyprland.lua` (секция `input`, строка `kb_layout`).

Добавить комментарий и (опционально) явное значение, чтобы инвариант не потерялся:

```lua
-- Keyboard layouts: `us` MUST stay first. Binds are resolved against the FIRST
-- layout (input:resolve_binds_by_sym = false is the default), so `us,ru` keeps
-- all binds working in both layouts. Switching: M4+S.
kb_layout = "us,ru", kb_variant = "", kb_model = "", kb_options = "", kb_rules = "",
resolve_binds_by_sym = false,
```

**Проверка:** `hyprctl getoption input:resolve_binds_by_sym` → `false`; в RU-раскладке
проверить `M4+d`, `M4+w`, `M4+SHIFT+r`, сабмапы (`M4+M1+r`, `M4+minus`).

### P1 — kitty (основной терминал, самый частый сценарий)

**Файл:** `files/kitty/key.conf` — блок «Russian layout duplicates (ЙЦУКЕН)» **генерируется**
из `lib/ru-keys.nix` (`kittyRuBinds` в `shells.nix`) и использует **литеральные кириллические
символы** (`map ctrl+shift+м …`) — ровно как латинские бинды kitty.

> ⚠️ Исправление (2026-08): исходный план использовал keysym-имена `CYRILLIC_*` — на этой
> системе они **не работают**: kitty резолвит их через `xkb_keysym_from_name`, а
> `libxkbcommon` не загружается (нет ld-кэша), поэтому имена молча отбрасываются как
> «unknown key» (регистр тоже важен: `Cyrillic_em`, а не `CYRILLIC_EM`). Литеральные
> символы парсятся без либы и матчатся тем же механизмом, что и латинские бинды: событие
> кириллического keysym несёт сам символ (подтверждено тестами kitty, `kitty_tests/keys.py`).

Ниже — исторический пример (не применять как есть):

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
map ctrl+shift+CYRILLIC_ZE      kitten choose_files         # kitty_mod+p  (p→з)
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

Если блок кажется громоздким — минимум: paste, close_tab/close_window, переключение
табов/окон, scroll_to_prompt, `kitty_mod+grave` (move_window_to_top).

**Проверка:** `kitty +kitten debug_keyboard` под RU (сверить имена keysym), затем по очереди
пройтись по дублям.

### P1 — mpv

**Файл:** `modules/user/nix-maid/apps/mpv/input.nix` — добавить кириллические дубли
(литеральные символы; mpv принимает «literal character … (ASCII or Unicode)»):

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

`>`/`<` (next/prev) — в RU недостижимы: вариант (а) оставить как есть (переключение мышью /
из плейлиста), (б) добавить дубли на `Ю`/`Б` (shift+`.`/`,`). `Alt+0/1/2` — цифры в RU те же,
дубли не нужны.

**Проверка:** `mpv --input-test` под RU (имя нажатой клавиши), затем `p`/`l`/`h`/`F`/`Alt+I`.

### P1 — SurfingKeys

**Файл:** `files/surfingkeys.js` — после существующих `map`/`mapkey` добавить компактный блок
«langmap» (rhs у `api.map` — это последовательность клавиш, диспатчится в команды без
пересоздания DOM-события, поэтому кириллица в lhs не зацикливается):

```js
// Russian layout: Cyrillic → Latin commands (ЙЦУКЕН)
const ru2en = { 'й':'q','ц':'w','у':'e','к':'r','е':'t','н':'y','г':'u','ш':'i','щ':'o','з':'p',
  'х':'[','ъ':']','ф':'a','ы':'s','в':'d','а':'f','п':'g','р':'h','о':'j','л':'k','д':'l',
  'ж':';','э':"'",'я':'z','ч':'x','с':'c','м':'v','и':'b','т':'n','ь':'m','б':',','ю':'.' };
Object.entries(ru2en).forEach(([ru, en]) => api.map(ru, en));
```

Альтернатива (если `api.map(ru, en)` по какой-то причине не сработает — проверить в консоли
браузера): точечные `api.mapkey('о', 'Scroll down', ...)` дубли для самых ходовых клавиш.

**Ограничения (не чинится скриптом):** набор hint-букв в режиме hints (`f`) — только
`asdfghjkl` (нужна US); `settings.hintChars` при желании можно заменить на цифры/знаки,
не зависящие от раскладки.

**Проверка:** под RU в браузере: `о`/`р`/`л`/`д` — скролл, `е` — новая вкладка, `в` —
закрыть, `г` — восстановить.

### P2 — zellij ✅ (кириллица в конфиге подтверждена по исходникам)

**Файл:** `files/gui/zellij/config.kdl` — дубли добавлены (только буквенные; Ctrl-бинды не
тронуты): `Alt+р/о/л/д` (MoveFocus), resize `р/о/л/д`, tab `д/р/т/к`, scroll `о/л`.

**Проверка:** zellij → RU → `Alt+р/о/л/д`; `Ctrl+b` → resize → `р/о/л/д`; tab/scroll режимы.

### P2 — mutt ❌ (не чинится конфигом)

Проверено по исходникам neomutt (`key/keymap.c`): `parse_keys` раскладывает ключ на **байты**
(`*d = (unsigned char) *s`), а кириллический символ — это 2 байта UTF-8. Привязка `bind pager о
...` забиндит байт `0xD0` (первый байт любого кириллического символа) и **сломает ввод
кириллицы** в mutt. Дубли не добавляем. Навигация стрелками (дефолтная) под RU работает;
буквенные бинды (`j k g G R u`) остаются US-only — known issue.

### P2 — yazi ✅ / rustmission ❌ / rmpc ✅

- **yazi** (`modules/user/nix-maid/cli/yazi.nix`): дубли добавлены — навигация `о/л/р/д`
  (j/k/h/l), `п п` (gg → top), `в` (d → yank), `п ы / п я / п к / п з` (g s / g z / g r / g p),
  `з` (p → smart-paste). Проверено по исходникам (`Key::from_str` принимает любой одиночный
  char); **только строчные** — заглавная кириллица несёт SHIFT и не сматчится.
- **rustmission** (`files/config/rustmission/keymap.toml`): ❌ не чинится — парсер intuitils
  проверяет `key.len() == 1` (байты); кириллица (2 байта) → ошибка парсинга keymap.toml.
  Навигация остаётся US-only — known issue.
- **rmpc** (`files/rmpc/config.ron`): дубли добавлены (global/navigation/queue). Проверено по
  исходникам (`winnow any` — любой Unicode-char; регистр → SHIFT). Заглавные кириллические
  дубли (`Д/Щ/З/Г/К/Ф/П/О/Л/Т/С`) работают.
- **khal** (`modules/user/nix-maid/sys/khal.nix`): `e→у`, `d→в` — по желанию (редко используемые).
- **broot / tig**: стандартные конфиги — по желанию, тем же приёмом.
- **btop**: клавиши **захардкожены**, конфигом не ремапятся — навигация стрелками работает,
  буквенные тумблеры (`d n m c f`) под RU недоступны; принять или заменить.
- **nethack / zsh vi-mode / satty**: не чиним (игры/краевые случаи), фиксируем как known issue.

### P2 — ghostty ✅ (решение: оставить с пометкой)

Пакет не установлен (kitty — основной терминал). Решение принято: **оставить** как
миграционный референс, с пометкой в шапке `files/cli/ghostty/config` и в модуле
`modules/user/nix-maid/cli/ghostty.nix`: «не использовать с RU до версии с W3C key-code
биндами (#7320)». Если ghostty когда-нибудь понадобится — пометку снять после проверки.

### P3 — системное (опционально)

- Единый источник соответствия EN↔ЙЦУКЕН (таблица ниже) — чтобы дубли в kitty/mpv/surfingkeys
  генерировались согласованно, как уже сделано в `files/gui/swayimg/init.lua` через `key2()`.
- Важные хоткеи со временем переводить на небуквенные («физические») клавиши, чтобы дубли не
  плодились бесконечно.

## Внесённые изменения (по файлам)

| Файл | Изменение |
|---|---|
| `files/gui/hypr/hyprland.lua` | P0: комментарий про инварианты + явное `resolve_binds_by_sym = false` |
| `files/kitty/key.conf` | P1: латинские бинды; RU-дубли **генерируются** и дописываются из `lib/ru-keys.nix` (см. «Генерация дублей») |
| `modules/user/nix-maid/cli/shells.nix` | P1: данные `kittyRuBinds` + генерация `key.conf`; kitty-конфиг разворачивается пофайлово |
| `modules/user/nix-maid/apps/mpv/input.nix` | P1: кириллические дубли (пауза/сик/fullscreen/mute/субтитры/апскейл) |
| `files/surfingkeys.js` | P1: langmap-блок `ru2en` + `api.map` |
| `files/gui/zellij/config.kdl` | P2: дубли `Alt+р/о/л/д`, resize/tab/scroll |
| `modules/user/nix-maid/cli/yazi.nix` | P2: дубли навигации и кастомных биндов — **генерируются** из `lib/ru-keys.nix` (`neg.ruKeys.mkRuKeys`) |
| `files/rmpc/config.ron` | P2: дубли global/navigation/queue (вкл. заглавные) |
| `files/cli/ghostty/config`, `modules/user/nix-maid/cli/ghostty.nix` | P2: пометка «не использовать с RU» (конфиг оставлен как миграционный референс) |
| `lib/ru-keys.nix` | **новый**: таблица qwerty→йцукен + генераторы (`mkRuKeys`, `kittySeq`, `mkKittyLines`, `mkLangmap`) — единственный источник правды |
| `lib/ru-keys-tests.nix`, `flake/checks.nix` | **новый**: чек `ru-keys` (полнота таблицы, биекция, golden для langmap/kitty-строк) |
| `modules/user/nix-maid/hyprland/ru-layout.nix` | **новый**: layout-daemon — раскладка по активному окну (us в kitty/mpv, ru в остальных) |
| `docs/howto/hotkeys-ru-layout.ru.md`, `docs/howto/index.md` | этот документ |

«Не чинится конфигом» (mutt, rustmission, btop) теперь **чинится автоматически** layout-daemon'ом
(см. «Layout-daemon») — конфиги этих программ не трогаем, раскладку им задаёт композитор.

## Layout-daemon: раскладка по активному окну (`features.input.ruHotkeys`)

Проблема существует только потому, что в kitty/mpv активна ru-раскладка в момент нажатия хоткея.
Демон `ru-layout` (systemd-user, `hyprland-session.target`) следит за активным окном и переключает
XKB-группу **на смене фокуса**:

- классы из `features.input.ruHotkeys.usClasses` (по умолчанию `kitty`, `mpv`) → `us`;
- всё остальное (браузер, чаты, …) → `ru` (typing-first).

Так чинятся разом **все** TUI-программы и то, что конфигом не лечится: mutt, rustmission, btop,
tig, broot, khal, zsh vi-mode, kitty-hints — им не нужны дубли, потому что раскладка уже us.
Правила применяются только на смене окна: ручной `M4+S` внутри окна не откатывается, пока фокус
не уйдёт. Индексы групп (`usLayoutIndex`/`ruLayoutIndex`) следуют инварианту `kb_layout = us,ru`.

Включение: `features.input.ruHotkeys.enable = true` (на odin — включено).
Проверка: `systemctl --user status ru-layout`; в kitty поднять `M4+S` → в соседнем окне раскладка
сама вернётся на us, в браузере — на ru.

## Генерация дублей (refactor, `lib/ru-keys.nix`)

Ручные кириллические дубли рассыпаются по конфигам и тихо рассинхронизируются с латинскими
биндами. С `lib/ru-keys.nix` все дубли **генерируются** из одной таблицы (qwerty→йцукен):

- модули получают её как `neg.ruKeys` (через `lib/neg-helpers.nix`, specialArgs);
- `neg.ruKeys.mkRuKeys [ "j" ]` → `[ "о" ]` (yazi и аналоги со списками клавиш);
- `neg.ruKeys.mkKittyLines [{ mod; keys; action; }]` → строки `map ctrl+shift+CYRILLIC_* …`
  (kitty: данные `kittyRuBinds` в `modules/user/nix-maid/cli/shells.nix`);
- `neg.ruKeys.mkLangmap` воспроизводит langmap neovim байт-в-байт (golden-тест).

Правило: новые дубли руками не писать — добавлять бинд в данные и/или расширять генератор.
Чек `nix eval .#checks.x86_64-linux.ru-keys` (и `nix flake check`) ловит рассинхрон таблицы.

Состояние миграции (рукописные дубли → генераторы):

- **готово**: kitty (`kittyRuBinds` в `shells.nix`), yazi (`mkRuKeys`), mpv (`mpvRuBinds`),
  zellij (`zellijRuBinds` в `hosts/odin/default.nix`), rmpc (`rmpcRuBinds` в `sys/media.nix`),
  SurfingKeys (`skRu2en` в `web/browsing.nix`); neovim langmap сверен с `mkLangmap` golden-тестом.
- **осталось вручную**: swayimg `init.lua` — бинды это inline-lua-замыкания; генерация лишь
  перенесла бы дублирование в данные без выигрыша. Дубли там работают и уже проверены.

Заодно генерация исправила три старые ошибки рукописных дублей: rmpc-навигация `D` → `В`
(было `в`), mpv `Alt+I`/`Alt+U` → `Alt+Ш`/`Alt+Г` (были строчные, не матчились под Shift);
SurfingKeys получил недостающую клавишу `/` (`'.'→'/'`).

## Порядок коммитов (стиль репо: `[scope] subject`)

1. `[docs] Document hotkey behavior under Russian keyboard layout` — этот док + index.md.
2. `[gui/hyprland] Pin keyboard-layout invariants (us first, resolve_binds_by_sym=false)` — P0.
3. `[cli/kitty] Add Russian-layout duplicates for kitty shortcuts` — P1 kitty.
4. `[media/audio] Add Russian-layout duplicates for mpv input` — P1 mpv.
5. `[web/vivaldi] Add Russian-layout langmap to SurfingKeys` — P1 surfingkeys.
6. `[cli/zellij] Add Russian-layout duplicates to keybinds` — P2 zellij.
7. `[cli/yazi] Add Russian-layout duplicates to yazi keymap` — P2 yazi.
8. `[media/audio] Add Russian-layout duplicates to rmpc keybinds` — P2 rmpc.
9. (опц.) `[nix-maid] Drop unused ghostty config` — P2 ghostty.

Каждый коммит самодостаточен и откатываем; дубли аддитивны и не ломают US-раскладку.
Проверка перед коммитами: `nix flake check` / сборка соответствующих модулей не обязательна
(изменения только в конфиг-файлах, не в Nix-выражениях), но `hyprctl reload` и перезапуск
kitty/zellij/rmpc нужны для применения.

## Приёмка (acceptance)

- US-раскладка: ничего не сломалось (дубли аддитивны; `hyprctl binds` не показывает конфликтов).
- RU-раскладка:
  - Hyprland: `M4+*`-бинды работают как раньше (`hyprctl getoption input:resolve_binds_by_sym` = false).
  - kitty: paste, закрытие таба/окна, переключение табов/окон, scroll_to_prompt.
  - mpv: `з/ш/д/р/А/Ф` (пауза/топбар/сик/fullscreen/audio), `Alt+ш/г` (апскейл).
  - SurfingKeys: скролл/вкладки/навигация.
  - zellij: `Alt+р/о/л/д`, режимы resize/tab/scroll.
  - yazi: навигация `о/л/р/д`, `п п` (top), `в` (yank).
  - rmpc: `з/й/ы` (пауза/выход/стоп), навигация `о/л/р/д`, заглавные дубли.
- Known issues (не чинятся конфигом): mutt (j/k/g/макросы), rustmission (h/l/k/j), btop
  (тумблеры), ghostty (не установлен), hints-режим SurfingKeys/kitty, `>`/`<` в mpv и rmpc.

## Приложение: ЙЦУКЕН ↔ латиница ↔ keysym

| Латинская | RU | Keysym (xkb) | Латинская | RU | Keysym (xkb) |
|---|---|---|---|---|---|
| q | й | Cyrillic_shorti | z | я | Cyrillic_ya |
| w | ц | Cyrillic_tse | x | ч | Cyrillic_che |
| e | у | Cyrillic_u | c | с | Cyrillic_es |
| r | к | Cyrillic_ka | v | м | Cyrillic_em |
| t | е | Cyrillic_ie | b | и | Cyrillic_i |
| y | н | Cyrillic_en | n | т | Cyrillic_te |
| u | г | Cyrillic_ghe | m | ь | Cyrillic_softsign |
| i | ш | Cyrillic_sha | , | б | Cyrillic_be |
| o | щ | Cyrillic_shcha | . | ю | Cyrillic_yu |
| p | з | Cyrillic_ze | ` | ё | Cyrillic_io |
| [ | х | Cyrillic_ha | ' | э | Cyrillic_e |
| ] | ъ | Cyrillic_hardsign | ; | ж | Cyrillic_zhe |
| a | ф | Cyrillic_ef | / | . | period |
| s | ы | Cyrillic_yeru | - | - | minus (тот же) |
| d | в | Cyrillic_ve | = | = | equal (тот же) |
| f | а | Cyrillic_a | Space | пробел | space (тот же) |
| g | п | Cyrillic_pe | Enter/Tab/стрелки | | те же |
| h | р | Cyrillic_er | Esc/F1–F12 | | те же |
| j | о | Cyrillic_o | | | |
| k | л | Cyrillic_el | | | |
| l | д | Cyrillic_de | | | |

В RU-раскладке символов `>`, `<`, `~` нет (в us они на своих местах), поэтому бинды на них
недостижимы — только переназначение.

## Ссылки

- Hyprland wiki, «Switchable keyboard layouts» / `resolve_binds_by_sym`:
  https://wiki.hypr.land/Configuring/Uncommon-tips-&-tricks/
- Hyprland исходник зафиксированной ревизии `36b2e0cf`: `src/managers/KeybindManager.cpp`
  (`updateXKBTranslationState`, `onKeyEvent`), `src/config/values/ConfigValues.cpp`
  (`input:resolve_binds_by_sym`, default `false`).
- kovidgoyal/kitty#2000 — обработка не-латинских раскладок, воркэраунд с `CYRILLIC_*`:
  https://github.com/kovidgoyal/kitty/issues/2000
- mpv `DOCS/man/input.rst` — «Key names»: literal Unicode key, matching по текущей раскладке.
- zellij `zellij-utils/src/data.rs` — `BareKey::from_str` (любой одиночный char).
- ghostty-org/ghostty#3513 («Ctrl+D not working on Russian layout») и #3584 (CSI `82;5u`):
  https://github.com/ghostty-org/ghostty/issues/3513
- ghostty-org/ghostty#7320 — переход на W3C key code бинды (Breaking Change):
  https://github.com/ghostty-org/ghostty/pull/7320
