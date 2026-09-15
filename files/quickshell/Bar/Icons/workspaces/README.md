# Workspace Icons

This directory stores the SVG assets, manifest, and generator metadata used by the Quickshell
workspace indicator.

Files:

- `manifest.json` — runtime data consumed by QML (slug/id mapping, per-icon font names, SVG path).
  `font.file` is written only for fonts inside the user tree (`$XDG_DATA_HOME`, `~`); fonts from the
  nix store are referenced by pattern/family alone — absolute paths went stale on every nixpkgs bump
  and nothing at runtime reads them.
- `icon-map.json` — generator input that persists each slug's codepoints and preferred font. Update
  this file when adding/removing workspaces or switching glyphs.
- `workspaces/*.svg` — generated assets (viewBox 0 0 1024 1024, filled with `currentColor`).

## Regenerating icons

Run from the repo root:

```bash
python3 files/quickshell/Tools/workspace-icons/generate.py
```

Requires: `python`, `python-fonttools`, `libxml2` (xmllint), `librsvg` (rsvg-convert — without it
pass `--skip-validate`). The script:

1. Parses workspace ids/labels from the `workspaces` table in `files/gui/hypr/hyprland.lua`
   (`id`/`name`/`layout`, fed to `hl.workspace_rule`). The old hyprlang layout
   (`files/gui/hypr/workspaces.conf`, `quickshell/.config/quickshell/...`) is gone and the parser
   was ported to the table in 2026-09. Every glyph now comes from fonts that are actually installed
   (`FiraCode Nerd Font Mono` for 17 icons, `Iosevka` for `obs`); the icons that used to be drawn
   from the licensed Font Awesome 6 Pro were re-picked in 2026-09 (`term` → `cod-terminal`, `dev` →
   `oct-code_square`, `vm` → `cod-vm`, `im` → `fa-comments`, `remote` → `fa-download`, `notes` →
   `fa-clone`; the rest kept their codepoints because the nerd font carries the same FA glyphs). The
   orphan `patchbay` map entry (no such workspace) was dropped. The run resolves *every* icon before
   writing anything, so a blocked run leaves this directory untouched, and a second run is
   byte-identical apart from `generatedAt` (verified).
1. Uses `icon-map.json` to map slugs to glyph codepoints and preferred fonts. If you removed glyphs
   from Hypr, make sure `icon-map.json` still lists the correct codepoints.
1. Exports each glyph to `workspaces/<id>-<slug>.svg`, normalizing to a square 1024 viewBox.
1. Validates the output via `xmllint` and `rsvg-convert`.
1. Writes an updated `manifest.json` with per-icon font names (`file` only for user-tree fonts).

## Adding or changing a glyph

1. Add/adjust the entry in the `workspaces` table in `files/gui/hypr/hyprland.lua` so the name
   reflects the new slug/label (no need to embed glyphs).
1. Edit `icon-map.json` to point the slug at the desired codepoint(s) and, if necessary, a different
   `fontPattern` (e.g., `Iosevka` if Nerd Font lacks the glyph).
1. Run `python3 files/quickshell/Tools/workspace-icons/generate.py` and commit the updated manifest
   - SVG(s) (see the parser blocker above).

Keep SVG edits automated — manual tweaks should go into upstream font sources, not here.
