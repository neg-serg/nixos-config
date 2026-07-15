# kvantum-qt-theme — Work Plan

## TL;DR (For humans)

**Что вы получите:** KvantumManager для интерактивного выбора тёмной Qt-темы + 8 предустановленных тёмных тем (3 встроенных: KvDark, KvArcDark, KvSimplicityDark; 5 Catppuccin Mocha: Blue, Mauve, Lavender, Sky, Green). Дефолтная тема — KvDark (чисто тёмная). После выбора темы через GUI — меняете одну переменную в `qt.nix` и пересобираете.

**Почему такой подход:** `kvantummanager` уже есть в системе (из `qtstyleplugin-kvantum`), но не видит тёмные темы — они не засимлинкованы в `~/.local/share/Kvantum/`. План добавляет недостающие симлинки и Catppuccin-пакеты. После интерактивного выбора — фиксация через переменную `kvantumTheme`.

**Что НЕ будет сделано:** Qt5-теминг (отказ), GTK-теминг, home-manager, стилизация панели/rofi/dunst (это отдельная тема).

**Объём:** 2 файла, 4 todo, ~80 строк изменений. Одна волна, один коммит.

**Риски:** Catppuccin-пакеты добавляют 5 override'ов → +5 оценок derivations при nixos-rebuild eval (~1-2 сек). Если accent-имена изменятся в nixpkgs, билд упадёт с понятной ошибкой `lib.checkListOfEnum`.

**Решения:** KvDark как дефолт (самый тёмный из встроенных); 5 Catppuccin-акцентов (достаточно для выбора, не перегружает); переменная `kvantumTheme` для лёгкой смены темы.

## Scope

**IN:**
- Interactive Kvantum theme browsing via `kvantummanager` (already on PATH from `qtstyleplugin-kvantum`)
- Declarative NixOS config to lock in chosen dark Kvantum theme for Qt6
- 3 built-in dark themes symlinked for browsing: `KvDark`, `KvArcDark`, `KvSimplicityDark`
- 5 Catppuccin Mocha accents symlinked for browsing: Blue, Mauve, Lavender, Sky, Green
- Default locked-in theme: `KvDark` (user changes after interactive selection)
- Maintain existing `QT_STYLE_OVERRIDE=kvantum` enforcement

**OUT:**
- Qt5 theming (explicitly declined)
- GTK theming
- Home-manager integration
- KDE Plasma desktop
- Full 56-theme Catppuccin matrix (not needed for interactive selection; user adds more if wanted)

## Verification strategy

**Agent-executed QA (tests-after)** — every todo has executable shell assertions:

| Check | Command | Expected |
|-------|---------|----------|
| kvantummanager binary | `which kvantummanager` | `/run/current-system/sw/bin/kvantummanager` |
| KvDark theme files | `test -f ~/.local/share/Kvantum/KvDark/KvDark.kvconfig` | exit 0 |
| KvArcDark theme files | `test -f ~/.local/share/Kvantum/KvArcDark/KvArcDark.kvconfig` | exit 0 |
| Catppuccin symlinks | `ls ~/.local/share/Kvantum/Catppuccin-Mocha-Blue/` | directory exists |
| kvantum.kvconfig | `grep 'theme=KvDark' ~/.config/Kvantum/kvantum.kvconfig` | match |
| qt6ct.conf style | `grep 'style=kvantum' ~/.config/qt6ct/qt6ct.conf` | match |
| QT_STYLE_OVERRIDE | `echo $QT_STYLE_OVERRIDE` | `kvantum` |
| No white fallback in qt6ct | `grep -v '^#' ~/.config/qt6ct/qt6ct.conf \| grep -i 'style'` | only `kvantum` |

## Execution strategy

Single wave — all changes in two files:
- `modules/user/theme-packages.nix` (package additions)
- `modules/user/nix-maid/gui/qt.nix` (theme symlinks + config)

## Todos

### Wave 1 — Theme infrastructure + interactive browsing

- [x] **Todo 1** — `modules/user/theme-packages.nix`: Add Catppuccin Mocha packages

**References:**
- Current file: `/etc/nixos/modules/user/theme-packages.nix` (18 lines)
- Package API: `pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "<Accent>"; }`
- Accents: Blue, Mauve, Lavender, Sky, Green per nixpkgs `pkgs/by-name/ca/catppuccin-kvantum/package.nix`

**Change:** Add 5 Catppuccin overrides to the `packages` list in `let` block:

```nix
# Catppuccin Kvantum — Mocha variant themes for interactive browsing
(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Blue"; })
(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Mauve"; })
(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Lavender"; })
(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Sky"; })
(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Green"; })
```

**Acceptance:** `nixos-rebuild dry-build` succeeds. Each override evaluates without error.

**QA (happy):**
```bash
# Verify each package installed to nix store
nix eval --raw .#nixosConfigurations.odin.config.environment.systemPackages | grep catppuccin-kvantum | wc -l
# Expected: 5
```

**QA (failure):** Wrong accent name → nix build fails with `lib.checkListOfEnum` error.

**Commit:** `[gui/qt] Add Catppuccin Mocha Kvantum themes for interactive browsing`

---

- [x] **Todo 2** — `modules/user/nix-maid/gui/qt.nix`: Add theme variable + built-in dark theme symlinks

**References:**
- Current file: `/etc/nixos/modules/user/nix-maid/gui/qt.nix` (57 lines)
- kvantumTheme variable: replaces hardcoded "KvantumAlt"
- Built-in themes source: `${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/`
- Available dark themes: KvDark, KvArcDark, KvSimplicityDark (verified via `ls` of package output)

**Change:** Add to `let` block:
```nix
kvantumTheme = "KvDark"; # Default dark theme — change after interactive selection via kvantummanager
```

**Change:** In `(n.mkHomeFiles { ... })` block — replace KvantumAlt symlinks with KvDark, KvArcDark, KvSimplicityDark:

Replace lines 50-53 with:
```nix
# Built-in dark Kvantum themes for interactive browsing via kvantummanager
".local/share/Kvantum/KvDark/KvDark.kvconfig".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvDark/KvDark.kvconfig";
".local/share/Kvantum/KvDark/KvDark.svg".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvDark/KvDark.svg";
".local/share/Kvantum/KvArcDark/KvArcDark.kvconfig".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvArcDark/KvArcDark.kvconfig";
".local/share/Kvantum/KvArcDark/KvArcDark.svg".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvArcDark/KvArcDark.svg";
".local/share/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig";
".local/share/Kvantum/KvSimplicityDark/KvSimplicityDark.svg".source =
  "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.svg";
```

**Acceptance:** 3 dark themes symlinked. User can browse them in kvantummanager.

**QA (happy):**
```bash
for theme in KvDark KvArcDark KvSimplicityDark; do
  test -f ~/.local/share/Kvantum/$theme/$theme.kvconfig && echo "$theme: OK"
done
# Expected: KvDark: OK, KvArcDark: OK, KvSimplicityDark: OK
```

**QA (failure):** Source path typo → nix eval fails with "Source file doesn't exist."

**Commit:** `[gui/qt] Replace KvantumAlt with dark built-in themes (KvDark, KvArcDark, KvSimplicityDark)`

---

- [x] **Todo 3** — `modules/user/nix-maid/gui/qt.nix`: Add Catppuccin Mocha theme symlinks

**References:**
- Package pattern: `${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Blue"; })}/share/Kvantum/Catppuccin-Mocha-Blue/`
- Theme directory content: `Catppuccin-Mocha-Blue.kvconfig` + `Catppuccin-Mocha-Blue.svg`
- Symlink target: `~/.local/share/Kvantum/Catppuccin-Mocha-<Accent>/`

**Change:** Add to `(n.mkHomeFiles { ... })` block after the built-in themes:

```nix
# Catppuccin Mocha themes for interactive browsing
".local/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Blue"; })}/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig";
".local/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Blue"; })}/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg";
".local/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Mauve"; })}/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig";
".local/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Mauve"; })}/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg";
".local/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Lavender"; })}/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig";
".local/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Lavender"; })}/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg";
".local/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Sky"; })}/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig";
".local/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Sky"; })}/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg";
".local/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Green"; })}/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig";
".local/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg".source =
  "${(pkgs.catppuccin-kvantum.override { variant = "Mocha"; accent = "Green"; })}/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg";
```

**Acceptance:** 5 Catppuccin Mocha themes symlinked. User sees them in kvantummanager.

**QA (happy):**
```bash
ls ~/.local/share/Kvantum/ | grep Catppuccin-Mocha | wc -l
# Expected: 5
```

**QA (failure):** Override parameters mismatch → nix eval fails.

**Commit:** `[gui/qt] Add Catppuccin Mocha Kvantum themes (Blue, Mauve, Lavender, Sky, Green)`

---

- [x] **Todo 4** — `modules/user/nix-maid/gui/qt.nix`: Update kvantum.kvconfig to use theme variable

**References:**
- Current line 35-38: hardcoded `theme=KvantumAlt`
- New variable: `kvantumTheme = "KvDark"` (from Todo 2)

**Change:** Line 37: Replace `theme=KvantumAlt` with `theme=${kvantumTheme}`

Also add a comment block before the mkHomeFiles call explaining the workflow:
```nix
# === Kvantum Theme Configuration ===
# Interactive selection workflow:
#   1. Rebuild with nixos-rebuild switch
#   2. Run: kvantummanager
#   3. Browse themes in the GUI (KvDark, KvArcDark, KvSimplicityDark, Catppuccin-Mocha-*)
#   4. Click a theme → "Use this theme" → "Apply"
#   5. To lock in declaratively: change `kvantumTheme` variable above and rebuild
#
# Default theme: KvDark (pure dark, no white elements)
```

**Acceptance:** `kvantum.kvconfig` references `${kvantumTheme}` variable. Changing the variable changes the active theme.

**QA (happy):**
```bash
grep 'theme=KvDark' ~/.config/Kvantum/kvantum.kvconfig
# Expected: theme=KvDark
```

**QA (failure):** Variable not resolved → literal `${kvantumTheme}` appears in config.

**Commit:** `[gui/qt] Parameterize Kvantum theme via kvantumTheme variable`

## Final verification wave

| Check | Method | Expected |
|-------|--------|----------|
| F1 — Plan compliance | Diff plan vs changed files | 4 todos matching, no extra files changed |
| F2 — Code quality | `statix check modules/user/nix-maid/gui/qt.nix modules/user/theme-packages.nix` | No statix errors |
| F3 — Interactive browsing | `kvantummanager` → GUI shows 8+ dark themes (3 built-in + 5 Catppuccin) | Themes visible and selectable |
| F4 — Scope fidelity | Grep for `qt5`, `gtk`, `home-manager` in diff | Zero new references |
| F5 — No white/default | `grep -r 'KvantumAlt' modules/user/nix-maid/gui/qt.nix` | No matches (fully removed) |

## Commit strategy

Single commit: `[gui/qt] Interactive Kvantum theme selection with Catppuccin + built-in dark themes`

## Success criteria

- `kvantummanager` shows 8+ dark themes: KvDark, KvArcDark, KvSimplicityDark, Catppuccin-Mocha-{Blue,Mauve,Lavender,Sky,Green}
- Default active theme: KvDark (pure dark)
- User changes `kvantumTheme` variable → `nixos-rebuild switch` → theme updates
- `QT_STYLE_OVERRIDE=kvantum` enforced globally (existing, maintained)
- Zero references to old `KvantumAlt` (light theme removed)
- No white/default Qt6 elements visible
