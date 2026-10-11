#!/usr/bin/env python3
"""Query the nearest neighbours of a track from a music-index directory.

Usage: music_similar.py [--index DIR] [-k N] [--json] [AUDIO]

Without AUDIO the current track is taken from playerctl (MPRIS), which makes
the command a one-liner for a compositor key binding.

The embedding settings are read from the index meta.json and checked against
its recorded signature, so a query is never embedded with settings other than
the ones the index vectors were built with. --selftest runs the ranking logic
against deterministic stub vectors (no torch, no model, no venv).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import music_embed  # noqa: E402  (same directory, wrapper sets PYTHONPATH)
from music_index import (  # noqa: E402  (same directory)
    IndexProblem,
    embed_signature,
    index_settings,
    index_signature,
    load_index,
    stub_embed,
    write_index,
)

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
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the offline stub-embedder self-check and exit",
    )
    parser.add_argument(
        "--queue",
        action="store_true",
        help="append the neighbours to the MPD queue with mpc instead of printing",
    )
    parser.add_argument(
        "--music-dir",
        default=os.environ.get("MUSIC_DIR", str(Path.home() / "music")),
        help="MPD music_directory; queued paths are made relative to it",
    )
    parser.add_argument(
        "--mpc-cmd",
        default=os.environ.get("MPC_CMD", "mpc"),
        help="command used for --queue (default: mpc)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="with --queue: print the commands without running them",
    )
    return parser.parse_args(argv)


def queue_neighbours(
    results: list[tuple[float, str]],
    music_dir: Path,
    mpc_cmd: str,
    dry_run: bool = False,
) -> int:
    """Append every neighbour to the MPD queue; returns how many were queued."""
    queued = 0
    for _score, path in results:
        try:
            uri = os.path.relpath(Path(path), music_dir)
        except ValueError:
            print(
                f"[music-similar] outside music_dir, skipped: {path}",
                file=sys.stderr,
            )
            continue
        if uri.startswith(".."):
            print(
                f"[music-similar] not under {music_dir}, skipped: {path}",
                file=sys.stderr,
            )
            continue
        if dry_run:
            print(f"{mpc_cmd} add {uri}")
            queued += 1
            continue
        completed = subprocess.run(
            [mpc_cmd, "add", uri],
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        if completed.returncode != 0:
            detail = (
                (completed.stderr or completed.stdout).strip().splitlines()
            )
            print(
                f"[music-similar] mpc add {uri} failed: {detail[-1] if detail else ''}",
                file=sys.stderr,
            )
            continue
        print(f"queued: {uri}")
        queued += 1
    return queued


def rank(
    matrix,
    query,
    k: int,
    paths: list[str] | None = None,
    exclude_path: str | None = None,
) -> list[tuple[float, str]]:
    """Top-k ``(score, path)`` pairs by cosine similarity, highest first.

    ``paths`` names the matrix rows; without it rows are reported by index.
    ``exclude_path`` is compared after ``Path.resolve()`` so relative and
    symlinked spellings of the query track are dropped.
    """
    import numpy as np

    if k <= 0:
        return []
    scores = matrix @ query
    order = np.argsort(-scores)
    excluded = str(Path(exclude_path).resolve()) if exclude_path else None
    results = []
    for position in order:
        index = int(position)
        path = str(paths[index]) if paths is not None else str(index)
        if excluded is not None and str(Path(path).resolve()) == excluded:
            continue
        results.append((float(scores[index]), path))
        if len(results) >= k:
            break
    return results


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(f"music-similar selftest: {message}")


def selftest() -> int:
    """Offline self-check: stub vectors, ranking and index errors."""
    import contextlib
    import io
    import tempfile

    try:
        index_signature({"model": "incomplete"})
    except IndexProblem:
        pass
    else:
        _check(False, "incomplete meta was accepted")
    try:
        import numpy as np
    except ImportError:
        print("[music-similar] selftest: skipped (numpy missing)")
        return 0

    matrix = np.asarray(
        [
            [1.0, 0.0, 0.0],  # the query vector itself
            [1.0, 0.0, 0.0],  # its identical twin
            [0.0, 1.0, 0.0],  # orthogonal
        ],
        dtype=np.float32,
    )
    query = np.asarray([1.0, 0.0, 0.0], dtype=np.float32)
    paths = ["self.wav", "twin.wav", "other.wav"]
    results = rank(matrix, query, 3, paths=paths)
    _check(
        sorted(path for _, path in results[:2]) == ["self.wav", "twin.wav"],
        "nearest neighbours are not the identical pair",
    )
    _check(results[0][0] > 0.999, "identical vector score is not 1")
    _check(
        results[2][1] == "other.wav" and abs(results[2][0]) < 1e-6,
        "orthogonal vector is not ranked last",
    )
    _check(len(rank(matrix, query, 1, paths=paths)) == 1, "-k not honoured")
    _check(rank(matrix, query, 0, paths=paths) == [], "-k 0 not honoured")
    excluded = rank(matrix, query, 3, paths=paths, exclude_path="self.wav")
    _check(
        [path for _, path in excluded] == ["twin.wav", "other.wav"],
        "self-exclusion dropped the wrong row",
    )
    _check(parse_args(["--selftest"]).selftest, "--selftest not parsed")
    _check(parse_args(["-k", "3"]).k == 3, "-k not parsed")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        audio = tmp / "query.wav"
        audio.write_bytes(b"")
        twin_dir = tmp / "twin"
        twin_dir.mkdir()
        (twin_dir / "query.wav").write_bytes(b"")
        other = tmp / "other.wav"
        other.write_bytes(b"x")
        query_vec = stub_embed(str(audio))
        twin_vec = stub_embed(str(twin_dir / "query.wav"))
        _check(query_vec == twin_vec, "stub embedder is not name-stable")
        stub_matrix = np.asarray(
            [query_vec, twin_vec, stub_embed(str(other))], dtype=np.float32
        )
        stub_paths = [str(audio), str(twin_dir / "query.wav"), str(other)]
        neighbours = rank(
            stub_matrix,
            np.asarray(query_vec, dtype=np.float32),
            2,
            paths=stub_paths,
        )
        _check(
            neighbours[0][0] > 0.99 and neighbours[0][1] in stub_paths[:2],
            "stub nearest neighbour is wrong",
        )

        missing = tmp / "missing-index"
        try:
            load_index(missing)
        except IndexProblem as exc:
            _check("no index" in str(exc), f"unclear error: {exc}")
        else:
            _check(False, "missing index was accepted")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = main(["--index", str(missing), "--json"])
        _check(rc != 0, "main accepted a missing index")
        _check("no index" in stderr.getvalue(), "main error is unclear")

        index_dir = tmp / "index"
        records = [{"path": str(audio), "mtime": 0, "size": 0}]
        vectors = np.asarray([[1.0, 0.0, 0.0]], dtype=np.float32)
        signature = embed_signature("stub/model", -2, 10.0, 3)
        meta = {
            "model": "stub/model",
            "layer": -2,
            "window_seconds": 10.0,
            "windows": 3,
            "signature": signature,
            "dim": 3,
            "count": 1,
        }
        write_index(index_dir, records, vectors, meta)
        loaded_meta, loaded_tracks, loaded = load_index(index_dir)
        _check(
            loaded.shape == (1, 3) and loaded_meta["signature"] == signature,
            "load_index returned the wrong data",
        )
        _check(
            loaded_tracks[0]["path"] == str(audio),
            "load_index returned the wrong tracks",
        )
        # A legacy index without a signature is accepted when its settings are
        # complete: the signature is derived from the recorded settings.
        legacy = {
            key: value for key, value in meta.items() if key != "signature"
        }
        write_index(index_dir, records, vectors, legacy)
        load_index(index_dir)
        # A signature that disagrees with the recorded settings is refused.
        bad = dict(meta, signature="0" * 12)
        write_index(index_dir, records, vectors, bad)
        try:
            load_index(index_dir)
        except IndexProblem as exc:
            _check("signature" in str(exc), f"unclear error: {exc}")
        else:
            _check(False, "mismatched signature was accepted")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = main(["--index", str(index_dir), "--json"])
        _check(rc != 0, "main accepted an incompatible index")
        _check(
            "signature" in stderr.getvalue(), "main signature error is unclear"
        )
        # Incomplete meta (settings cannot be established) is refused too.
        incomplete = {
            key: value
            for key, value in meta.items()
            if key not in ("signature", "windows")
        }
        write_index(index_dir, records, vectors, incomplete)
        try:
            load_index(index_dir)
        except IndexProblem:
            pass
        else:
            _check(False, "incomplete meta was accepted")
    print("[music-similar] selftest: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.selftest:
        return selftest()

    index_dir = Path(args.index).expanduser()
    try:
        meta, tracks, matrix = load_index(index_dir)
    except IndexProblem as exc:
        print(f"[music-similar] {exc}", file=sys.stderr)
        return 2
    model_id, layer, window_seconds, windows = index_settings(meta)

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

    device = music_embed.pick_device(args.device)
    processor, model, rate = music_embed.load_model(model_id, device)
    recorder = music_embed.LayerRecorder(model)
    dummy = argparse.Namespace(
        window_seconds=window_seconds,
        windows=windows,
        quiet=True,
    )
    try:
        query = music_embed.embed_file(
            model, processor, str(query_path), rate, layer, dummy, recorder
        )
    finally:
        recorder.close()

    paths = [record["path"] for record in tracks]
    exclude = None if args.self else str(query_path)
    results = rank(matrix, query, args.k, paths=paths, exclude_path=exclude)
    if args.queue:
        music_dir = Path(args.music_dir).expanduser()
        if not music_dir.is_dir():
            print(
                f"[music-similar] music directory not found: {music_dir}",
                file=sys.stderr,
            )
            return 2
        queued = queue_neighbours(
            results, music_dir, args.mpc_cmd, dry_run=args.dry_run
        )
        print(
            f"[music-similar] queued {queued} of {len(results)}",
            file=sys.stderr,
        )
        return 0 if queued else 1
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
