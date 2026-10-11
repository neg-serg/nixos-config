#!/usr/bin/env python3
"""Trained MTG (Essentia) music tags: Discogs-400 styles + Jamendo mood/theme.

Zero-shot CLAP (`music-tags`) matches free text against an audio embedding;
these heads are *trained* on the Discogs/Jamendo taxonomies, so the labels are
canonical, prompt-insensitive and cheap: EffNet-Discogs embeddings (~0.34 s for
30 s of audio, CPU) followed by one small head per taxonomy (~0.03 s).

Measured on four known tracks (30 s, mean over 29 EffNet frames):
  Evoken  -> Doom Metal .11, Funeral Doom Metal in the top-5
  AFX     -> Jungle .20, Drum n Bass .19, Breakcore .19, IDM .18
  Cryo    -> Dark Ambient .39 (CLAP could only say drone/ambient)
  Rome    -> Experimental .32, Neofolk .09 (CLAP was more confident here)

Models come from `scripts/dev/music-mtg-models.sh` (default directory
`/zero/ai/music-ai/mtg-models`, override with --models or MUSIC_MTG_MODELS);
the interpreter needs `essentia-tensorflow`, which lives in the dedicated
`venv-mtg` created by `scripts/dev/music-mtg-setup.sh` — the shared
venv-analysis has plain essentia without the TensorflowPredict* classes.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

DEFAULT_MODELS = os.environ.get(
    "MUSIC_MTG_MODELS", "/zero/ai/music-ai/mtg-models"
)
DEFAULT_SECONDS = 30.0
BACKBONE = "discogs-effnet-bs64-1"
# key -> (model file stem, default number of labels, human title)
HEADS = {
    "genre": ("genre_discogs400-discogs-effnet-1", 5, "Discogs-400 styles"),
    "mood": (
        "mtg_jamendo_moodtheme-discogs-effnet-1",
        3,
        "Jamendo mood/theme",
    ),
    "instrument": (
        "mtg_jamendo_instrument-discogs-effnet-1",
        3,
        "instruments",
    ),
    "danceability": ("danceability-discogs-effnet-1", 2, "danceability"),
    "voice": ("voice_instrumental-discogs-effnet-1", 2, "voice/instrumental"),
}
CORE_HEADS = ("genre", "mood", "instrument")
AUDIO_EXTS = {".mp3", ".flac", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".wma"}


def head_files(models_dir: Path, key: str) -> tuple[Path, Path]:
    stem = HEADS[key][0]
    return models_dir / f"{stem}.pb", models_dir / f"{stem}.json"


def missing_files(models_dir: Path, keys) -> list[Path]:
    """Model files that are not on disk yet (backbone first)."""
    missing = [models_dir / f"{BACKBONE}.pb"]
    for key in keys:
        missing.extend(head_files(models_dir, key))
    return [path for path in missing if not path.exists()]


def check_models(models_dir: Path, keys) -> int:
    missing = missing_files(models_dir, keys)
    present = len(keys) * 2 + 1 - len(missing)
    total = len(keys) * 2 + 1
    print(f"[music-mtg] models in {models_dir}: {present}/{total} files")
    for path in missing:
        print(f"  missing: {path.name}")
    if missing:
        print(
            "[music-mtg] fetch them with scripts/dev/music-mtg-models.sh "
            f"--dir {models_dir} --set {'core' if set(keys) <= set(CORE_HEADS) else 'all'}"
        )
        return 1
    return 0


def load_heads(models_dir: Path, keys):
    """(backbone, [(key, top_k, classes, predictor)]) with metadata loaded."""
    from essentia.standard import (
        TensorflowPredict2D,
        TensorflowPredictEffnetDiscogs,
    )

    backbone = TensorflowPredictEffnetDiscogs(
        graphFilename=str(models_dir / f"{BACKBONE}.pb"),
        output="PartitionedCall:1",
    )
    heads = []
    for key in keys:
        stem, top_k, _title = HEADS[key]
        meta = json.loads((models_dir / f"{stem}.json").read_text())
        schema = meta["schema"]
        predictor = TensorflowPredict2D(
            graphFilename=str(models_dir / f"{stem}.pb"),
            input=schema["inputs"][0]["name"],
            output=schema["outputs"][0]["name"],
        )
        heads.append((key, top_k, list(meta["classes"]), predictor))
    return backbone, heads


def load_audio(path: Path, seconds: float):
    """Mono 16 kHz float array, clipped to the first ``seconds``."""
    from essentia.standard import MonoLoader

    samples = MonoLoader(
        filename=str(path), sampleRate=16000, resampleQuality=4
    )()
    if seconds:
        samples = samples[: int(seconds * 16000)]
    return samples


def score(backbone, heads, samples, top: int | None = None) -> dict:
    """Mean-pooled predictions of every head for one clip."""
    import numpy as np

    # Short inputs come back as a list (or a flat single frame): normalise.
    embeddings = np.asarray(backbone(samples))
    if embeddings.ndim == 1:
        embeddings = embeddings.reshape(1, -1)
    if embeddings.size == 0 or embeddings.shape[0] == 0:
        raise ValueError("clip too short for EffNet frames (need about 1 s)")
    record = {"frames": int(embeddings.shape[0]), "tags": {}}
    for key, default_top, classes, predictor in heads:
        mean = np.asarray(predictor(embeddings)).mean(axis=0)
        order = np.argsort(mean)[::-1][: (top or default_top)]
        record["tags"][key] = [
            {
                "label": str(classes[int(index)]),
                "score": round(float(mean[int(index)]), 4),
            }
            for index in order
        ]
    return record


def tag_file(backbone, heads, path: Path, seconds: float, top: int | None):
    started = time.time()
    record = score(backbone, heads, load_audio(path, seconds), top=top)
    record["path"] = str(path)
    record["engine"] = "mtg"
    record["seconds"] = round(time.time() - started, 3)
    return record


def print_record(record: dict, titles: dict) -> None:
    print(
        f"{record['path']}  ({record['seconds']:.2f}s, {record['frames']} frames)"
    )
    for key, tags in record["tags"].items():
        rendered = ", ".join(
            f"{tag['label']} {tag['score']:.3f}" for tag in tags
        )
        print(f"  {titles.get(key, key):18} {rendered}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("paths", nargs="*", help="audio files")
    parser.add_argument(
        "--models", default=DEFAULT_MODELS, help="model directory"
    )
    parser.add_argument(
        "--set",
        dest="head_set",
        default="core",
        choices=("core", "all"),
        help="core: genre/mood/instrument; all: + danceability/voice",
    )
    parser.add_argument(
        "--top", type=int, help="labels per head (default per head)"
    )
    parser.add_argument(
        "--seconds", type=float, default=DEFAULT_SECONDS, help="clip length"
    )
    parser.add_argument("--dir", help="tag every audio file under DIR instead")
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument(
        "--check", action="store_true", help="report models and exit"
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if not args.paths and not args.dir and not args.check:
        parser.error("need FILE..., --dir DIR or --check")
    return args


def head_keys(head_set: str) -> tuple[str, ...]:
    if head_set == "all":
        return tuple(HEADS)
    return CORE_HEADS


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    models_dir = Path(args.models).expanduser()
    keys = head_keys(args.head_set)
    if args.check:
        return check_models(models_dir, keys)
    missing = missing_files(models_dir, keys)
    if missing:
        print(
            f"[music-mtg] missing {len(missing)} model file(s) in {models_dir}; "
            "run scripts/dev/music-mtg-models.sh",
            file=sys.stderr,
        )
        return 2

    files: list[Path] = []
    for raw in args.paths:
        path = Path(raw).expanduser()
        if not path.exists():
            print(f"[music-mtg] file not found: {path}", file=sys.stderr)
            return 2
        files.append(path)
    if args.dir:
        root = Path(args.dir).expanduser()
        if not root.is_dir():
            print(f"[music-mtg] not a directory: {root}", file=sys.stderr)
            return 2
        files.extend(
            item
            for item in sorted(root.rglob("*"))
            if item.is_file() and item.suffix.lower() in AUDIO_EXTS
        )
    if not files:
        print("[music-mtg] no audio files to tag", file=sys.stderr)
        return 2

    backbone, heads = load_heads(models_dir, keys)
    # One warm-up call: the first inference also loads the graph (~0.4 s).
    try:
        score(backbone, heads, load_audio(files[0], 5.0), top=1)
    except Exception as exc:  # a warm-up failure must not kill the real pass
        print(f"[music-mtg] warm-up skipped: {exc}", file=sys.stderr)
    titles = {key: HEADS[key][2] for key in keys}
    records = []
    for path in files:
        try:
            record = tag_file(backbone, heads, path, args.seconds, args.top)
        except Exception as exc:  # keep a batch going on unreadable files
            print(f"[music-mtg] skip {path}: {exc}", file=sys.stderr)
            continue
        records.append(record)
        if args.json:
            print(json.dumps(record, ensure_ascii=False))
        elif not args.quiet:
            print_record(record, titles)
    return 0 if records else 1


if __name__ == "__main__":
    raise SystemExit(main())
