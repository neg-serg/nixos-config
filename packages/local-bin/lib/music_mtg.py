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


def settings_key(head_set: str, keys, seconds: float, top: int | None) -> str:
    """Everything that changes the numbers also changes the cached record."""
    return f"{head_set}|{'/'.join(keys)}|seconds={seconds:g}|top={top or 'default'}"


def load_done(path: Path) -> dict[str, tuple[int, int, str]]:
    """path -> (mtime, size, settings) of the tracks already in the output."""
    done: dict[str, tuple[int, int, str]] = {}
    if not path.exists():
        return done
    for line in path.read_text(errors="replace").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        done[record["path"]] = (
            record.get("mtime", 0),
            record.get("size", 0),
            record.get("settings", ""),
        )
    return done


def _record(path: Path, partial: dict, settings: str) -> dict:
    """Full JSONL record: tags plus the resume key of the file itself."""
    stat = path.stat()
    record = dict(partial)
    record["path"] = str(path)
    record["mtime"] = stat.st_mtime_ns
    record["size"] = stat.st_size
    record["engine"] = "mtg"
    record["settings"] = settings
    return record


def _print_progress(done: int, total: int, started: float) -> None:
    elapsed = time.time() - started
    rate = done / elapsed if elapsed else 0.0
    left = (total - done) / rate if rate else 0.0
    print(
        f"[music-mtg] {done}/{total} files, {elapsed:.1f}s elapsed, "
        f"{rate:.1f} files/s, ETA {int(left // 3600):02d}:{int(left % 3600 // 60):02d}:{int(left % 60):02d}",
        file=sys.stderr,
    )


_WORKER: dict = {}


def _worker_init(
    models_dir: str, keys, seconds: float, top: int | None
) -> None:
    """Load the graphs once per worker process."""
    backbone, heads = load_heads(Path(models_dir), keys)
    _WORKER.update(backbone=backbone, heads=heads, seconds=seconds, top=top)


def _worker_tag(path: str) -> dict:
    record = score(
        _WORKER["backbone"],
        _WORKER["heads"],
        load_audio(Path(path), _WORKER["seconds"]),
        top=_WORKER["top"],
    )
    record["path"] = path
    return record


def run_batch(backbone, heads, files, keys, models_dir: Path, args) -> int:
    """Tag a whole library into a JSONL file, resuming by mtime+size+settings."""
    out_path = Path(args.out).expanduser()
    settings = settings_key(args.head_set, keys, args.seconds, args.top)
    done = {} if args.rebuild else load_done(out_path)
    pending = []
    for path in files:
        stat = path.stat()
        if done.get(str(path)) == (stat.st_mtime_ns, stat.st_size, settings):
            continue
        pending.append(path)
    if args.limit:
        pending = pending[: args.limit]
    if not pending:
        print(
            f"[music-mtg] 0 new, {len(files) - len(pending)} skipped -> {out_path}"
        )
        return 0

    jobs = max(1, args.jobs)
    executor = None
    if jobs > 1:
        from concurrent.futures import ProcessPoolExecutor

        try:
            executor = ProcessPoolExecutor(
                max_workers=jobs,
                initializer=_worker_init,
                initargs=(str(models_dir), keys, args.seconds, args.top),
            )
        except (
            OSError,
            PermissionError,
        ) as exc:  # no POSIX semaphores: serial
            print(
                f"[music-mtg] parallel mode unavailable ({exc}); running serially",
                file=sys.stderr,
            )
            executor = None

    started = time.time()
    written = 0
    skipped = 0
    with open(out_path, "a", encoding="utf-8") as handle:
        if executor is not None:
            from concurrent.futures import as_completed

            futures = {
                executor.submit(_worker_tag, str(p)): p for p in pending
            }
            iterator = as_completed(futures)
        else:
            futures = {}
            iterator = pending
        try:
            for item in iterator:
                if futures:
                    path = futures[item]
                    try:
                        partial = item.result()
                    except (
                        Exception
                    ) as exc:  # keep the pass going on bad files
                        print(
                            f"[music-mtg] skip {path}: {exc}", file=sys.stderr
                        )
                        skipped += 1
                        continue
                else:
                    path = item
                    try:
                        partial = score(
                            backbone,
                            heads,
                            load_audio(path, args.seconds),
                            top=args.top,
                        )
                        partial["path"] = str(path)
                    except Exception as exc:
                        print(
                            f"[music-mtg] skip {path}: {exc}", file=sys.stderr
                        )
                        skipped += 1
                        continue
                handle.write(
                    json.dumps(
                        _record(path, partial, settings), ensure_ascii=False
                    )
                    + "\n"
                )
                handle.flush()
                written += 1
                if not args.quiet and written % 25 == 0:
                    _print_progress(written, len(pending), started)
        finally:
            if executor is not None:
                executor.shutdown(wait=False, cancel_futures=True)
    print(
        f"[music-mtg] {written} new, {skipped} skipped -> {out_path} "
        f"({time.time() - started:.1f}s)"
    )
    return 0 if written or not skipped else 1


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
    parser.add_argument(
        "--out",
        help=(
            "batch mode: append JSONL records to FILE and resume by "
            "mtime+size+settings (needed for a whole library)"
        ),
    )
    parser.add_argument(
        "--limit", type=int, help="batch mode: stop after N pending files"
    )
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="batch mode: ignore the output file",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="batch mode: worker processes, each loads its own graph (660 MB RSS each)",
    )
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument(
        "--check", action="store_true", help="report models and exit"
    )
    parser.add_argument(
        "--stats",
        metavar="FILE.jsonl",
        help="summarize an existing tag file (label distribution, mood coverage)",
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if not args.paths and not args.dir and not args.check and not args.stats:
        parser.error("need FILE..., --dir DIR, --stats FILE or --check")
    return args


def head_keys(head_set: str) -> tuple[str, ...]:
    if head_set == "all":
        return tuple(HEADS)
    return CORE_HEADS


def print_stats(tags_file: Path, top: int = 8) -> int:
    """Summarize a tag file: label distribution and mood coverage."""
    if not tags_file.is_file():
        print(f"[music-mtg] no tag file: {tags_file}", file=sys.stderr)
        return 2
    counts: dict[str, dict[str, int]] = {key: {} for key in HEADS}
    tracks = 0
    broken = 0
    covered = 0
    for line in tags_file.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            broken += 1
            continue
        tags = record.get("tags") if isinstance(record, dict) else None
        if not isinstance(tags, dict):
            broken += 1
            continue
        tracks += 1
        for key in counts:
            labels = tags.get(key) or []
            if not labels:
                continue
            top_label = labels[0].get("label")
            if key == "mood" and float(labels[0].get("score", 0)) >= 0.10:
                covered += 1
            if isinstance(top_label, str):
                counts[key][top_label] = counts[key].get(top_label, 0) + 1
    if not tracks:
        print(
            f"[music-mtg] no usable records in {tags_file} ({broken} broken)"
        )
        return 1
    print(f"{tags_file}: {tracks} tracks, {broken} broken lines")
    for key, table in counts.items():
        if not table:
            continue
        rendered = ", ".join(
            f"{label} {count}"
            for label, count in sorted(table.items(), key=lambda kv: -kv[1])[
                :top
            ]
        )
        print(f"  {HEADS[key][2]:18} {rendered}")
    print(f"  mood coverage >= 0.10: {covered}/{tracks}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    models_dir = Path(args.models).expanduser()
    keys = head_keys(args.head_set)
    if args.stats:
        return print_stats(Path(args.stats).expanduser())
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
    if args.out:
        return run_batch(backbone, heads, files, keys, models_dir, args)
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
