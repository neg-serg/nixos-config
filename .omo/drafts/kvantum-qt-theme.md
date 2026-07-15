# kvantum-qt-theme — Draft

## Meta
- **intent**: clear
- **review_required**: false
- **status**: delivered
- **slug**: kvantum-qt-theme

## Request
Выбрать интерактивно и поставить потом декларативно хорошую qt тему kvantum, от которой потом требуется чтобы она применялась везде точно и не было бы ничего белого или дефолтного нигде.

(Interactively select a good Kvantum Qt theme, then declaratively install it; must apply everywhere globally; no white/default elements anywhere.)

## Topology Lock

| # | Component | Outcome | Status |
|---|-----------|---------|--------|
| C1 | Kvantum theme selection (interactive browsing + choice) | User picks theme via `kvantummanager` | pending |
| C2 | Declarative NixOS config for the chosen theme | Theme symlinked + config files deployed | pending |
| C3 | Qt5 support | Enable/disable qt5ct + Qt5 Kvantum plugin | pending |
| C4 | Global enforcement (no white/default fallback) | Force-dark palette, ensure no app falls back to default Qt style | pending |

## Metis Gaps (addressed)

| Gap | Resolution |
|-----|------------|
| G1 (BLOCKER): Catppuccin ships 1 theme | Use 5 separate overrides for Mocha+accents |
| G2 (BLOCKER): "KvantumDark" doesn't exist | Correct names: KvDark, KvArcDark, KvSimplicityDark |
| G3: Missing interactive browsing criteria | Added: kvantummanager launches, themes visible, apply works |
| G4: Missing executable QA | Added shell assertions with exact paths |
| G5: No theme variant selection policy | Default: KvDark; all available themes listed |
| G6: QT_STYLE_OVERRIDE scope creep | Clarified: maintained (existing), not new work |

## Key Findings

### Current setup (`/etc/nixos/modules/user/nix-maid/gui/qt.nix`)
- Uses `KvantumAlt` theme (light/grey variant of Kvantum default)
- Only Qt6: `qt6ct` + `kdePackages.qtstyleplugin-kvantum`
- Qt5 support commented out (`pkgs.qt5ct` line 22)
- Theme files symlinked from nix store to `~/.local/share/Kvantum/KvantumAlt/`
- `QT_STYLE_OVERRIDE=kvantum`, `QT_QPA_PLATFORMTHEME=qt6ct`

### Available Kvantum themes in nixpkgs (release-26.05)
1. **Built-in** (via `pkgs.kdePackages.qtstyleplugin-kvantum`):
   - Kvantum (default — light)
   - KvantumDark (dark)
   - KvantumAlt (lighter variant)
2. **Catppuccin** (`pkgs.catppuccin-kvantum`):
   - 4 variants: Latte (light), Frappe, Macchiato, Mocha (dark)
   - 14 accents: blue, flamingo, green, lavender, maroon, mauve, peach, pink, red, rosewater, sapphire, sky, teal, yellow

### Known workaround
Kvantum theme discovery from nix store is broken via XDG_DATA_DIRS. The fix (used in this repo + confirmed in NixOS Discourse): symlink theme directory to `~/.local/share/Kvantum/<ThemeName>/` AND write `~/.config/Kvantum/kvantum.kvconfig`.

### Environment
- Hyprland on Wayland
- No KDE Plasma, no GTK theming
- Custom dark theme for panel/dunst/rofi

## Decisions Made
- D1: Keep qt6ct as platform theme (already working)
- D2: Keep `QT_STYLE_OVERRIDE=kvantum` for global enforcement
- D3: Keep existing Kvantum symlink workaround pattern
