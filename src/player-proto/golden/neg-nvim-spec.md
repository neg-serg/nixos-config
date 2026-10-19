# neg.nvim → native desktop app restyle spec

Implementation-ready description of the `neg` Neovim colorscheme, intended for porting the
look to a native GPU desktop app (Rust music player). Every value below is either a literal
from the plugin sources or a computed derivation of literals, using the plugin's own
math (`lua/neg/util.lua`). Nothing is invented; where the source is silent, the text says so.

Conventions used in this document:

- `fg`/`bg`/`sp` are `#rrggbb` or `NONE` (transparent / inherit).
- "resolved" means: follow `link=` chains, apply the default option set, and apply the
  post-processing passes that run by default in `M.setup()`.
- Contrast ratios are WCAG 2.1 relative-luminance ratios, computed with the same sRGB
  linearisation the plugin itself uses in `lua/neg/validate.lua`.

---

## 1. Provenance

| item | value |
|---|---|
| Plugin root | `/home/neg/.local/share/nvim/lazy/neg.nvim` |
| Declared version | `4.72` (`-- Version:     4.72`, `lua/neg/init.lua` line 2) |
| Last change stamp | `16-10-2026` (`lua/neg/init.lua` line 3) |
| Git HEAD | `e82e0560662e154710dbab50c11c81916268ae70` (2026-10-16 09:49:58 +0300) |
| Git describe | `v4.50-43-ge82e056` |
| HEAD subject | `docs(release): update CHANGELOG and release notes for 4.72` |
| Upstream | `https://github.com/neg-serg/neg.nvim` |
| Lineage | extends Jason W Ryan's miromiro(1) Vim color file (header comment in `init.lua`) |

Files read (all absolute paths under the plugin root):

```
lua/neg/init.lua                     # highlight mapping + all post-processing passes
lua/neg/palette.lua                  # raw palette and aliases
lua/neg/util.lua                     # lighten / darken / alpha / terminal colors / transparency
lua/neg/options.lua                  # option schema (toggles, enums, ranges)
lua/neg/validate.lua                 # self-validation rules + optional contrast gate
lua/neg/commands.lua                 # (skimmed) runtime command surface
lua/neg/groups/editor.lua            # core editor + Pmenu + diff groups
lua/neg/groups/editor_extras.lua     # PmenuMatch, Cursor, EndOfBuffer, VisualNOS, FloatShadow
lua/neg/groups/legacy.lua            # legacy Vim syntax groups
lua/neg/groups/diagnostics.lua       # Diagnostic* families
lua/neg/groups/lsp.lua               # Lsp* groups
lua/neg/groups/treesitter.lua        # @capture mapping
lua/neg/groups/treesitter_extras.lua
lua/neg/groups/plugins/telescope.lua
lua/neg/groups/plugins/which_key.lua
lua/neg/groups/plugins/nvim_tree.lua
lua/neg/groups/plugins/neo_tree.lua
lua/neg/groups/plugins/trouble.lua
lua/neg/groups/plugins/noice.lua
lua/neg/groups/plugins/snacks.lua
lua/neg/groups/plugins/cmp.lua
lua/neg/groups/plugins/blink.lua
lua/neg/groups/plugins/indent.lua
lua/neg/groups/plugins/rainbow.lua
README.md
CHANGELOG.md
RELEASE_NOTES.md
lua/neg/RELEASE_NOTES.md             # per-version release notes (4.72 entry: Pmenu rules)
```

Default configuration actually in force (from `default_config` in `init.lua`), because every
resolved color depends on it:

```lua
saturation = 100, alpha_overlay = 0, transparent = false, terminal_colors = true,
preset = nil, operator_colors = 'families', number_colors = 'ramp',
ui = {
  core_enhancements = true, dim_inactive = false, mode_accent = true, focus_caret = true,
  soft_borders = false, float_panel_bg = false, auto_transparent_panels = true,
  diff_focus = true, light_signs = false, outlines = false,
  reading_mode = false, search_visibility = 'default', screenreader_friendly = false,
  telescope_accents = true, path_separator_blue = false, selection_model = 'kitty',
},
treesitter = { extras = true, punct_family = false },
styles = { comments = 'italic', keywords/functions/strings/variables/types/operators/
           numbers/booleans/constants/punctuation = 'none' },
diagnostics_virtual_bg = false, diagnostics_virtual_bg_blend = 15,
diagnostics_virtual_bg_mode = 'blend', diagnostics_virtual_bg_strength = 0.15,
```

---

## 2. Raw palette

Source file: `lua/neg/palette.lua`. The literal Lua keys are given, plus the descriptive
aliases the palette defines for them (aliases are pure copies, listed once per family).

### 2.1 Backgrounds and surfaces

| key | hex | derived? | alias | role comment (verbatim) |
|---|---|---|---|---|
| `bclr` | `#000000` | no | `bg_default` | background color hexadecimal |
| `dark` | `#121212` | no | `fg_dark`, `dark_color` | dark color |
| `culc` | `#272727` | no | `bg_cursorcolumn` | cursor line/column hexadecimal |
| `visu` | `#080808` | no | `bg_visual` | visual highlight |
| `clin` | `#131e30` | no | `bg_cursorline` | cursor line |
| `dnorm` | `#15181f` | no | `bg_selection_dim` | (no comment; used as the theme-mode Visual bg) |
| `tkic` | `#111827` | no | `telekasten_icon` | icon tint (telekasten accents) |
| `tkbr` | `#1d2433` | no | `telekasten_bracket` | bracket separators |

### 2.2 Greys and foregrounds

| key | hex | derived? | alias | role comment (verbatim) |
|---|---|---|---|---|
| `norm` | `#6c7e96` | no | `fg_default`, `default_color` | default foreground |
| `whit` | `#d1e5ff` | no | `fg_white`, `white_color` | white color |
| `comm` | `#363f4b` | **yes** — `U.darken(colors.norm, 50)` | `fg_comment`, `comment_color` | comment color; the file says `comm='#3c4754'` then overwrites it: `colors.comm = U.darken(colors.norm, 50)` |
| `high` | `#a5c1e6` | no | `fg_highlight`, `highlight_color` | highlight color |
| `darkhigh` | `#7387a1` | no | `fg_highlight_dark`, `highlight_dark_color` | darker highlight color |
| `drk2` | `#223f73` | no | `fg_dark_secondary`, `dark_secondary_color` | dark 2 color |
| `pmen` | `#6c7e96` | no | `fg_pmenu`, `pmenu_color` | pmenu text (theme grey) |
| `iden` | `#6289b3` | no | `fg_identifier`, `identifier_color` | identifier color |
| `dbng` | `#506a7d` | no | `fg_preproc_dark`, `preproc_dark_color` | dark preprocessor color |
| `lbgn` | `#7095b0` | no | `fg_preproc_light`, `preproc_light_color` | light preprocessor color |

Note: `comm` has **28.0 % HSV saturation, hue 214.3°** — it is exactly the same hue as
`norm`, only darker (L 50.6 % → 25.3 % HSL). All three "neutral" greys (`norm`, `comm`,
`pmen`) share hue 214°.

### 2.3 Syntax hues

| key | hex | derived? | alias | role comment (verbatim) |
|---|---|---|---|---|
| `lit1` | `#127978` | no | `fg_literal_1`, `literal1_color` | literal color 1 |
| `lit2` | `#148787` | no | `fg_literal_2`, `literal2_color` | literal color 2 |
| `lit3` | `#127a57` | no | `fg_literal_3`, `literal3_color` | literal color 3 |
| `ops1` | `#367cb0` | no | `fg_keyword_1`, `keyword1_color` | operations color 1 |
| `ops2` | `#2b7694` | no | `fg_keyword_2`, `keyword2_color` | operations color 2 |
| `ops3` | `#005faf` | no | `fg_keyword_3`, `keyword3_color` | operations color 3 |
| `ops4` | `#395573` | no | `fg_keyword_4`, `keyword4_color` | operations color 4 |
| `otag` | `#357b63` | no | `fg_tag`, `tag_color` | tag highlight color |
| `lstr` | `#6e879f` | no | `fg_string`, `string_color` | literal string highlight ("cool, subdued steel-blue tuned for readability on dark bg") |
| `incl` | `#005f87` | no | `fg_include`, `include_color` | include color |
| `dlim` | `#4779b3` | no | `fg_delimiter`, `delimiter_color` | delimiter color |
| `blod` | `#5f0000` | no | `fg_red_blood`, `red_blood_color` | bloody red |
| `violet` | `#3D005D` | no | `fg_violet`, `violet_color` | violet |
| `var` | `#7387a1` | no | `fg_variable`, `variable_color` | (comment reads "function highlight" — copy/paste artefact in the source) |
| `func` | `#7095b0` | no | `fg_function`, `function_color` | function highlight |
| `cmpdef` | `#0c2430` | no | `fg_cmp_default`, `cmp_default_color` | cmp item |

Hue census (HSV): the whole text palette lives in a narrow blue/teal band —
`norm` 214°, `func` 205°, `ops1` 206°, `ops2` 197°, `ops3` 207°, `iden` 211°, `dlim` 212°,
`lstr` 209°, `incl` 198°, `lit1/lit2` 179/180°, `lit3` 160°, `otag` 159°. Off-band members:
`dred` 342°, `blod` 0°, `violet` 279° (used only as the terminal "magenta" and the `Error` fg).

### 2.4 Diff and diagnostic

| key | hex | derived? | alias | role comment (verbatim) |
|---|---|---|---|---|
| `dadd` | `#007a66` | no | `fg_diff_add`, `diff_add_color` | diff add (luminous spruce, balanced brightness) |
| `dchg` | `#1d4aaf` | no | `fg_diff_change`, `diff_change_color` | diff change (bright indigo) |
| `dred` | `#6b0f2a` | no | `fg_diff_delete`, `diff_delete_color` | diff delete (dark burgundy) |
| `dwarn` | `#c8a8ef` | no | `fg_warning`, `warning_color` | warning (cyberpunk lilac) |
| `csel` | `#005faf` | no | `fg_search`, `search_color` | search highlight color |

### 2.5 Neutral ramp `col1` … `col24`

Straight ramp from near-black to near-white with a slight blue bias in the middle; exported
as `shade_01` … `shade_24`. No comment in the source other than the key names.

| key | hex | key | hex | key | hex |
|---|---|---|---|---|---|
| `col1` | `#000408` | `col9` | `#233b58` | `col17` | `#7c90a8` |
| `col2` | `#010912` | `col10` | `#2b4462` | `col18` | `#8d9eb2` |
| `col3` | `#040f1c` | `col11` | `#344d6c` | `col19` | `#95a7bc` |
| `col4` | `#071526` | `col12` | `#3f5876` | `col20` | `#a4b3c6` |
| `col5` | `#0c1c30` | `col13` | `#496280` | `col21` | `#b7c2d0` |
| `col6` | `#10233a` | `col14` | `#546c8a` | `col22` | `#bfc8d0` |
| `col7` | `#162b44` | `col15` | `#607794` | `col23` | `#dbdfe4` |
| `col8` | `#1c334e` | `col16` | `#6d839e` | `col24` | `#EEEEEE` |

Observed usage (grep over `lua/neg/groups/**`): only `shade_07`, `shade_10`, `shade_11` are
referenced — indent guides (`IblIndent`, `IndentBlanklineChar`, `TroubleIndent`,
`NvimTreeIndentMarker` = `shade_07`), active scope (`IblScope`, `IndentBlanklineContextChar`,
`MiniIndentscopeSymbol` = `shade_10`), scope start underline (`IndentBlanklineContextStart`
= `shade_11`). `shade_12` … `shade_24` are currently unused.

### 2.6 Rainbow `br1` … `br7`

Exported as `rainbow_1` … `rainbow_7` and consumed only by `plugins/rainbow.lua`
(`RainbowDelimiterRed` … `RainbowDelimiterCyan`).

| key | hex | key | hex |
|---|---|---|---|
| `br1` | `#4064be` | `br5` | `#475c94` |
| `br2` | `#4361b0` | `br6` | `#485a8c` |
| `br3` | `#455fa3` | `br7` | `#485885` |
| `br4` | `#465e9c` | | |

The seven "rainbow" levels are all the same blue, differing only in lightness — the
rainbow-delimiter integration is deliberately near-monochrome, not a real rainbow.

### 2.7 Misc / derived helper colors

| key | hex | derived? | formula / note |
|---|---|---|---|
| `bg_float` | `#141414` | **yes** | `U.lighten(colors.bclr, 8)` |
| `bg_panel` | `#0f0f0f` | **yes** | `U.lighten(colors.bclr, 6)` |
| `border_color` | `#000000` | **yes** | `U.darken(colors.bclr, 10)` → black stays black |
| `pmenu_bg` | `#000000` | alias | `colors.pmenu_bg = colors.bclr` |
| `pmenu_sel_bg` | `#272727` | alias | `colors.pmenu_sel_bg = colors.culc` |
| `pmenu_sel_fg` | `#d1e5ff` | alias | `colors.pmenu_sel_fg = colors.whit` |
| `pmenu_match` | `#a5c1e6` | alias | `colors.pmenu_match = colors.high` |
| `pmenu_kind` | `#7387a1` | alias | `colors.pmenu_kind = colors.darkhigh` |
| `pmenu_dim` | `#363f4b` | alias | `colors.pmenu_dim = colors.comm` |
| `pmenu_sbar` | `#121212` | alias | `colors.pmenu_sbar = colors.dark` |
| `pmenu_thumb` | `#506a7d` | alias | `colors.pmenu_thumb = colors.dbng` |
| `pmenu_border` | `#272727` | alias | `colors.pmenu_border = colors.culc` |
| `selection_bg` | `#0d1824` | no (literal in palette) | kitty-inspired selection bg, `ui.selection_model = 'kitty'` (default) |
| `selection_fg` | `#367bbf` | no (literal in palette) | kitty-inspired selection fg |
| `error_color` | `#6b0f2a` | alias | `= diff_delete_color` |
| `success_color` | `#007a66` | alias | `= diff_add_color` |
| `info_color` | `#7095b0` | alias | `= preproc_light_color` |
| `hint_color` | `#6289b3` | alias | `= identifier_color` |
| `accent_primary` | `#005f87` | alias | `= include_color` |
| `accent_secondary` | `#005faf` | alias | `= keyword3_color` |
| `accent_tertiary` | `#367cb0` | alias | `= keyword1_color` |
| `fg_literal_*`, … | — | alias block | every descriptive alias duplicates an existing hue; no new colors |

Hardcoded hexes **outside** the palette (important, because a port would otherwise miss them):

| hex | where | meaning in practice |
|---|---|---|
| `#2c3641` | `groups/editor.lua` `LineNr` | dim line-number grey (not on the `col1..col24` ramp) |
| `#123425` | `groups/editor.lua` `DiffAdd` bg | dark spruce wash |
| `#122c34` | `groups/editor.lua` `DiffChange` bg | dark indigo wash |
| `#111d26` | `which_key.lua`, `noice.lua`, `trouble.lua`, `nvim_tree.lua`, `neo_tree.lua` | de-facto "sidebar / popup surface" color used by 5 plugin modules (19 occurrences) |

---

## 3. Semantic mapping (resolved, default options)

Resolution rules applied:

1. `link=` chains are followed (`NormalFloat → Normal`, `FloatBorder → VertSplit`,
   `WinSeparator → VertSplit`, `NormalNC → Normal`, `Conceal → @operator`).
2. `M.setup()` post-processing order (from `init.lua`):
   accessibility → diagnostics virtual bg → alpha overlay → selection model → dim inactive →
   mode accent → focus caret → soft borders → auto transparent panels → float panel bg →
   diff focus → light signs → punct family → diag pattern → lexeme cues → thick cursor →
   outlines → reading mode → search visibility → screenreader → telescope accents → path
   separator → overrides. With the default config only the following passes are active:
   selection model (`kitty`), mode accent, focus caret (no-op, see below), auto transparent
   panels (no-op, background is not transparent), diff focus (only inside `:diff` windows),
   telescope accents (`true`).
3. `bg = NONE` means "whatever is behind" — in practice `#000000` (Normal).

### 3.1 Base editor / surfaces

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `Normal` | `#6c7e96` | `#000000` | — | `Normal={bg=p.bg_default, fg=p.default_color}` |
| `NormalNC` | `#6c7e96` | `#000000` | — | `NormalNC={link='Normal'}` (dim_inactive=false keeps the link) |
| `NormalFloat` | `#6c7e96` | `#000000` | — | `NormalFloat={link='Normal'}`; `hi(0,'NormalFloat',{link='Normal'})` when `float_panel_bg=false` |
| `FloatBorder` | `#121212` | `NONE` | — | `FloatBorder={link='VertSplit'}` + `VertSplit={bg='NONE', fg=p.dark_color}` |
| `FloatTitle` | `#005faf` | `NONE` | bold | `FloatTitle={fg=p.keyword3_color, bold=true}` |
| `WinSeparator` | `#121212` | `NONE` | — | `WinSeparator={link='VertSplit'}` |
| `VertSplit` | `#121212` | `NONE` | — | `VertSplit={bg='NONE', fg=p.dark_color}` |
| `CursorLine` | — | `#000000` | — | baseline `CursorLine={}`, then mode accent: normal-mode `U.darken(p.bg_default, 8)` = `#000000`; insert `alpha(include, bg, 0.14)` = `#000d13`; visual `alpha(tag, bg, 0.14)` = `#07110e` |
| `CursorColumn` | — | `#272727` | — | `CursorColumn={bg=p.bg_cursorcolumn}` |
| `ColorColumn` | — | `#272727` | — | `ColorColumn={bg=p.bg_cursorcolumn}` |
| `CursorLineNr` | `#005faf` | `#131e30` | italic, bold | `CursorLineNr={bg=p.bg_cursorline, fg=p.keyword3_color, italic=true, bold=true}` |
| `LineNr` | `#2c3641` | `NONE` | italic | `LineNr={fg='#2c3641', bg=nil, italic=true}` |
| `LineNrAbove` / `LineNrBelow` | `#2c3641` | `NONE` | italic | `{link='LineNr'}` (editor_extras) |
| `NegLineNrDim` | `#363f4b` | `NONE` | — | `NegLineNrDim={ fg=p.comment_color }` (used for inactive windows) |
| `SignColumn` | `NONE` | `NONE` | — | `SignColumn={bg='NONE', fg='NONE'}` |
| `FoldColumn` | `#363f4b` | `NONE` | — | `FoldColumn={bg='NONE', fg=p.comment_color}` |
| `Folded` | `#a5c1e6` | `#080808` | — | `Folded={bg=p.bg_visual, fg=p.highlight_color}` |
| `Whitespace` | `#363f4b` | `NONE` | — | `Whitespace={fg=p.comment_color}` |
| `EndOfBuffer` | `#000000` | `NONE` | — | `EndOfBuffer={fg=p.bg_default}` — deliberately invisible on black |
| `NonText` | `#2b7694` | `NONE` | — | `NonText={bg=nil, fg=p.keyword2_color}` |
| `Conceal` | `#2b7694` | `NONE` | — | `Conceal={link='@operator'}`, `['@operator']={ fg = p.keyword2_color }` |
| `Directory` | `#2b7694` | `NONE` | — | `Directory={bg=nil, fg=p.keyword2_color}` |
| `Question` | `#2b7694` | `NONE` | — | `Question={fg=p.keyword2_color}` |
| `Title` | `#127a57` | `NONE` | — | `Title={bg=nil, fg=p.literal3_color}` (only `preset='hard'` adds bold) |
| `Underlined` | `#395573` | `NONE` | — | `Underlined={bg=nil, fg=p.keyword4_color}` |
| `MatchParen` | `#121212` | `#a5c1e6` | — | `MatchParen={bg=p.highlight_color, fg=p.dark_color}` (inverted chip) |
| `Error` | `#3D005D` | `#000000` | — | `Error={bg=p.bg_default, fg=p.violet_color}` |
| `MsgArea` | `#6c7e96` | `NONE` | — | `MsgArea={fg=p.default_color}` |
| `MsgSeparator` | `#121212` | `NONE` | — | `MsgSeparator={fg=p.dark_color}` |
| `WinBar` | `#005faf` | `NONE` | — | `WinBar={fg=p.keyword3_color}` |
| `WinBarNC` | `#363f4b` | `NONE` | — | `WinBarNC={fg=p.comment_color}` |
| `FloatShadow` | — | `#000000` | blend 18 | `FloatShadow={bg=p.bg_default, blend=18}` |
| `FloatShadowThrough` | — | `#000000` | blend 24 | `FloatShadowThrough={bg=p.bg_default, blend=24}` |
| `Cursor`, `lCursor`, `CursorIM`, `TermCursor`, `TermCursorNC` | — | — | **reverse** | `Cursor={reverse=true}` etc. — cursor is an inversion of the cell, not a color |

### 3.2 Cursor / selection / search

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `Visual` (default, `selection_model='kitty'`) | `#367bbf` | `#0d1824` | — (bold forced off) | `hi(0,'Visual',{ bg=p.selection_bg, fg=p.selection_fg, bold=false, underline=false })` |
| `Visual` (`selection_model='default'`) | `NONE` | `#15181f` | bold | `Visual={bg=p.bg_selection_dim, fg='NONE', bold=true}` |
| `VisualNOS` (kitty) | `#367bbf` | `#0d1824` | — | `hi(0,'VisualNOS',{ bg=p.selection_bg, fg=p.selection_fg })` |
| `VisualNOS` (default model) | `NONE` | `#15181f` | — | `VisualNOS={bg=p.bg_selection_dim, fg='NONE'}` |
| `Search` | `#005faf` | `NONE` | italic | `Search={bg='NONE', fg=p.search_color, italic=true}` (`alpha_overlay=0` default ⇒ no fill) |
| `IncSearch` | `#005faf` | `#121212` | italic, underline | `IncSearch={bg=p.dark_color, fg=p.search_color, italic=true,underline=true}` |
| `CurSearch` | `#005faf` | `#121212` | italic, bold | `CurSearch={bg=p.dark_color, fg=p.search_color, italic=true, bold=true}` |
| `Substitute` | `#121212` | `#005faf` | bold | `Substitute={bg=p.search_color, fg=p.dark_color, bold=true}` |
| `WildMenu` | `#005f87` | `#121212` | — | `WildMenu={bg=p.dark_color, fg=p.include_color}` |
| `LspReferenceText/Read/Write` | — | `#080808` | — | `LspReferenceText={bg=p.bg_visual}` (same for Read/Write) |

### 3.3 Pmenu family (the canonical "list UI" model of this theme)

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `Pmenu` | `#6c7e96` | `#000000` | — | `Pmenu={bg=p.pmenu_bg, fg=p.pmenu_color}` |
| `PmenuSel` | `#d1e5ff` | `#272727` | bold | `PmenuSel={bg=p.pmenu_sel_bg, fg=p.pmenu_sel_fg, bold=true}` |
| `PmenuMatch` | `#a5c1e6` | `#000000` (inherits Pmenu) | underline | `PmenuMatch={fg=p.pmenu_match, underline=true}` |
| `PmenuMatchSel` | `#d1e5ff` | `#272727` (inherits PmenuSel) | underline, bold | `PmenuMatchSel={fg=p.pmenu_sel_fg, underline=true, bold=true}` |
| `PmenuKind` | `#7387a1` | `NONE` | — | `PmenuKind={fg=p.pmenu_kind, bg='NONE'}` |
| `PmenuKindSel` | `#d1e5ff` | `#272727` | bold | `PmenuKindSel={fg=p.pmenu_sel_fg, bg=p.pmenu_sel_bg, bold=true}` |
| `PmenuExtra` | `#363f4b` | `NONE` | — | `PmenuExtra={fg=p.pmenu_dim, bg='NONE'}` |
| `PmenuExtraSel` | `#d1e5ff` | `#272727` | — | `PmenuExtraSel={fg=p.pmenu_sel_fg, bg=p.pmenu_sel_bg}` |
| `PmenuSbar` | `NONE` | `#121212` | — | `PmenuSbar={bg=p.pmenu_sbar, fg='NONE'}` |
| `PmenuThumb` | `NONE` | `#506a7d` | — | `PmenuThumb={bg=p.pmenu_thumb, fg='NONE'}` |

### 3.4 Status line, tab line

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `StatusLine` | `#7095b0` (normal mode) | `NONE` | — | `StatusLine={bg='NONE', fg=p.function_color}`; mode accent swaps fg: insert `#005f87`, visual `#357b63` |
| `StatusLineNC` | `NONE` | `NONE` | — | `StatusLineNC={bg='NONE', fg='NONE'}` |
| `TabLine` | `#223f73` | `#000000` | — | `TabLine={bg=p.bg_default, fg=p.dark_secondary_color}` |
| `TabLineFill` | `#2b7694` | `#000000` | — | `TabLineFill={bg=p.bg_default, fg=p.keyword2_color}` |
| `TabLineSel` | `#223f73` | `#080808` | — | `TabLineSel={bg=p.bg_visual, fg=p.dark_secondary_color}` |

### 3.5 Messages

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `ErrorMsg` | `#6c7e96` | `NONE` | — | `ErrorMsg= {bg='NONE', fg=p.default_color}` — **not red** |
| `WarningMsg` | `#6c7e96` | `NONE` | — | `WarningMsg={bg='NONE', fg=p.default_color}` — **not yellow** |
| `MoreMsg` | `#005faf` | `NONE` | — | `MoreMsg={bg='NONE', fg=p.keyword3_color}` |
| `ModeMsg` | `#005faf` | `NONE` | — | `ModeMsg={bg='NONE', fg=p.keyword3_color}` |
| `QuickFixLine` | `#6c7e96` | `#131e30` | bold | `QuickFixLine={bg=p.bg_cursorline, fg=p.default_color, bold=true}` |

### 3.6 Spelling

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `SpellBad` | — | — | underline | `SpellBad={underline=true}` |
| `SpellCap` | — | — | underline | `SpellCap={underline=true}` |
| `SpellLocal` | — | — | underline | `SpellLocal={underline=true}` |
| `SpellRare` | — | — | underline | `SpellRare={underline=true}` |

No `sp` color is set for spelling groups: the theme encodes "spelling = underline only".

### 3.7 Diff

| group | fg | bg | attrs | source |
|---|---|---|---|---|
| `DiffAdd` | `#007a66` | `#123425` (literal) | — | `DiffAdd={bg='#123425', fg=p.diff_add_color}` |
| `DiffChange` | `#1d4aaf` | `#122c34` (literal) | — | `DiffChange={bg='#122c34', fg=p.diff_change_color}` |
| `DiffDelete` | `#6b0f2a` | `#5f0000` | — | `DiffDelete={bg=p.red_blood_color, fg=p.diff_delete_color}` |
| `DiffText` | `#d1e5ff` | `NONE` | — | `DiffText={bg='NONE', fg=p.white_color}` |
| `DiffAdd`/`Change`/`Delete`/`Text` inside `:diff` (`ui.diff_focus=true`) | `NONE` | add `#001b16`, change `#061027`, delete `#150308`, text `#001822` | text also bold | `U.alpha(color, p.bg_default, 0.22/0.22/0.20/0.25)`, fg explicitly `NONE` |

### 3.8 Diagnostics

All five severities map to exactly one palette hue, reused for base, virtual text, sign,
floating and (as `sp` under a curl) underline variants.

| severity | hex | base | virtual text | sign | floating | underline |
|---|---|---|---|---|---|---|
| Error | `#6b0f2a` (dred) | `DiagnosticError` | `DiagnosticVirtualTextError` | `DiagnosticSignError` | `DiagnosticFloatingError` | `DiagnosticUnderlineError` (undercurl, `sp`) |
| Warn | `#c8a8ef` (dwarn) | `DiagnosticWarn` | `DiagnosticVirtualTextWarn` | `DiagnosticSignWarn` | `DiagnosticFloatingWarn` | `DiagnosticUnderlineWarn` (undercurl, `sp`) |
| Info | `#7095b0` (lbgn) | `DiagnosticInfo` | `DiagnosticVirtualTextInfo` | `DiagnosticSignInfo` | `DiagnosticFloatingInfo` | `DiagnosticUnderlineInfo` (undercurl, `sp`) |
| Hint | `#6289b3` (iden) | `DiagnosticHint` | `DiagnosticVirtualTextHint` | `DiagnosticSignHint` | `DiagnosticFloatingHint` | `DiagnosticUnderlineHint` (undercurl, `sp`) |
| Ok | `#007a66` (dadd) | `DiagnosticOk` | `DiagnosticVirtualTextOk` | `DiagnosticSignOk` | `DiagnosticFloatingOk` | `DiagnosticUnderlineOk` (undercurl, `sp`) |

Additional: `DiagnosticDeprecated={strikethrough=true, fg=p.comment_color}` → `#363f4b`,
strikethrough. `LspInlayHint` and `LspCodeLens` → `#363f4b`, italic.
No `bg` is set on any diagnostic group by default (`diagnostics_virtual_bg = false`).

### 3.9 Syntax (reference; the app has no syntax highlighting)

| capture / legacy group | fg | attrs |
|---|---|---|
| `@comment`, `Comment` | `#363f4b` | italic |
| `@keyword` | `#2b7694` (ops2) | — |
| `@keyword.function` | `#367cb0` (ops1) | — |
| `@type`, `Type`, `Keyword` | `#2b7694` | — |
| `@type.builtin` | `#005faf` (ops3) | — |
| `@function`, `Function` | `#7095b0` (func) | — |
| `@constant`, `Constant` | `#148787` (lit2) | — |
| `@string`, `String`, `Character` | `#6e879f` (lstr) | — |
| `@number`, `Number` | `#367cb0` (ops1); `ramp` mode: integer `#367cb0`, hex `#4284b5`, octal `#3375a5`, binary `#3c80b2` | — |
| `@float`, `Float`, `Boolean` | `#127a57` (lit3) | — |
| `@operator`, `Operator` | `#2b7694` | — |
| `@punctuation.bracket/.delimiter/.special`, `Delimiter`, `Special` | `#4779b3` (dlim) | — |
| `@variable`, `@field`, `@property`, `@parameter`, `@namespace`, `Identifier` | `#6289b3` (iden); `@variable` uses `#7387a1` (var) | — |
| `@tag` | `#357b63` (otag) | — |
| `@include`, `Include`, `@markup.link.url` | `#005f87` (incl) | links underlined |
| `@preproc`, `PreProc` | `#7095b0` (lbgn) | — |
| `@define` | `#506a7d` (dbng) | — |
| `@exception` | `#5f0000` (blod) | — |
| `@markup.heading`, `.strong` | inherits | bold |
| `@markup.italic` | inherits | italic |
| `@markup.quote`, `@markup.list` | `#363f4b` | italic (`quote`) |
| `@comment.todo` | `#7095b0` | — |
| `@comment.warning` | `#c8a8ef` | — |
| `@comment.error` | `#6b0f2a` | — |
| `@comment.note` | `#6289b3` | — |
| `@diff.plus/.minus/.delta` | `#007a66` / `#6b0f2a` / `#1d4aaf` | — |

### 3.10 Plugin UI conventions (the reusable "list / panel / picker" vocabulary)

| plugin surface | resolved colors |
|---|---|
| Telescope normal/preview/prompt/results panes | `link = Normal` (fg `#6c7e96`, bg `#000000`) |
| Telescope borders (all four) | `link = WinSeparator` ⇒ fg `#121212` |
| Telescope titles | `link = WinBar` ⇒ fg `#005faf` |
| `TelescopeMatching` (`telescope_accents=true` → mode `default`) | fg `#005faf` (search hue), no underline |
| `TelescopeSelection` | bg = CursorLine bg (`#000000` under defaults) |
| `TelescopeSelectionCaret` | fg `#005f87` |
| `TelescopeResultsDiffAdd/Change/Delete` | `#007a66` / `#1d4aaf` / `#6b0f2a` |
| WhichKey | key `#005faf` bold; group `#127a57`; desc `#6c7e96`; separator `#363f4b`; float bg `#111d26`; border `link = FloatBorder` |
| Noice popup / cmdline popup / popupmenu | bg `#111d26`, fg `#6c7e96`, border `link = FloatBorder`; `NoiceCursor` bg `#005faf` |
| Trouble (sidebar) | bg `#111d26`, text `#6c7e96`, count `#005faf` bold, filename `#005f87`, fold icon / location `#363f4b`, indent `#162b44`, signs = diagnostic hues |
| nvim-tree / neo-tree | bg `#111d26`, dir icon/name `#2b7694`, root `#7095b0` bold, cursor line bg `#131e30`, indent marker `#162b44`, git added `#007a66`, modified `#005f87`, deleted `#5f0000` |
| snacks picker / input | `NormalFloat` / `FloatBorder` / `WinBar` links (no own colors) |
| cmp / blink kind icons | the syntax palette (function `#7095b0`, field/property `#6289b3`, class/interface `#2b7694`, keyword `#367cb0`, snippet `#6e879f`, folder `#005f87`, color/event `#3D005D`, …); the menu itself is `Pmenu` |

---

## 4. Design invariants

Each rule is quoted from the source that establishes it.

**1. The background is pure black and nothing else.**
`palette.lua`: `bclr='#000000', -- background color hexadecimal`; `editor.lua`:
`Normal={bg=p.bg_default, fg=p.default_color}`. There is no second "app background"
color — every other surface is either a near-black wash (`#080808`, `#0f0f0f`, `#121212`,
`#131e30`, `#272727`) or a plugin-local literal (`#111d26`).

**2. Foreground is a single desaturated blue-grey, and every neutral derives from it.**
`norm='#6c7e96', -- default foreground`; "neutral" companions are the same hue at different
lightness (`#a5c1e6`, `#7387a1`, `#6289b3`, `#506a7d` — all hue ≈ 205–214°).

**3. Comment / dim text is exactly `darken(foreground, 50%)`.**
```lua
-- Base comment color is derived from default to keep relative contrast stable
colors.comm = U.darken(colors.norm, 50)
```
→ `#363f4b`. The same value is reused as `pmenu_dim`, `WinBarNC`, `FoldColumn`,
`Whitespace`, `NegLineNrDim`, `DiagnosticDeprecated` fg, `LspInlayHint` fg, which is why the
theme has exactly one "dim" tone.

**4. Floats and panels are `lighten(background, N)`, never tinted.**
```lua
-- Neutral defaults derived from base background (avoid bluish tint)
colors.bg_float = U.lighten(colors.bclr, 8)   -- #141414
colors.bg_panel = U.lighten(colors.bclr, 6)   -- #0f0f0f
colors.border_color = U.darken(colors.bclr, 10)
```
and by default a float is *not* lifted at all: `NormalFloat={link='Normal'}` plus
`hi(0, 'NormalFloat', { link = 'Normal' })` ("Restore to inherit Normal (no extra tint)").
The `lighten(bg, 8)` float background only materialises when the terminal background is
transparent (`apply_auto_transparent_panels`) or when `ui.float_panel_bg` is switched on.

**5. Borders and separators are almost invisible by design.**
`VertSplit={bg='NONE', fg=p.dark_color}` (`#121212` on `#000000`, ratio 1.12:1),
`FloatBorder={link='VertSplit'}`, `WinSeparator={link='VertSplit'}`. `ui.soft_borders`
does not brighten them (`U.darken(p.bg_default, 10)` is still black; the float variant is
`U.darken(bg_float, 8)` = `#121212`).

**6. Pmenu is monochrome on a pure-black ground.**
```lua
-- Pmenu: monochrome, pure-black ground, neutral grey ramp
Pmenu={bg=p.pmenu_bg, fg=p.pmenu_color},
PmenuSel={bg=p.pmenu_sel_bg, fg=p.pmenu_sel_fg, bold=true},
PmenuSbar={bg=p.pmenu_sbar, fg='NONE'},
PmenuThumb={bg=p.pmenu_thumb, fg='NONE'},
```
`CHANGELOG.md` (4.72): "Pmenu: monochrome completion menu on a pure-black ground, assembled
from existing palette greys (pmen/culc/whit/high/comm) — no new colours." Selection is a
grey bar (`#272727`) with near-white text (`#d1e5ff`); matches are underlined and use the
highlight grey (`#a5c1e6`); the scrollbar is a two-step grey ramp (`#121212` track,
`#506a7d` thumb).

**7. The status line carries no background; state is expressed by text hue only.**
`StatusLine={bg='NONE', fg=p.function_color}` and
`StatusLineNC={bg='NONE', fg='NONE'}`. Mode awareness (on by default) changes only the
foreground: normal `#7095b0`, insert `#005f87`, visual `#357b63`.

**8. Errors and warnings are textual, not chromatic.**
`ErrorMsg= {bg='NONE', fg=p.default_color}` and `WarningMsg={bg='NONE', fg=p.default_color}`
— both are the plain foreground `#6c7e96`. Red/yellow are reserved for diagnostics, diffs
and terminal ANSI slots.

**9. Every semantic slot has exactly one hue, and hues are not shared across meanings.**
`#007a66` = added / ok / success; `#1d4aaf` = changed; `#6b0f2a` = deleted / error;
`#c8a8ef` = warning; `#7095b0` = info; `#6289b3` = hint; `#005faf` = search & matches.
Encoded by the aliases:
```lua
colors.error_color   = colors.diff_delete_color
colors.success_color = colors.diff_add_color
colors.info_color    = colors.preproc_light_color
colors.hint_color    = colors.identifier_color
```

**10. Selection is a near-black panel, not a hue wash.**
`bg_selection_dim = colors.dnorm` (`#15181f`) for the theme model; the default kitty model is
`Visual` on `#0d1824` with text `#367bbf` (`selection_bg`, `selection_fg`). Both stay inside
the blue-grey band; neither introduces a new hue.

**11. Nothing in the UI is bright; the brightest chromatic values belong to semantics little
used as body text.** `#d1e5ff` (near-white, V=100 %) and `#a5c1e6` are highlight/match
colors; the highest-value semantic hue is `#c8a8ef` (warning, V=93.7 %). Body text tops out
at V=58.8 % (`#6c7e96`).

**12. The `col1..col24` ramp is the structural grey scale, used through three stops only.**
Only `shade_07` `#162b44`, `shade_10` `#2b4462`, `shade_11` `#344d6c` are referenced —
indent guides, active scope, scope-start underline. The rest of the ramp is defined but
unused.

**13. `br1..br7` is a monochrome "rainbow".**
```lua
RainbowDelimiterRed={fg=p.rainbow_1}, ... RainbowDelimiterCyan={fg=p.rainbow_7},
```
all seven values are the same blue (`#4064be` → `#485885`), i.e. rainbow brackets are
expressed as a lightness ramp, not as hues.

**14. Contrast is tuned, not maximised; the theme has an explicit AA heuristic.**
```lua
local ratio = contrast(fg, bg) or 7.0
if ratio >= 4.5 then return end
...
if ratio < 3.0 then delta = 16 else delta = 12 end
```
(`ui.focus_caret`, default on) — if the base pairing is below AA, the cursor line is darkened
by 12–16 %. With the stock palette the ratio is 5.06:1, so this pass never fires: the theme
targets AA for body text and does **not** chase AAA anywhere. `validate.lua` encodes the same
policy: "Simple contrast sanity: if both fg and bg present and equal → warn", plus an opt-in
gate `NEG_VALIDATE_CONTRAST=1 NEG_VALIDATE_CONTRAST_MIN=3.0` (README §Validation).

**15. All accents are optional and off by default; the stock look is the muted one.**
`ui.soft_borders=false`, `ui.float_panel_bg=false`, `ui.light_signs=false`,
`ui.path_separator_blue=false`, `ui.outlines=false`, `ui.reading_mode=false`,
`diagnostics_virtual_bg=false`, `alpha_overlay=0`, `styles.* = 'none'` except
`comments='italic'`.

**16. Terminal ANSI slots are the theme's own meaning table (and reuse the same hues).**
```lua
p.bg_default,          -- 0: black    #000000
p.diff_delete_color,   -- 1: red      #6b0f2a
p.diff_add_color,      -- 2: green    #007a66
p.warning_color,       -- 3: yellow   #c8a8ef
p.include_color,       -- 4: blue     #005f87
p.violet_color,        -- 5: magenta  #3D005D
p.literal2_color,      -- 6: cyan     #148787
p.white_color,         -- 7: white    #d1e5ff
```
Slots 8–15 duplicate 0–7 (`vim.g['terminal_color_'..(i+8)] = colors[i+1]`).

---

## 5. Contrast data (WCAG 2.1)

Formula: `(L1 + 0.05) / (L2 + 0.05)` with `L = 0.2126 R + 0.7152 G + 0.0722 B`, sRGB
linearised exactly as in `validate.lua` (`c <= 0.03928 ? c/12.92 : ((c+0.055)/1.055)^2.4`).
Verdicts: AA normal text ≥ 4.5, AAA normal ≥ 7.0, AA large text (≥ 18.66 px bold / 24 px)
≥ 3.0, AAA large ≥ 4.5.

### 5.1 Core pairs

| pair | fg | bg | ratio | AA norm | AAA norm | AA large | AAA large |
|---|---|---|---|---|---|---|---|
| Normal text on background | `#6c7e96` | `#000000` | **5.06:1** | PASS | fail | PASS | PASS |
| Comment on background | `#363f4b` | `#000000` | 1.97:1 | fail | fail | fail | fail |
| LineNr on background | `#2c3641` | `#000000` | 1.71:1 | fail | fail | fail | fail |
| FoldColumn / Whitespace (`comm`) | `#363f4b` | `#000000` | 1.97:1 | fail | fail | fail | fail |
| NonText / Directory (`ops2`) | `#2b7694` | `#000000` | 4.12:1 | fail | fail | PASS | fail |
| Title (`lit3`) | `#127a57` | `#000000` | 3.95:1 | fail | fail | PASS | fail |
| StatusLine fg (`func`) | `#7095b0` | `#000000` | 6.61:1 | PASS | fail | PASS | PASS |
| WinSeparator / FloatBorder (`dark`) | `#121212` | `#000000` | 1.12:1 | fail | fail | fail | fail |
| MoreMsg / WinBar / ModeMsg (`ops3`) | `#005faf` | `#000000` | 3.26:1 | fail | fail | PASS | fail |
| ErrorMsg / WarningMsg (`norm`) | `#6c7e96` | `#000000` | 5.06:1 | PASS | fail | PASS | PASS |

### 5.2 Pmenu family

| pair | fg | bg | ratio | AA norm | AAA norm | AA large | AAA large |
|---|---|---|---|---|---|---|---|
| Pmenu text | `#6c7e96` | `#000000` | 5.06:1 | PASS | fail | PASS | PASS |
| PmenuSel text on selection bar | `#d1e5ff` | `#272727` | **11.64:1** | PASS | PASS | PASS | PASS |
| PmenuMatch on menu | `#a5c1e6` | `#000000` | 11.37:1 | PASS | PASS | PASS | PASS |
| PmenuMatchSel on bar | `#d1e5ff` | `#272727` | 11.64:1 | PASS | PASS | PASS | PASS |
| PmenuKind | `#7387a1` | `#000000` | 5.71:1 | PASS | fail | PASS | PASS |
| PmenuExtra (`comm`, "dim") | `#363f4b` | `#000000` | 1.97:1 | fail | fail | fail | fail |
| PmenuThumb on PmenuSbar | `#506a7d` | `#121212` | 3.30:1 | fail | fail | PASS | fail |
| PmenuThumb on background | `#506a7d` | `#000000` | 3.70:1 | fail | fail | PASS | fail |
| PmenuSbar track on background | `#121212` | `#000000` | 1.12:1 | fail | fail | fail | fail |

### 5.3 Selection / search

| pair | fg | bg | ratio | AA norm | AAA norm | AA large | AAA large |
|---|---|---|---|---|---|---|---|
| Visual, kitty model | `#367bbf` | `#0d1824` | 4.04:1 | fail | fail | PASS | fail |
| Visual, theme model (Normal fg over `dnorm`) | `#6c7e96` | `#15181f` | 4.28:1 | fail | fail | PASS | fail |
| Search text (`bg=NONE`) | `#005faf` | `#000000` | 3.26:1 | fail | fail | PASS | fail |
| CurSearch | `#005faf` | `#121212` | 2.90:1 | fail | fail | fail | fail |
| IncSearch | `#005faf` | `#121212` | 2.90:1 | fail | fail | fail | fail |
| Substitute (inverted) | `#121212` | `#005faf` | 3.26:1 | fail | fail | PASS | fail |
| WildMenu | `#005f87` | `#121212` | 2.66:1 | fail | fail | fail | fail |
| CursorLineNr | `#005faf` | `#131e30` | 2.59:1 | fail | fail | fail | fail |
| QuickFixLine | `#6c7e96` | `#131e30` | 4.03:1 | fail | fail | PASS | fail |
| Folded | `#a5c1e6` | `#080808` | 10.84:1 | PASS | PASS | PASS | PASS |
| MatchParen (inverted chip) | `#121212` | `#a5c1e6` | 10.14:1 | PASS | PASS | PASS | PASS |
| TabLine | `#223f73` | `#000000` | 2.03:1 | fail | fail | fail | fail |
| TabLineSel | `#223f73` | `#080808` | 1.93:1 | fail | fail | fail | fail |

### 5.4 Syntax hues on the background (`#000000`)

| hue | key | ratio | AA norm | AAA norm | AA large | AAA large |
|---|---|---|---|---|---|---|
| `#367cb0` | ops1 / numbers | **4.67:1** | PASS | fail | PASS | PASS |
| `#2b7694` | ops2 / keyword | 4.12:1 | fail | fail | PASS | fail |
| `#005faf` | ops3 / type.builtin | 3.26:1 | fail | fail | PASS | fail |
| `#395573` | ops4 / assignment | 2.72:1 | fail | fail | fail | fail |
| `#127978` | lit1 | 4.03:1 | fail | fail | PASS | fail |
| `#148787` | lit2 / constant | 4.85:1 | PASS | fail | PASS | PASS |
| `#127a57` | lit3 / bool, title | 3.95:1 | fail | fail | PASS | fail |
| `#357b63` | otag | 4.16:1 | fail | fail | PASS | fail |
| `#6e879f` | lstr / string | **5.63:1** | PASS | fail | PASS | PASS |
| `#005f87` | incl / include | 2.99:1 | fail | fail | fail | fail |
| `#4779b3` | dlim / punctuation | 4.65:1 | PASS | fail | PASS | PASS |
| `#5f0000` | blod / exception | 1.49:1 | fail | fail | fail | fail |
| `#3D005D` | violet / Error | 1.36:1 | fail | fail | fail | fail |
| `#a5c1e6` | high / match | 11.37:1 | PASS | PASS | PASS | PASS |
| `#7387a1` | darkhigh / var | 5.71:1 | PASS | fail | PASS | PASS |
| `#7095b0` | func | 6.61:1 | PASS | fail | PASS | PASS |
| `#6289b3` | iden | 5.75:1 | PASS | fail | PASS | PASS |
| `#506a7d` | dbng | 3.70:1 | fail | fail | PASS | fail |
| `#d1e5ff` | whit | 16.36:1 | PASS | PASS | PASS | PASS |

### 5.5 Diagnostic / diff hues on the background

| hue | key | ratio | AA norm | AAA norm | AA large | AAA large |
|---|---|---|---|---|---|---|
| `#6b0f2a` | error / diff delete | 1.73:1 | fail | fail | fail | fail |
| `#c8a8ef` | warning | **10.30:1** | PASS | PASS | PASS | PASS |
| `#7095b0` | info | 6.61:1 | PASS | fail | PASS | PASS |
| `#6289b3` | hint | 5.75:1 | PASS | fail | PASS | PASS |
| `#007a66` | ok / diff add | 3.98:1 | fail | fail | PASS | fail |

Diff foreground-over-wash pairs (the values the theme actually ships):

| pair | fg | bg | ratio | verdict |
|---|---|---|---|---|
| DiffAdd | `#007a66` | `#123425` | 2.58:1 | fails AA normal and AA large |
| DiffChange | `#1d4aaf` | `#122c34` | 1.85:1 | fails every level |
| DiffDelete | `#6b0f2a` | `#5f0000` | 1.16:1 | fails every level |
| DiffText | `#d1e5ff` | `#000000` | 16.36:1 | passes AAA |

### 5.6 What the numbers say

- The only comfortably readable, on-palette body-text colors are `#6c7e96` (5.06:1),
  `#7095b0`, `#6289b3`, `#7387a1`, `#6e879f`, `#d1e5ff`, `#a5c1e6`, `#c8a8ef`.
- Chrome and annotations (comments, line numbers, borders, tab labels, thumb tracks,
  `PmenuExtra`) are **intentionally below every WCAG threshold** — the theme encodes a
  "recede into black" policy, not a WCAG-passing one.
- The red family (`#6b0f2a`, `#5f0000`, `#3D005D`) is the lowest-contrast set in the palette;
  red is used as *tint on dark surfaces* (diff/diagnostic), never as a text accent.
- No pairing in the stock theme reaches AAA for normal-size text.

---

## 6. What a native app must imitate vs must not

### 6.1 App-relevant vocabulary (the subset that carries meaning outside code)

| semantic role | color | where the theme uses it | app usage |
|---|---|---|---|
| Canvas / background | `#000000` | `Normal` bg, `Pmenu` bg, `PmenuSbar`… | window background, everywhere |
| Surface raised 1 (popover, menu, list row) | `#121212` | `dark` — `IncSearch`/`CurSearch` bg, `PmenuSbar`, `WildMenu`, `MsgSeparator` | context menus, dropdowns, tooltips base |
| Surface raised 2 (selection bar, hover) | `#272727` | `culc` — `PmenuSel`, `ColorColumn`, `CursorColumn` | selected row, hovered row, focused control fill |
| Surface raised 3 (side panel) | `#111d26` | plugin-local literal used by 5 sidebar/popup modules | library/sidebar/queue panel, settings pane |
| Primary text | `#6c7e96` | `norm` — `Normal`, `Pmenu`, `PmenuExtra` base | track titles, labels, body |
| Dim / secondary text | `#363f4b` | `comm` — comments, `WinBarNC`, `PmenuExtra`, inactive labels | durations, secondary metadata, disabled captions |
| Tertiary text | `#7387a1` | `darkhigh` — `PmenuKind` | "kind" tags (album, artist), badges |
| Emphasis text / playing indicator | `#d1e5ff` | `whit` — `PmenuSel` text, `DiffText`, active item label | now-playing track title, current row label |
| Match / highlight emphasis | `#a5c1e6` | `high` — `PmenuMatch`, `Folded`, `MatchParen` bg | search-match highlight, current match, wave marker |
| Accent / active control | `#005faf` | `ops3`/`csel` — `MoreMsg`, `WinBar`, `CursorLineNr`, `Substitute` bg, `TelescopeMatching` | focus ring, active tab underline, progress bar, active transport button |
| Accent soft / caret | `#005f87` | `incl` — `WildMenu`, `TelescopeSelectionCaret`, `NoiceCursor` bg, links | caret, small active dot, link text |
| Secondary accent | `#367cb0` | `ops1` — numbers/keywords, `Visual` fg in kitty model | selected-text foreground, secondary graph color |
| Selection background | `#0d1824` | `selection_bg` — `Visual` (kitty model) | selected text in lists / text fields; also the "row selection under text" tone |
| Selection dim background | `#15181f` | `dnorm` — `Visual` (theme model), `VisualNOS` | alternative selection tone if `#0d1824` reads too blue |
| Success / added | `#007a66` | `dadd` — `DiffAdd`, `DiagnosticOk`, `success_color` | "added to library", sync ok, download complete |
| Progress / change | `#1d4aaf` | `dchg` — `DiffChange`, terminal ANSI blue-ish change slot | modified state, update available, buffering |
| Danger / deleted / error | `#6b0f2a` | `dred` — `DiffDelete`, `DiagnosticError`, `error_color` | destructive action, error icon, "remove" state |
| Danger deep (surface) | `#5f0000` | `blod` — `DiffDelete` bg, `@exception` | error banner background, not error text |
| Warning | `#c8a8ef` | `dwarn` — `DiagnosticWarn`, terminal ANSI yellow slot | non-fatal warning, "lossy format" badge |
| Info | `#7095b0` | `lbgn` — `DiagnosticInfo`, `StatusLine` fg, `MoreMsg` | informational toast, status text |
| Hint | `#6289b3` | `iden` — `DiagnosticHint` | subtle hints, keyboard-hint glyphs |
| Violet (rare) | `#3D005D` | `violet` — `Error` fg, terminal magenta | avoid; only if a fifth hue is unavoidable |
| Indent / divider guide | `#162b44` | `shade_07` | list separators, queue indentation rails |
| Divider (active) | `#2b4462` | `shade_10` | active divider, scope marker |

Concrete mapping for a music player:

- **Progress bar (elapsed)** → `#005faf`; track (remaining) → `#121212`; hover/scrub thumb →
  `#a5c1e6`; drag preview → `#272727`.
- **Playing indicator** → text `#d1e5ff`, icon accent `#a5c1e6`; paused → `#6c7e96`;
  buffering → `#1d4aaf`.
- **Focus ring / keyboard focus** → 1 px `#005faf` outline on `#000000`; do not use a glow.
- **Selection (list row)** → bg `#272727`, label `#d1e5ff`, bold (exactly `PmenuSel`).
- **Hover** → bg `#121212` (exactly `PmenuSbar` / `CurSearch` ground), no text change.
- **Matches inside a filtered list** → `#a5c1e6` + underline (exactly `PmenuMatch`).
- **Danger (delete playlist / remove track)** → icon/label `#6b0f2a`; if the label must be
  readable, put `#d1e5ff` text on a `#5f0000` fill (mirrors `DiffDelete` semantics).
- **Success (added, synced)** → `#007a66`.
- **Warning (unsupported codec, missing file)** → `#c8a8ef`.
- **Chrome that must recede** (dividers, panel borders, scrollbar tracks, timestamps,
  library counts) → `#121212` / `#363f4b` and nothing brighter.

### 6.2 Must imitate

1. Pure `#000000` background with no elevation gradient and no "card" shadows other than the
   theme's `blend` idea (a `#000000` overlay at 18–24 % behind floats).
2. One neutral foreground family; secondary text produced by darkening, never by desaturating
   a hue (`darken(fg, 50%)`).
3. Monochrome menus/lists: grey selection bar + near-white selected label + underlined match
   in a highlight grey. No colored rows.
4. Borders near-invisible: dividers at `#121212`-class contrast, i.e. "you see them only if you
   look".
5. Status/utility bars with no fill (`bg = NONE`) and hue-only state.
6. Error/warning *messages* rendered in plain foreground; chromatic red/yellow reserved for
   badges/icons/rows, not for prose.
7. One hue per meaning, reused across surfaces (the same `#6b0f2a` for error text, error icon
   and error underline).
8. Inverted chips for "current match" style emphasis (`MatchParen`: dark text on `#a5c1e6`).

### 6.3 Must not imitate

1. **Syntax hues** — `lit1` `#127978`, `lit2` `#148787`, `lit3` `#127a57`, `otag` `#357b63`,
   `incl` `#005f87`, `ops4` `#395573`, `dlim` `#4779b3`, `blod` `#5f0000`, `violet` `#3D005D`.
   They exist only to differentiate code tokens; in an app they would read as arbitrary
   decoration. (Exception: `#005f87` is `accent_primary` and is fine as a small caret/dot.)
2. **`br1..br7`** — a seven-step monochrome ramp for nested brackets; it has no app meaning and
   is intentionally not a rainbow. Do not build a "rainbow" palette from these.
3. **`col1..col24` as a general-purpose scale** — only three stops are actually used
   (`07/10/11`). Do not expose the whole ramp as a design-token ladder; most steps are unused.
4. **The theme's sub-AA chrome as body text.** `#363f4b`, `#2c3641`, `#2b4462`, `#121212`,
   `#223f73` are all ≤ 2.1:1 on black. Use them for rules, tracks and separators only; for
   text that must be read (durations, counts) prefer `#6c7e96` or `#7387a1`.
5. **The low-contrast red foregrounds as alert text.** `#6b0f2a` on `#000000` is 1.73:1 —
   the theme accepts that inside the gutter/virtual text, where the glyph is small and
   reinforced by an icon or undercurl. A native app should reproduce the *hue*, not the
   contrast, for any text a user must act on.
6. **Non-default modes from `ui.*`** — `reading_mode`, `screenreader_friendly`,
   `accessibility.*`, `preset='hard'|'presentation'|'focus'` change these values; the spec
   above describes stock `neg`, so do not mix fragments of presets in.
7. **Kitty/ANSI slot mapping colours as UI** (terminal 1–7 above all): those slots exist so
   the terminal matches the theme, not as an app palette.

---

## 7. Typography, spacing, motion

- The theme encodes **text attributes only**: `bold`, `italic`, `underline`, `undercurl`,
  `strikethrough`, `reverse`, `nocombine`, and `blend` (a 0–100 transparency percentage).
  There is no font family, font size, weight scale, line height, letter spacing, corner radius
  or padding value anywhere in the palette, group tables or options.
- Default style policy (`styles` in `default_config`):
  `comments = 'italic'`, everything else `'none'`. Presets can change that
  (`hard` → bold keywords/functions/types/constants/booleans/numbers and bold `Title`;
  `pro` → no italics; `writing` → bold headings; `accessibility` → no italic comments).
- Attributes actually shipped on by default:
  - italic: `Comment`/`@comment`, `LineNr`, `LineNrAbove/Below`, `CursorLineNr`,
    `Search`, `IncSearch`, `CurSearch`, `LspInlayHint`, `LspCodeLens`, `@markup.italic`,
    `@markup.quote`, `NoiceCmdLine`;
  - bold: `PmenuSel`, `PmenuKindSel`, `PmenuMatchSel`, `CursorLineNr`, `QuickFixLine`,
    `Substitute`, `CurSearch`, `FloatTitle`, `@markup.heading`, `@markup.strong`,
    plus plugin bold (`WhichKey`, `TroubleCount`, tree roots, `NvimTreeOpenedFolderName`);
  - underline: `PmenuMatch`, `PmenuMatchSel`, `IncSearch`, `Spell*`, `@markup.link*`,
    `@string.special.url`, indent scope start;
  - undercurl: all `DiagnosticUnderline*` (with `sp` = the severity hue);
  - strikethrough: `DiagnosticDeprecated`, `@markup.strikethrough`,
    `@lsp.typemod.deprecated`;
  - reverse: `Cursor`, `lCursor`, `CursorIM`, `TermCursor`, `TermCursorNC` — the cursor is
    "invert the cell", not a colored bar.
- Spacing implication that *is* derivable: the UI has no borders/dividers of visible weight
  (separators at 1.12:1), so panels must be separated by **surface lightness** (`#000000` →
  `#121212` → `#272727` → `#111d26`), not by lines. Selection and hover are the only two
  fill-levels below a panel.
- Nothing in the sources mentions animation, easing, durations or motion. The only time-based
  behaviour is Neovim's own cursor blink and `blend` compositing. Do not infer motion rules
  from this theme.

---

## 8. Explicitly not stated in the source (do not invent)

- No font, size, weight, radius, padding, margin or spacing tokens exist.
- No rule states *why* `#123425` and `#122c34` (diff washes) are literals outside the palette;
  they simply are literals in `groups/editor.lua`.
- `#2c3641` (LineNr) is not part of `col1..col24`; no comment explains its derivation.
- `#111d26` (sidebar/popup surface) is a repeated literal, never promoted to a palette key;
  the palette has no equivalent entry.
- `shade_12` … `shade_24` and `rainbow_1..7` beyond rainbow-delimiters have no documented
  purpose.
- The theme states no explicit contrast target beyond the `focus_caret` AA heuristic (§4 rule
  14) and the opt-in validator gate; there is no statement that every group must pass AA.
- No mapping is given for application-level concepts (playlists, equalizer, artwork); §6 is a
  projection of palette roles onto those concepts, not a source claim.
