#!/usr/bin/env python3
"""Write the ML mood (and optionally the Discogs style) into the audio files.

Players, MPD's own `search` and other machines only see tags that live in the
files; the mood labels from `music-mtg-tags` otherwise stay in a cache file.
This tool copies them in — dry run by default, and every change is appended to
a JSONL log (old -> new per file) so a run can be reviewed or reverted by hand.

Usage:
    music-apply-tags.py [--tags FILE] [--field mood,genre] [--min-score X]
                        [--top N] [--limit N] [--music-dir DIR] [--only GLOB]
                        [--log FILE] [--apply] [--quiet]

MOOD is a field the files do not carry yet, so writing it is safe; GENRE
*replaces* whatever genre the file already has and is therefore off by default.

Writing goes through mutagen (python3Packages.mutagen): one code path for
FLAC/Ogg (Vorbis comments), MP3/WAV (ID3: TMOO/TCON) and M4A (the
----:com.apple.iTunes freeform atoms this library already uses).  Containers
mutagen cannot write (aac/wma) are reported and skipped.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import sys
import time
from pathlib import Path

DEFAULT_TAGS = os.environ.get(
    "MUSIC_MTG_TAGS", "~/.cache/music-mtg/tags.jsonl"
)
DEFAULT_LOG = os.environ.get(
    "MUSIC_TAG_LOG", "~/.cache/music-mtg/tag-changes.jsonl"
)
AUDIO_SUFFIXES = {
    ".flac",
    ".mp3",
    ".m4a",
    ".ogg",
    ".opus",
    ".wav",
    ".aac",
    ".wma",
}


VORBIS_SUFFIXES = {".flac", ".ogg", ".opus"}
ID3_SUFFIXES = {".mp3", ".wav"}
MP4_SUFFIXES = {".m4a"}
MP4_MOOD = "----:com.apple.iTunes:MOOD"
MP4_GENRE = "\xa9gen"


def writer_for(path: Path) -> str:
    """Which mutagen container handles this file."""
    suffix = path.suffix.lower()
    if suffix in VORBIS_SUFFIXES:
        return "vorbis"
    if suffix in ID3_SUFFIXES:
        return "id3"
    if suffix in MP4_SUFFIXES:
        return "mp4"
    return "unsupported"


def read_tag(writer: str, path: Path, field: str) -> str:
    """Current value of one field, empty when absent."""
    from mutagen.flac import FLAC
    from mutagen.id3 import ID3
    from mutagen.mp4 import MP4, MP4FreeForm
    from mutagen.oggopus import OggOpus
    from mutagen.oggvorbis import OggVorbis
    from mutagen.wave import WAVE

    name = field.upper()
    if writer == "vorbis":
        audio = (
            OggOpus(path)
            if path.suffix.lower() == ".opus"
            else (
                FLAC(path)
                if path.suffix.lower() == ".flac"
                else OggVorbis(path)
            )
        )
        values = audio.get(name) or []
        return str(values[0]) if values else ""
    if writer == "id3":
        tags = WAVE(path).tags if path.suffix.lower() == ".wav" else ID3(path)
        if tags is None:
            return ""
        frame = tags.get("TMOO" if field == "mood" else "TCON")
        return str(frame.text[0]) if frame and frame.text else ""
    if writer == "mp4":
        tags = MP4(path).tags or {}
        key = MP4_MOOD if field == "mood" else MP4_GENRE
        values = tags.get(key) or []
        if not values:
            return ""
        value = values[0]
        if isinstance(value, MP4FreeForm):
            return value.decode("utf-8", "replace")
        return str(value)
    return ""


def write_tag(writer: str, path: Path, field: str, value: str) -> bool:
    """Set one field in place; True when the file was updated."""
    from mutagen.flac import FLAC
    from mutagen.id3 import ID3, TCON, TMOO
    from mutagen.mp4 import MP4, MP4FreeForm
    from mutagen.oggopus import OggOpus
    from mutagen.oggvorbis import OggVorbis
    from mutagen.wave import WAVE

    try:
        if writer == "vorbis":
            audio = (
                OggOpus(path)
                if path.suffix.lower() == ".opus"
                else (
                    FLAC(path)
                    if path.suffix.lower() == ".flac"
                    else OggVorbis(path)
                )
            )
            audio[field.upper()] = value
            audio.save()
            return True
        if writer == "id3":
            audio = WAVE(path) if path.suffix.lower() == ".wav" else None
            if audio is not None:
                tags = audio.add_tags() or audio.tags
            else:
                try:
                    tags = ID3(path)
                except Exception:
                    tags = ID3()
                    tags.save(path)
                    tags = ID3(path)
            frame = TMOO if field == "mood" else TCON
            tags.setall(frame.__name__, [frame(encoding=3, text=value)])
            tags.save(path)
            return True
        if writer == "mp4":
            audio = MP4(path)
            if audio.tags is None:
                audio.add_tags()
            key = MP4_MOOD if field == "mood" else MP4_GENRE
            audio.tags[key] = (
                [MP4FreeForm(value.encode("utf-8"))]
                if field == "mood"
                else [value]
            )
            audio.save()
            return True
    except Exception as exc:
        print(
            f"[music-apply-tags] {field.upper()} failed on {path.name}: "
            f"{type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return False
    print(
        f"[music-apply-tags] {path.suffix} cannot be written (unsupported)",
        file=sys.stderr,
    )
    return False


def pick_labels(tags: dict, field: str, min_score: float, top: int) -> str:
    labels = tags.get(field) or []
    picked = []
    for item in labels:
        if float(item.get("score", 0.0)) < min_score:
            continue
        label = str(item.get("label"))
        # Discogs labels are "Parent---Style"; the file field wants the style.
        picked.append(label.split("---")[-1])
        if len(picked) >= top:
            break
    return ";".join(picked)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tags", default=DEFAULT_TAGS, help="tag JSONL file")
    parser.add_argument(
        "--field",
        default="mood",
        help="mood, genre or both (comma separated; genre replaces the old tag)",
    )
    parser.add_argument("--min-score", type=float, default=0.15)
    parser.add_argument("--top", type=int, default=3, help="labels per field")
    parser.add_argument("--limit", type=int, default=0, help="0 = all files")
    parser.add_argument(
        "--music-dir",
        default=os.environ.get("MUSIC_DIR", "~/music"),
        help="files outside it are refused",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="GLOB",
        help="only matching paths (repeatable, e.g. '*.flac')",
    )
    parser.add_argument("--log", default=DEFAULT_LOG, help="change log")
    parser.add_argument(
        "--apply", action="store_true", help="really write (default: dry run)"
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    args.fields = [
        item.strip() for item in args.field.split(",") if item.strip()
    ]
    bad = [item for item in args.fields if item not in {"mood", "genre"}]
    if bad or not args.fields:
        parser.error("--field must be mood and/or genre")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    tags_file = Path(args.tags).expanduser()
    if not tags_file.is_file():
        print(f"[music-apply-tags] no tag file: {tags_file}", file=sys.stderr)
        return 2
    music_dir = Path(args.music_dir).expanduser().resolve()
    if not music_dir.is_dir():
        print(
            f"[music-apply-tags] no music directory: {music_dir}",
            file=sys.stderr,
        )
        return 2
    log_path = Path(args.log).expanduser()
    if args.apply:
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            # The log is the safety net for a library-wide write, so refuse to
            # touch anything when it cannot be opened.
            print(
                f"[music-apply-tags] cannot create {log_path.parent}: {exc}",
                file=sys.stderr,
            )
            return 2
        print(f"[music-apply-tags] applying to {music_dir}, log -> {log_path}")
    else:
        print(
            f"[music-apply-tags] dry run (add --apply to write), tags={tags_file}"
        )

    files = 0
    changed = 0
    empty = 0
    failed = 0
    handle = log_path.open("a", encoding="utf-8") if args.apply else None
    try:
        for line in tags_file.read_text(errors="replace").splitlines():
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            raw = record.get("path")
            if not isinstance(raw, str):
                continue
            path = Path(raw)
            if not path.is_file() or path.suffix.lower() not in AUDIO_SUFFIXES:
                continue
            if args.only and not any(
                fnmatch.fnmatch(str(path), pattern) for pattern in args.only
            ):
                continue
            try:
                path.resolve().relative_to(music_dir)
            except ValueError:
                print(
                    f"[music-apply-tags] outside {music_dir}, skipped: {path}",
                    file=sys.stderr,
                )
                failed += 1
                continue
            files += 1
            if args.limit and files > args.limit:
                break
            tags = record.get("tags") or {}
            writer = writer_for(path)
            for field in args.fields:
                value = pick_labels(tags, field, args.min_score, args.top)
                if not value:
                    empty += 1
                    continue
                current = read_tag(writer, path, field)
                if current == value:
                    continue
                if not args.apply:
                    if not args.quiet:
                        print(
                            f"would set {field.upper()}={value} "
                            f"(was {current or 'none'}) in "
                            f"{path.relative_to(music_dir)} [{writer}]"
                        )
                    changed += 1
                    continue
                if write_tag(writer, path, field, value):
                    changed += 1
                    handle.write(
                        json.dumps(
                            {
                                "path": str(path),
                                "field": field,
                                "old": current,
                                "new": value,
                                "writer": writer,
                                "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                            },
                            ensure_ascii=False,
                        )
                        + "\n"
                    )
                    handle.flush()
                else:
                    failed += 1
    finally:
        if handle is not None:
            handle.close()
    verb = "written" if args.apply else "would change"
    print(
        f"[music-apply-tags] {changed} {verb}, {empty} without labels, "
        f"{failed} failed (of {files} files)"
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
