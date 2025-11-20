# Workspace Icons

This directory stores the SVG assets, manifest, and generator metadata used by the
Quickshell workspace indicator.

Files:

- `manifest.json` — runtime data consumed by QML (slug/id mapping, per-icon font info, SVG path).
- `icon-map.json` — generator input that persists each slug's codepoints and preferred font.
  Update this file when adding/removing workspaces or switching glyphs.
- `workspaces/*.svg` — generated assets (viewBox 0 0 1024 1024, filled with `currentColor`).

## Regenerating icons

Run from the repo root:

```
just workspace-icons
```

The recipe wraps `quickshell/.config/quickshell/Tools/workspace-icons/generate.py` inside a
`nix shell` that provides python+fonttools, `xmllint`, and `rsvg-convert`. The script:

1. Parses `modules/user/gui/hypr/conf/workspaces.conf` for workspace ids/labels.
2. Uses `icon-map.json` to map slugs to glyph codepoints and preferred fonts. If you removed
   glyphs from Hypr, make sure `icon-map.json` still lists the correct codepoints.
3. Exports each glyph to `workspaces/<id>-<slug>.svg`, normalizing to a square 1024 viewBox.
4. Validates the output via `xmllint` and `rsvg-convert`.
5. Writes an updated `manifest.json` with absolute font metadata for QML.

## Adding or changing a glyph

1. Update `modules/user/gui/hypr/conf/workspaces.conf` so the workspace name reflects the new
   slug/label (no need to embed glyphs).
2. Edit `icon-map.json` to point the slug at the desired codepoint(s) and, if necessary, a
   different `fontPattern` (e.g., `Iosevka` if Nerd Font lacks the glyph).
3. Run `just workspace-icons` and commit the updated manifest + SVG(s).

Keep SVG edits automated — manual tweaks should go into upstream font sources, not here.
