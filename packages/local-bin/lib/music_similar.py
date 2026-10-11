#!/usr/bin/env python3
"""Query the nearest neighbours of a track from a music-index directory.

Usage: music_similar.py [--index DIR] [-k N] [--json] [AUDIO]

Without AUDIO the current track is taken from playerctl (MPRIS), which makes
the command a one-liner for a compositor key binding.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import music_embed  # noqa: E402  (same directory, wrapper sets PYTHONPATH)

DEFAULT_INDEX = Path.home() / ".cache" / "music-index"


def current_track_path() -> str | None:
    """Path of the track MPRIS reports as playing."""
    try:
        url = subprocess.check_output(
            ["playerctl", "metadata", "xesam:url"], text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    if not url.startswith("file://"):
        return None
    return unquote(urlparse(url).path)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "audio", nargs="?", help="query file (default: playerctl)"
    )
    parser.add_argument("--index", default=str(DEFAULT_INDEX))
    parser.add_argument("-k", type=int, default=15, help="neighbours to print")
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument("--device", default="auto")
    parser.add_argument(
        "--self",
        action="store_true",
        help="keep the query track itself in the results",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    import numpy as np

    index_dir = Path(args.index).expanduser()
    vectors_path = index_dir / "vectors.npy"
    tracks_path = index_dir / "tracks.jsonl"
    meta_path = index_dir / "meta.json"
    if not vectors_path.exists() or not tracks_path.exists():
        print(
            f"[music-similar] no index in {index_dir}; build it with music-index",
            file=sys.stderr,
        )
        return 2
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    audio = args.audio or current_track_path()
    if not audio:
        print(
            "[music-similar] no audio argument and no playerctl track",
            file=sys.stderr,
        )
        return 2
    query_path = Path(audio).expanduser()
    if not query_path.exists():
        print(f"[music-similar] file not found: {query_path}", file=sys.stderr)
        return 2

    model_id = meta.get("model", music_embed.DEFAULT_MODEL)
    layer = int(meta.get("layer", -1))
    device = music_embed.pick_device(args.device)
    processor, model, rate = music_embed.load_model(model_id, device)
    recorder = music_embed.LayerRecorder(model)
    dummy = argparse.Namespace(
        window_seconds=float(meta.get("window_seconds", 10.0)),
        windows=int(meta.get("windows", 3)),
        quiet=True,
    )
    try:
        query = music_embed.embed_file(
            model, processor, str(query_path), rate, layer, dummy, recorder
        )
    finally:
        recorder.close()

    matrix = np.load(vectors_path)
    tracks = [
        json.loads(line) for line in tracks_path.read_text().splitlines()
    ]
    if matrix.shape[0] != len(tracks):
        print(
            "[music-similar] index is inconsistent; rebuild with music-index",
            file=sys.stderr,
        )
        return 3
    scores = matrix @ query
    order = np.argsort(-scores)
    query_real = str(query_path.resolve())
    results = []
    for position in order:
        record = tracks[int(position)]
        path = record["path"]
        if not args.self and str(Path(path).resolve()) == query_real:
            continue
        results.append((float(scores[int(position)]), path))
        if len(results) >= args.k:
            break
    if args.json:
        print(
            json.dumps(
                {
                    "query": str(query_path),
                    "model": model_id,
                    "results": [
                        {"score": round(score, 4), "path": path}
                        for score, path in results
                    ],
                },
                ensure_ascii=False,
            )
        )
    else:
        for score, path in results:
            print(f"{score:6.3f}  {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
