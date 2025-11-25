# Workspace Icon Pipeline

This doc explains how the workspace indicator glyphs are generated and how to refresh them when
Hyprland or the QuickShell theme changes.

## Source of truth

- Hypr names live in `modules/user/gui/hypr/conf/workspaces.conf`. Names keep the Gothic/Coptic
  prefixes (e.g. `𐌰:term`) but **do not** include Private Use Area glyphs any more.
- Glyph metadata (codepoints + preferred font) is stored in
  `quickshell/.config/quickshell/Bar/Icons/workspaces/icon-map.json`. This lets us keep the icon
  mapping even though the Hypr config no longer embeds the icon characters.
- The generator writes SVGs and `manifest.json` into the same directory. The manifest is read at
  runtime by `Helpers/WorkspaceIcons.js`.

## Regeneration steps

1. Adjust Hypr workspaces or `icon-map.json` as needed.
2. From the repo root run:

   ```bash
   just workspace-icons
   ```

   The `just` recipe launches `quickshell/.config/quickshell/Tools/workspace-icons/generate.py`
   inside a `nix shell` with python 3.13, `fonttools`, `xmllint`, and `rsvg-convert`.

3. The script will:
   - Parse Hypr workspace ids/names.
   - Merge that with `icon-map.json`, resolving fonts via `fc-match` (with per-slug overrides and
     fallbacks like `Iosevka`).
   - Export each glyph to `workspaces/<id>-<slug>.svg` (viewBox `0 0 1024 1024`, fill
     `currentColor`).
   - Validate every SVG via `xmllint --noout` and `rsvg-convert`.
   - Update `icon-map.json` (preserving overrides) and emit a fresh `manifest.json` with absolute
     font metadata.

4. Commit the new/modified SVGs, manifest, and any icon-map changes.

## Adding a new workspace icon

1. Add the workspace entry to the Hypr config (without embedding the icon glyph).
2. In `icon-map.json` add a block for the slug:

   ```json
   "my-slug": {
     "codepoints": ["U+E123"],
     "fontPattern": "FiraCode Nerd Font Mono"
   }
   ```

   - `codepoints` can list multiple values (e.g., glyph + variation selector).
   - `fontPattern` is optional; omit it to use the global default.

3. Run `just workspace-icons` to generate the SVG and manifest entry.
4. Update docs / QML if the new workspace needs bespoke behavior.

## Troubleshooting

- `fc-match` failure: ensure the referenced font is installed or point `fontPattern` at an
  absolute path.
- Missing glyph errors: add a fallback font (e.g., `Iosevka`) to `icon-map.json` or the global
  `fontFallbacks` list, then rerun the generator.
- `xmllint` / `rsvg-convert` failures: check stdout for syntax errors; the generator will stop at
  the first invalid SVG so you can fix the glyph mapping.

The runtime loader (`Helpers/WorkspaceIcons.js`) reads `manifest.json` at startup; no reload is
needed unless you change assets while QuickShell is running (in that case use the QuickShell reload
binding).
