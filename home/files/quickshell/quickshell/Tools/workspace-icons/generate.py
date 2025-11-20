#!/usr/bin/env python3
"""Workspace icon generator.

Parses Hyprland workspace definitions, tracks glyph metadata, exports SVGs
from preferred fonts (Font Awesome 6 Pro + fallbacks) and writes a manifest consumed by QuickShell.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import unicodedata
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

DEFAULT_FONT_PATTERN = "Font Awesome 6 Pro"
DEFAULT_FONT_FALLBACKS = ["FiraCode Nerd Font Mono", "Iosevka"]
DEFAULT_VIEWBOX = 1024
DEFAULT_PADDING = 48
HYPR_REL_PATH = Path("nix/.config/home-manager/modules/user/gui/hypr/conf/workspaces.conf")
ICONS_REL_DIR = Path("quickshell/.config/quickshell/Bar/Icons/workspaces")
MAP_FILENAME = "icon-map.json"
MANIFEST_FILENAME = "manifest.json"
SVG_SUBDIR = "workspaces"
SVG_EXT = ".svg"
XML_HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
SVG_NS = "http://www.w3.org/2000/svg"

WORKSPACE_RE = re.compile(r"^\s*workspace\s*=\s*([^,]+),\s*defaultName:(.+)$")
PRIVATE_RANGES = (
    (0xE000, 0xF8FF),  # BMP PUA
    (0xF0000, 0xFFFFD),  # Plane 15
    (0x100000, 0x10FFFD),  # Plane 16
)
VARIATION_RANGES = (
    (0xFE00, 0xFE0F),
    (0xE0100, 0xE01EF),
)


def is_codepoint_in_ranges(cp: int, ranges: Sequence[Tuple[int, int]]) -> bool:
    return any(start <= cp <= end for start, end in ranges)


def is_private_use(cp: int) -> bool:
    return is_codepoint_in_ranges(cp, PRIVATE_RANGES)


def is_variation_selector(cp: int) -> bool:
    return is_codepoint_in_ranges(cp, VARIATION_RANGES)


@dataclass
class WorkspaceDef:
    ws_id: int
    raw_default: str
    glyph: str
    codepoints: List[str]
    hypr_name: str
    slug: str
    label: str
    icon_filename: str
    font_pattern: str
    font_family: str
    font_style: str
    font_file: str
    path_data: str


class SvgExporter:
    def __init__(self, font_path: Path, viewbox: int, padding: int) -> None:
        if viewbox <= 0:
            raise ValueError("viewbox must be positive")
        if padding * 2 >= viewbox:
            raise ValueError("padding must leave positive drawing space")
        self.font = TTFont(font_path)
        self.glyph_set = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap() or {}
        self.viewbox = viewbox
        self.padding = padding
        self.available = viewbox - 2 * padding

    def export_svg(self, codepoint: int, dest: Path) -> str:
        glyph_name = self.cmap.get(codepoint)
        if not glyph_name:
            raise RuntimeError(f"No glyph for codepoint U+{codepoint:04X}")
        glyph = self.glyph_set[glyph_name]
        bounds_pen = BoundsPen(self.glyph_set)
        glyph.draw(bounds_pen)
        if bounds_pen.bounds is None:
            raise RuntimeError(f"Glyph {glyph_name} has no outline")
        xmin, ymin, xmax, ymax = bounds_pen.bounds
        width = xmax - xmin
        height = ymax - ymin
        span = max(width, height)
        scale = self.available / span if span > 0 else 1.0
        span_x = width * scale
        span_y = height * scale
        tx = self.padding + (self.available - span_x) / 2 - scale * xmin
        ty = self.padding + (self.available - span_y) / 2 + scale * ymax
        matrix = (scale, 0.0, 0.0, -scale, tx, ty)
        svg_pen = SVGPathPen(self.glyph_set)
        transform_pen = TransformPen(svg_pen, matrix)
        glyph.draw(transform_pen)
        path_data = svg_pen.getCommands().strip()
        if not path_data:
            raise RuntimeError(f"Glyph {glyph_name} yielded empty path")
        svg = self._wrap_svg(path_data)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(svg, encoding="utf-8")
        return path_data

    def _wrap_svg(self, path: str) -> str:
        return (
            f"{XML_HEADER}\n"
            f"<svg xmlns=\"{SVG_NS}\" viewBox=\"0 0 {self.viewbox} {self.viewbox}\" role=\"img\">\n"
            f"  <path fill=\"currentColor\" d=\"{path}\"/>\n"
            "</svg>\n"
        )


class FontResolver:
    def __init__(self, viewbox: int, padding: int) -> None:
        self.viewbox = viewbox
        self.padding = padding
        self.info_cache: Dict[str, Tuple[str, str, str]] = {}
        self.exporter_cache: Dict[str, SvgExporter] = {}

    def exporter_for_pattern(self, pattern: str) -> Tuple[SvgExporter, Tuple[str, str, str]]:
        info = self.info_cache.get(pattern)
        if info is None:
            info = ensure_font_info(pattern)
            self.info_cache[pattern] = info
        _, _, font_file = info
        exporter = self.exporter_cache.get(font_file)
        if exporter is None:
            exporter = SvgExporter(Path(font_file), self.viewbox, self.padding)
            self.exporter_cache[font_file] = exporter
        return exporter, info


def parse_hypr_workspaces(text: str) -> List[Tuple[int, str]]:
    entries: List[Tuple[int, str]] = []
    for line in text.splitlines():
        match = WORKSPACE_RE.match(line)
        if not match:
            continue
        key, value = match.groups()
        key = key.strip()
        try:
            ws_id = int(key)
        except ValueError:
            continue
        entries.append((ws_id, value.strip()))
    return entries


def should_capture_icon(cp: int) -> bool:
    if is_private_use(cp):
        return True
    category = unicodedata.category(chr(cp))
    return category.startswith("S")


def split_glyph(name: str) -> Tuple[str, str, List[str]]:
    if not name:
        return "", "", []
    chars = list(name)
    if not chars:
        return "", "", []
    first = chars[0]
    cp = ord(first)
    if not should_capture_icon(cp):
        return "", name, []
    glyph_chars = [first]
    codepoints = [f"U+{cp:04X}"]
    idx = 1
    while idx < len(chars):
        cp_next = ord(chars[idx])
        if is_variation_selector(cp_next):
            glyph_chars.append(chars[idx])
            codepoints.append(f"U+{cp_next:04X}")
            idx += 1
            continue
        break
    rest = "".join(chars[idx:]).lstrip()
    return "".join(glyph_chars), rest, codepoints


def slugify(value: str) -> str:
    lowered = value.strip().lower()
    lowered = re.sub(r"[^a-z0-9]+", "-", lowered)
    lowered = lowered.strip("-")
    return lowered


def derive_slug(rest: str, ws_id: int, seen: set[str]) -> Tuple[str, str]:
    hypr_name = rest.strip()
    slug_source = hypr_name
    if ":" in slug_source:
        slug_source = slug_source.split(":", 1)[1]
    slug_source = slug_source.strip()
    if not slug_source:
        slug_source = hypr_name or f"ws{ws_id}"
    slug = slugify(slug_source) or f"ws{ws_id}"
    if slug in seen:
        slug = f"{slug}-{ws_id}"
    seen.add(slug)
    return slug, hypr_name or slug_source


def load_icon_map(path: Path) -> Dict:
    if not path.exists():
        return {
            "fontPattern": DEFAULT_FONT_PATTERN,
            "fontFallbacks": list(DEFAULT_FONT_FALLBACKS),
            "viewBox": DEFAULT_VIEWBOX,
            "padding": DEFAULT_PADDING,
            "icons": {},
        }
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if "fontFallbacks" not in data or not isinstance(data["fontFallbacks"], list):
        data["fontFallbacks"] = list(DEFAULT_FONT_FALLBACKS)
    return data


def save_json(path: Path, data: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")


def _get_name_record(name_table, name_id: int, default: str) -> str:
    try:
        for record in name_table.names:
            if record.nameID == name_id:
                try:
                    return record.toUnicode()
                except Exception:
                    continue
    except Exception:
        pass
    return default


def _font_names_from_file(font_path: Path) -> Tuple[str, str]:
    font = TTFont(str(font_path))
    try:
        name_table = font["name"]
        family = _get_name_record(name_table, 1, font_path.stem)
        style = _get_name_record(name_table, 2, "Regular")
        return family, style
    finally:
        font.close()


def ensure_font_info(pattern: str) -> Tuple[str, str, str]:
    candidate = Path(os.path.expanduser(pattern))
    if candidate.exists():
        family, style = _font_names_from_file(candidate)
        return family, style, str(candidate)
    fmt = "%{family}\n%{style}\n%{file}\n"
    cmd = ["fc-match", "-f", fmt, pattern]
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"fc-match failed for pattern '{pattern}'") from exc
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if len(lines) < 3:
        raise RuntimeError(f"Unexpected fc-match output for '{pattern}': {result.stdout!r}")
    family, style, file_path = lines[:3]
    return family, style, file_path


def validate_command(cmd: Sequence[str]) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def validate_svg(path: Path) -> None:
    if shutil.which("xmllint") is None:
        print(f"WARN: xmllint not found; skipping XML validation for {path}", file=sys.stderr)
    else:
        validate_command(["xmllint", "--noout", str(path)])
    tmp_png = path.with_suffix(".png")
    if shutil.which("rsvg-convert") is None:
        print(f"WARN: rsvg-convert not found; skipping raster validation for {path}", file=sys.stderr)
        return
    try:
        validate_command(["rsvg-convert", "-o", str(tmp_png), str(path)])
    finally:
        if tmp_png.exists():
            tmp_png.unlink()


def build_manifest(font_info: Tuple[str, str, str], font_pattern: str, viewbox: int, items: List[WorkspaceDef]) -> Dict:
    family, style, font_file = font_info
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "viewBox": viewbox,
        "font": {
            "pattern": font_pattern,
            "family": family,
            "style": style,
            "file": font_file,
        },
        "icons": [
            {
                "id": item.ws_id,
                "slug": item.slug,
                "hyprName": item.hypr_name,
                "label": item.label,
                "codepoints": item.codepoints,
                "svg": str(Path(SVG_SUBDIR) / item.icon_filename),
                "path": item.path_data,
                "defaultName": item.raw_default,
                "font": {
                    "pattern": item.font_pattern,
                    "family": item.font_family,
                    "style": item.font_style,
                    "file": item.font_file,
                },
            }
            for item in items
        ],
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Generate workspace icon assets")
    parser.add_argument("--hypr", type=Path, default=repo_root / HYPR_REL_PATH)
    parser.add_argument("--icons", type=Path, default=repo_root / ICONS_REL_DIR)
    parser.add_argument("--font-pattern", dest="font_pattern", default=None)
    parser.add_argument("--skip-validate", action="store_true", help="Skip XML/SVG validation")
    args = parser.parse_args(argv)

    hypr_path = args.hypr
    icons_dir = args.icons
    map_path = icons_dir / MAP_FILENAME
    manifest_path = icons_dir / MANIFEST_FILENAME
    svg_dir = icons_dir

    map_data = load_icon_map(map_path)
    if args.font_pattern:
        map_data["fontPattern"] = args.font_pattern
    font_pattern = map_data.get("fontPattern") or DEFAULT_FONT_PATTERN
    viewbox = int(map_data.get("viewBox", DEFAULT_VIEWBOX))
    padding = int(map_data.get("padding", DEFAULT_PADDING))

    fallback_patterns_raw = map_data.get("fontFallbacks", [])
    fallback_patterns = [
        str(item).strip()
        for item in (fallback_patterns_raw or [])
        if isinstance(item, str) and str(item).strip()
    ]

    hypr_text = hypr_path.read_text(encoding="utf-8")
    hypr_entries = parse_hypr_workspaces(hypr_text)
    if not hypr_entries:
        raise RuntimeError(f"No workspace definitions found in {hypr_path}")

    icon_map = map_data.setdefault("icons", {})
    seen_slugs: set[str] = set()
    workspace_specs: List[Dict[str, Any]] = []

    for ws_id, raw in hypr_entries:
        glyph, rest, codepoints = split_glyph(raw)
        slug, hypr_name = derive_slug(rest or raw, ws_id, seen_slugs)
        label = hypr_name.strip() or slug
        map_entry = icon_map.get(slug)
        if not isinstance(map_entry, dict):
            map_entry = {}
            icon_map[slug] = map_entry
        if glyph:
            map_entry["codepoints"] = codepoints
        stored_codes = map_entry.get("codepoints")
        if not stored_codes:
            raise RuntimeError(f"Missing glyph codepoints for slug '{slug}' (workspace {ws_id})")
        glyph_codes = stored_codes
        glyph_chars = "".join(chr(int(cp[2:], 16)) for cp in glyph_codes)
        filename = f"{ws_id:02d}-{slug}.svg"
        workspace_specs.append(
            {
                "ws_id": ws_id,
                "raw_default": raw,
                "glyph": glyph_chars,
                "codepoints": glyph_codes,
                "hypr_name": hypr_name,
                "slug": slug,
                "label": label,
                "icon_filename": filename,
                "map_entry": map_entry,
            }
        )

    workspace_specs.sort(key=lambda item: item["ws_id"])
    resolver = FontResolver(viewbox=viewbox, padding=padding)
    default_font_info = resolver.exporter_for_pattern(font_pattern)[1]
    final_items: List[WorkspaceDef] = []

    for spec in workspace_specs:
        map_entry = spec["map_entry"]
        preferred_patterns: List[str] = []
        entry_pattern = map_entry.get("fontPattern") if isinstance(map_entry, dict) else None
        if isinstance(entry_pattern, str) and entry_pattern.strip():
            preferred_patterns.append(entry_pattern.strip())
        if font_pattern not in preferred_patterns:
            preferred_patterns.append(font_pattern)
        for fallback in fallback_patterns:
            if fallback not in preferred_patterns:
                preferred_patterns.append(fallback)

        svg_path = svg_dir / spec["icon_filename"]
        primary_code = int(spec["codepoints"][0][2:], 16)
        export_info = None
        exported_path_data: Optional[str] = None
        last_error: Optional[Exception] = None
        for pattern_choice in preferred_patterns:
            exporter_instance, info = resolver.exporter_for_pattern(pattern_choice)
            try:
                exported_path_data = exporter_instance.export_svg(primary_code, svg_path)
            except RuntimeError as err:
                last_error = err
                continue
            export_info = (pattern_choice, *info)
            break
        if export_info is None:
            raise last_error or RuntimeError(f"No glyph available for slug '{spec['slug']}'")
        if not exported_path_data:
            raise RuntimeError(f"Failed to export path data for slug '{spec['slug']}'")

        used_pattern, used_family, used_style, used_file = export_info
        if isinstance(map_entry, dict):
            map_entry["fontPattern"] = used_pattern
        if not args.skip_validate:
            validate_svg(svg_path)

        final_items.append(
            WorkspaceDef(
                ws_id=spec["ws_id"],
                raw_default=spec["raw_default"],
                glyph=spec["glyph"],
                codepoints=spec["codepoints"],
                hypr_name=spec["hypr_name"],
                slug=spec["slug"],
                label=spec["label"],
                icon_filename=spec["icon_filename"],
                font_pattern=used_pattern,
                font_family=used_family,
                font_style=used_style,
                font_file=used_file,
                path_data=exported_path_data,
            )
        )

    save_json(map_path, map_data)

    manifest = build_manifest(default_font_info, font_pattern, viewbox, final_items)
    save_json(manifest_path, manifest)
    print(f"Wrote {manifest_path.relative_to(repo_root)} ({len(final_items)} icons)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
