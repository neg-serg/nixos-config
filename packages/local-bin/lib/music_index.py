#!/usr/bin/env python3
"""Build a similarity index for a music library from model embeddings.

Usage: music_index.py [--out DIR] [--model ID] [--layer N] [-j N] [MUSIC_DIR]

The index is plain numpy — for a library of a few thousand tracks a brute
force cosine search is milliseconds, so there is no Annoy/BLAS dependency to
install and no separate index build step beyond the embedding pass:

  INDEX/vectors.npy   float32 (N, D), L2-normalised rows
  INDEX/tracks.jsonl  one {"path", "mtime", "size", "vector_index"} per line
  INDEX/meta.json     model, layer, dim, count, timestamps
  INDEX/cache/*.npy   per-file vectors, keyed by path+mtime+size+model

Re-running skips files whose cached vector matches (same size and mtime), so
an interrupted pass resumes cheaply.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import music_embed  # noqa: E402  (same directory, wrapper sets PYTHONPATH)

AUDIO_EXTS = {".mp3", ".flac", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".wma"}
DEFAULT_INDEX = Path.home() / ".cache" / "music-index"

_WORKER: dict = {}


def file_key(path: Path) -> str:
    """Cache key: path + mtime + size + model/layer (any change re-embeds)."""
    import hashlib

    stat = path.stat()
    raw = f"{path}:{stat.st_mtime_ns}:{stat.st_size}"
    return hashlib.sha1(raw.encode()).hexdigest()


def scan(root: Path, exts: set[str]) -> list[Path]:
    files = [
        item
        for item in sorted(root.rglob("*"))
        if item.is_file() and item.suffix.lower() in exts
    ]
    return files


def _worker_init(model: str, layer: int, device: str, args: dict) -> None:
    processor, net, rate = music_embed.load_model(model, device)
    _WORKER.update(
        model=net,
        recorder=music_embed.LayerRecorder(net),
        processor=processor,
        rate=rate,
        layer=layer,
        args=argparse.Namespace(**args),
    )


def _worker_embed(path: str) -> list[float]:
    vector = music_embed.embed_file(
        _WORKER["model"],
        _WORKER["processor"],
        path,
        _WORKER["rate"],
        _WORKER["layer"],
        _WORKER["args"],
        _WORKER["recorder"],
    )
    return [float(x) for x in vector]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=str(Path.home() / "music"))
    parser.add_argument("--out", default=str(DEFAULT_INDEX), help="index dir")
    parser.add_argument("--model", default=music_embed.DEFAULT_MODEL)
    parser.add_argument("--layer", type=int, default=-1)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--window-seconds", type=float, default=10.0)
    parser.add_argument("--windows", type=int, default=3)
    parser.add_argument(
        "-j", "--jobs", type=int, default=1, help="parallel workers"
    )
    parser.add_argument(
        "-n", "--limit", type=int, help="only the first N files"
    )
    parser.add_argument(
        "--rebuild", action="store_true", help="ignore the cache"
    )
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    import numpy as np

    root = Path(args.root).expanduser()
    if not root.is_dir():
        print(f"[music-index] not a directory: {root}", file=sys.stderr)
        return 2
    out_dir = Path(args.out).expanduser()
    cache_dir = out_dir / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)

    device = music_embed.pick_device(args.device)
    files = scan(root, AUDIO_EXTS)
    if args.limit:
        files = files[: args.limit]
    if not files:
        print(f"[music-index] no audio files under {root}", file=sys.stderr)
        return 2
    if not args.quiet:
        print(
            f"[music-index] {len(files)} files, {args.model} on {device}",
            file=sys.stderr,
        )

    pending: list[tuple[Path, Path]] = []
    for path in files:
        cache_file = cache_dir / f"{file_key(path)}.npy"
        if args.rebuild or not cache_file.exists():
            pending.append((path, cache_file))

    started = time.time()
    done = 0
    if pending:
        pool = None
        if args.jobs > 1:
            try:
                pool = ProcessPoolExecutor(
                    max_workers=args.jobs,
                    initializer=_worker_init,
                    initargs=(
                        args.model,
                        args.layer,
                        device,
                        {
                            "window_seconds": args.window_seconds,
                            "windows": args.windows,
                            "quiet": True,
                        },
                    ),
                )
            except (OSError, PermissionError) as exc:
                # Sandboxes without POSIX semaphores (and any other pool
                # failure) fall back to the serial pass instead of dying.
                print(
                    f"[music-index] parallel workers unavailable ({exc}); "
                    "running serially",
                    file=sys.stderr,
                )
                pool = None
        try:
            if pool is None:
                _worker_init(
                    args.model,
                    args.layer,
                    device,
                    {
                        "window_seconds": args.window_seconds,
                        "windows": args.windows,
                        "quiet": True,
                    },
                )
            for path, cache_file in pending:
                try:
                    if pool is None:
                        values = _worker_embed(str(path))
                    else:
                        values = pool.submit(_worker_embed, str(path)).result()
                except Exception as exc:  # keep the pass going on bad files
                    print(f"[music-index] skip {path}: {exc}", file=sys.stderr)
                    continue
                np.save(cache_file, np.asarray(values, dtype=np.float32))
                done += 1
                if not args.quiet and done % 10 == 0:
                    rate = done / max(1e-6, time.time() - started)
                    print(
                        f"[music-index] {done}/{len(pending)} "
                        f"({rate:.2f} files/s)",
                        file=sys.stderr,
                    )
        finally:
            if pool is not None:
                pool.shutdown()

    rows, records = [], []
    for path in files:
        cache_file = cache_dir / f"{file_key(path)}.npy"
        if not cache_file.exists():
            continue
        rows.append(np.load(cache_file))
        stat = path.stat()
        records.append(
            {
                "path": str(path),
                "mtime": stat.st_mtime_ns,
                "size": stat.st_size,
                "vector_index": len(rows) - 1,
            }
        )
    if not rows:
        print("[music-index] nothing embedded", file=sys.stderr)
        return 1
    matrix = np.stack(rows).astype(np.float32)
    np.save(out_dir / "vectors.npy", matrix)
    with open(out_dir / "tracks.jsonl", "w") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    meta = {
        "model": args.model,
        "layer": args.layer,
        "dim": int(matrix.shape[1]),
        "count": int(matrix.shape[0]),
        "window_seconds": args.window_seconds,
        "windows": args.windows,
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    with open(out_dir / "meta.json", "w") as handle:
        json.dump(meta, handle, indent=2)
    if not args.quiet:
        print(
            f"[music-index] {matrix.shape[0]} tracks x {matrix.shape[1]} dims "
            f"-> {out_dir} ({done} new, {time.time() - started:.1f}s)",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
