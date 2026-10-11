#!/usr/bin/env python3
"""Build a similarity index for a music library from model embeddings.

Usage: music_index.py [--out DIR] [--model ID] [--layer N] [-j N] [MUSIC_DIR]

The index is plain numpy — for a library of a few thousand tracks a brute
force cosine search is milliseconds, so there is no Annoy/BLAS dependency to
install and no separate index build step beyond the embedding pass:

  INDEX/vectors.npy   float32 (N, D), L2-normalised rows
  INDEX/tracks.jsonl  one {"path", "mtime", "size", "vector_index"} per line
  INDEX/meta.json     model, layer, device, window_seconds, windows,
                      signature, dim, count, created
  INDEX/cache/*.npy   per-file vectors, keyed by path+mtime+size+signature

The cache key folds in a short signature hash of the four embedding settings
(model, layer, window_seconds, windows), so switching any of them re-embeds
instead of silently reusing vectors built with other settings. Cache files
written by older versions (keyed without the signature) are left alone and
simply ignored, except when meta.json proves that the old cache belongs to
the current settings: those vectors are then copied to the signature key
(the old file is kept — a concurrently running older build still reads it),
so existing work survives the upgrade without ever mixing settings.

Re-running skips files whose cached vector matches the current key, so an
interrupted pass resumes cheaply.

--selftest runs the whole pipeline offline against a deterministic stub
embedder (no torch, no model, no venv); the parts that need numpy are skipped
with a printed notice when numpy is unavailable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import music_embed  # noqa: E402  (same directory, wrapper sets PYTHONPATH)

AUDIO_EXTS = {".mp3", ".flac", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".wma"}
DEFAULT_INDEX = Path.home() / ".cache" / "music-index"
SETTINGS_KEYS = ("model", "layer", "window_seconds", "windows")
PROGRESS_EVERY = 25
STUB_DIM = 16

_WORKER: dict = {}


class IndexProblem(Exception):
    """Index missing, inconsistent or built with other settings."""


def embed_signature(
    model: str, layer: int, window_seconds: float, windows: int
) -> str:
    """Short hash of the settings that decide the embedding values."""
    settings = (str(model), int(layer), float(window_seconds), int(windows))
    return hashlib.sha1(repr(settings).encode()).hexdigest()[:12]


def file_key(path: Path, signature: str) -> str:
    """Cache key: path + mtime + size + signature (any change re-embeds)."""
    stat = path.stat()
    raw = f"{path}:{stat.st_mtime_ns}:{stat.st_size}:{signature}"
    return hashlib.sha1(raw.encode()).hexdigest()


def legacy_file_key(path: Path) -> str:
    """Cache key used before embed signatures existed (no settings folded in)."""
    stat = path.stat()
    raw = f"{path}:{stat.st_mtime_ns}:{stat.st_size}"
    return hashlib.sha1(raw.encode()).hexdigest()


def stub_embed(path: str, dim: int = STUB_DIM) -> list[float]:
    """Deterministic hash-based unit vector for --selftest (no torch)."""
    stat = Path(path).stat()
    digest = hashlib.shake_128(f"{Path(path).name}:{stat.st_size}".encode())
    values = [((byte * 2) - 255) / 255.0 for byte in digest.digest(dim)]
    scale = sum(value * value for value in values) ** 0.5 or 1.0
    return [value / scale for value in values]


def scan(root: Path, exts: set[str]) -> list[Path]:
    files = [
        item
        for item in sorted(root.rglob("*"))
        if item.is_file() and item.suffix.lower() in exts
    ]
    return files


def _set_threads(threads: int) -> None:
    """Cap torch's CPU threads when --threads N > 0 is given."""
    if threads > 0:
        import torch

        torch.set_num_threads(threads)


def _worker_init(
    model: str, layer: int, device: str, args: dict, threads: int = 0
) -> None:
    _set_threads(threads)
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


def write_index(
    out_dir: Path, records: list[dict], vectors: Any, meta: dict
) -> None:
    """Write vectors.npy, tracks.jsonl and meta.json into ``out_dir``."""
    import numpy as np

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    np.save(out_dir / "vectors.npy", np.asarray(vectors, dtype=np.float32))
    with open(out_dir / "tracks.jsonl", "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    with open(out_dir / "meta.json", "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)


def index_settings(meta: dict) -> tuple[str, int, float, int]:
    """Embedding settings an index was built with (raises IndexProblem)."""
    missing = [key for key in SETTINGS_KEYS if key not in meta]
    if missing:
        raise IndexProblem(
            "index meta.json is missing embed settings "
            f"({', '.join(missing)}); rebuild with music-index"
        )
    return (
        str(meta["model"]),
        int(meta["layer"]),
        float(meta["window_seconds"]),
        int(meta["windows"]),
    )


def index_signature(meta: dict) -> str:
    """Signature the index must have for its own recorded settings.

    Indexes built before signatures existed still record all four settings,
    so their signature can be derived exactly; a recorded signature that
    disagrees with the settings is a mismatch and raises IndexProblem.
    """
    model, layer, window_seconds, windows = index_settings(meta)
    expected = embed_signature(model, layer, window_seconds, windows)
    recorded = meta.get("signature")
    if recorded and recorded != expected:
        raise IndexProblem(
            f"index signature {recorded} does not match its settings "
            f"({expected}); rebuild with music-index"
        )
    return expected


def load_index(index_dir: Path) -> tuple[dict, list[dict], Any]:
    """Load meta/tracks/vectors, refusing missing or incompatible indexes."""
    import numpy as np

    index_dir = Path(index_dir)
    vectors_path = index_dir / "vectors.npy"
    tracks_path = index_dir / "tracks.jsonl"
    if not vectors_path.exists() or not tracks_path.exists():
        raise IndexProblem(
            f"no index in {index_dir}; build it with music-index"
        )
    meta_path = index_dir / "meta.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    matrix = np.load(vectors_path)
    tracks = [
        json.loads(line)
        for line in tracks_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if matrix.ndim != 2 or matrix.shape[0] != len(tracks):
        raise IndexProblem(
            f"inconsistent index in {index_dir} "
            f"({matrix.shape[0]} vectors, {len(tracks)} tracks); "
            "rebuild with music-index"
        )
    if "count" in meta and int(meta["count"]) != matrix.shape[0]:
        raise IndexProblem(
            f"index meta.json says {meta['count']} tracks but holds "
            f"{matrix.shape[0]}; rebuild with music-index"
        )
    if "dim" in meta and int(meta["dim"]) != matrix.shape[1]:
        raise IndexProblem(
            f"index meta.json says {meta['dim']} dims but holds "
            f"{matrix.shape[1]}; rebuild with music-index"
        )
    index_signature(meta)
    return meta, tracks, matrix


def read_meta(out_dir: Path) -> dict | None:
    """meta.json as a dict, or None when it is absent or unreadable."""
    meta_path = Path(out_dir) / "meta.json"
    if not meta_path.exists():
        return None
    try:
        return json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def audit_index(root: Path, out_dir: Path, limit: int = 20) -> int:
    """List the scanned files that are not in the index (no embedding).

    A finished build can be short of the scanned file count: unreadable or
    exotic files are skipped while the pass continues. This reports exactly
    which ones, so the gaps are known instead of guessed.
    """
    try:
        meta, tracks, _matrix = load_index(out_dir)
    except IndexProblem as exc:
        print(f"[music-index] {exc}", file=sys.stderr)
        return 2
    indexed = {record["path"] for record in tracks}
    scanned = [str(path) for path in scan(root, AUDIO_EXTS)]
    missing = [path for path in scanned if path not in indexed]
    print(
        f"[music-index] audit: {len(indexed)} indexed, {len(scanned)} scanned, "
        f"{len(missing)} missing (index built {meta.get('created', '?')})"
    )
    for path in missing[:limit]:
        print(path)
    if len(missing) > limit:
        print(f"... and {len(missing) - limit} more")
    return 0


def legacy_settings_match(
    out_dir: Path, model: str, layer: int, window_seconds: float, windows: int
) -> bool:
    """True when meta.json attributes the legacy cache to these settings.

    Without meta.json (or with any of the four settings missing/different)
    the pre-signature cache cannot be attributed, so nothing is migrated.
    """
    meta_path = out_dir / "meta.json"
    if not meta_path.exists():
        return False
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    try:
        recorded = index_settings(meta)
    except IndexProblem:
        return False
    wanted = (str(model), int(layer), float(window_seconds), int(windows))
    return recorded == wanted


def migrate_legacy_vector(path: Path, cache_file: Path) -> bool:
    """Copy a pre-signature cache entry to its signature key, if usable.

    Copies instead of renaming so an older music-index process still running
    keeps finding its entries under the legacy name. Returns True when the
    new key was written; a missing or unreadable entry just returns False and
    the caller re-embeds that file.
    """
    legacy_file = cache_file.parent / f"{legacy_file_key(path)}.npy"
    if not legacy_file.exists():
        return False
    partial = cache_file.with_name(cache_file.name + ".part.npy")
    try:
        import numpy as np

        vector = np.load(legacy_file)
        np.save(partial, np.asarray(vector, dtype=np.float32))
        partial.replace(cache_file)
    except Exception:
        partial.unlink(missing_ok=True)
        return False
    return True


def _print_progress(done: int, total: int, started: float) -> None:
    """Progress line for long builds: elapsed, rate and rough ETA."""
    elapsed = max(time.time() - started, 1e-9)
    rate = done / elapsed
    remaining = max(total - done, 0) / rate if rate > 0 else 0.0
    eta = time.strftime("%H:%M:%S", time.gmtime(remaining))
    print(
        f"[music-index] {done}/{total} files, {elapsed:.1f}s elapsed, "
        f"{rate:.2f} files/s, ETA {eta}",
        file=sys.stderr,
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=str(Path.home() / "music"))
    parser.add_argument("--out", default=str(DEFAULT_INDEX), help="index dir")
    parser.add_argument("--model", default=music_embed.DEFAULT_MODEL)
    parser.add_argument(
        "--layer",
        type=int,
        default=None,
        help=(
            "hidden layer to pool; default is per model (-2 for MERT-v1, "
            "-1 for MERT-v2, both measured) and is part of the signature"
        ),
    )
    parser.add_argument("--device", default="auto")
    parser.add_argument(
        "--window-seconds",
        type=float,
        default=music_embed.DEFAULT_WINDOW_SECONDS,
    )
    parser.add_argument(
        "--windows", type=int, default=music_embed.DEFAULT_WINDOWS
    )
    parser.add_argument(
        "-j", "--jobs", type=int, default=1, help="parallel workers"
    )
    parser.add_argument(
        "-n", "--limit", type=int, help="only the first N files"
    )
    parser.add_argument(
        "--rebuild", action="store_true", help="ignore the cache"
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=0,
        help="torch CPU threads for embedding (0 = torch default)",
    )
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument(
        "--adopt-legacy",
        action="store_true",
        help=(
            "trust pre-signature cache entries (no meta.json signature) as if "
            "they were built with the current settings; use it when a build "
            "started before the signature existed"
        ),
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the offline stub-embedder self-check and exit",
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help=(
            "report which scanned files are missing from the existing index "
            "(no embedding) and exit"
        ),
    )
    parser.add_argument(
        "--audit-limit",
        type=int,
        default=20,
        help="how many missing paths --audit prints (default 20)",
    )
    return parser.parse_args(argv)


def build_index(
    root: Path,
    out_dir: Path,
    *,
    model: str,
    layer: int,
    window_seconds: float,
    windows: int,
    device: str = "auto",
    jobs: int = 1,
    limit: int | None = None,
    rebuild: bool = False,
    quiet: bool = False,
    threads: int = 0,
    adopt_legacy: bool = False,
    embed=None,
) -> int:
    """Embed every audio file under ``root`` and write the index.

    ``embed`` overrides the model with a plain callable (used by --selftest);
    with it no model/device/thread setup happens. Returns an exit code.
    """
    import numpy as np

    root = Path(root).expanduser()
    if not root.is_dir():
        print(f"[music-index] not a directory: {root}", file=sys.stderr)
        return 2
    out_dir = Path(out_dir).expanduser()
    cache_dir = out_dir / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    signature = embed_signature(model, layer, window_seconds, windows)

    # Building with different settings than the index on disk means re-embedding
    # every file — for a real library that is hours, so say it out loud before
    # the pass starts (and how to keep the old index instead).
    existing_meta = read_meta(out_dir)
    if existing_meta and not rebuild:
        try:
            recorded = index_settings(existing_meta)
        except IndexProblem:
            recorded = None
        wanted = (str(model), int(layer), float(window_seconds), int(windows))
        if recorded and recorded != wanted:
            print(
                "[music-index] WARNING: the index in "
                f"{out_dir} was built with model={recorded[0]} layer={recorded[1]} "
                f"window_seconds={recorded[2]:g} windows={recorded[3]}; the current "
                "settings differ, so every file will be re-embedded. Re-run with "
                f"--model {recorded[0]} --layer {recorded[1]} "
                f"--window-seconds {recorded[2]:g} --windows {recorded[3]} "
                "to keep it, or pass --adopt-legacy to reuse its cache.",
                file=sys.stderr,
            )

    files = scan(root, AUDIO_EXTS)
    if limit:
        files = files[:limit]
    if not files:
        print(f"[music-index] no audio files under {root}", file=sys.stderr)
        return 2
    if embed is None:
        device = music_embed.pick_device(device)
        _set_threads(threads)
    else:
        device = "stub"
    if not quiet:
        print(
            f"[music-index] {len(files)} files, {model} on {device}",
            file=sys.stderr,
        )

    # Pre-signature entries are only trustworthy when meta.json attributes
    # the cache to the current settings; --rebuild always re-embeds.
    # --adopt-legacy asserts that trust by hand: useful when a run started
    # before the signature existed and its cache should not be thrown away.
    can_migrate = not rebuild and (
        adopt_legacy
        or legacy_settings_match(
            out_dir, model, layer, window_seconds, windows
        )
    )
    if adopt_legacy and not quiet:
        print(
            "[music-index] --adopt-legacy: treating pre-signature cache "
            f"entries as if built with model={model} layer={layer} "
            f"window_seconds={window_seconds:g} windows={windows}",
            file=sys.stderr,
        )
    pending: list[tuple[Path, Path]] = []
    migrated = 0
    for path in files:
        cache_file = cache_dir / f"{file_key(path, signature)}.npy"
        if not rebuild and cache_file.exists():
            continue
        if can_migrate and migrate_legacy_vector(path, cache_file):
            migrated += 1
            continue
        pending.append((path, cache_file))
    if migrated and not quiet:
        print(
            f"[music-index] migrated {migrated} cached vectors "
            "from the pre-signature key",
            file=sys.stderr,
        )

    started = time.time()
    done = 0
    if pending:
        pool = None
        if embed is None and jobs > 1:
            try:
                pool = ProcessPoolExecutor(
                    max_workers=jobs,
                    initializer=_worker_init,
                    initargs=(
                        model,
                        layer,
                        device,
                        {
                            "window_seconds": window_seconds,
                            "windows": windows,
                            "quiet": True,
                        },
                        threads,
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
            if embed is None and pool is None:
                _worker_init(
                    model,
                    layer,
                    device,
                    {
                        "window_seconds": window_seconds,
                        "windows": windows,
                        "quiet": True,
                    },
                    threads,
                )
            for path, cache_file in pending:
                try:
                    if embed is not None:
                        values = embed(str(path))
                    elif pool is None:
                        values = _worker_embed(str(path))
                    else:
                        values = pool.submit(_worker_embed, str(path)).result()
                except Exception as exc:  # keep the pass going on bad files
                    print(f"[music-index] skip {path}: {exc}", file=sys.stderr)
                    continue
                np.save(cache_file, np.asarray(values, dtype=np.float32))
                done += 1
                if not quiet and done % PROGRESS_EVERY == 0:
                    _print_progress(done, len(pending), started)
        finally:
            if pool is not None:
                pool.shutdown()

    rows, records = [], []
    for path in files:
        cache_file = cache_dir / f"{file_key(path, signature)}.npy"
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
    meta = {
        "model": model,
        "layer": layer,
        "device": device,
        "window_seconds": window_seconds,
        "windows": windows,
        "signature": signature,
        "dim": int(matrix.shape[1]),
        "count": int(matrix.shape[0]),
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    write_index(out_dir, records, matrix, meta)
    if not quiet:
        print(
            f"[music-index] {matrix.shape[0]} tracks x {matrix.shape[1]} dims "
            f"-> {out_dir} ({done} new, {time.time() - started:.1f}s)",
            file=sys.stderr,
        )
    return 0


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(f"music-index selftest: {message}")


def selftest() -> int:
    """Offline self-check with a stub embedder (see module docstring)."""
    import contextlib
    import io
    import tempfile

    signature = embed_signature("stub/model", -2, 10.0, 3)
    variants = [
        embed_signature("other/model", -2, 10.0, 3),
        embed_signature("stub/model", -1, 10.0, 3),
        embed_signature("stub/model", -2, 5.0, 3),
        embed_signature("stub/model", -2, 10.0, 1),
    ]
    _check(len({signature, *variants}) == 5, "signature ignores a setting")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "a.flac"
        path.write_bytes(b"")
        keys = {file_key(path, item) for item in [signature, *variants]}
        _check(len(keys) == 5, "cache key does not fold in the signature")
        vector = stub_embed(str(path))
        _check(vector == stub_embed(str(path)), "stub embedder is unstable")
        _check(len(vector) == STUB_DIM, "stub embedder has the wrong dim")
        _check(
            abs(sum(value * value for value in vector) - 1.0) < 1e-9,
            "stub embedder is not a unit vector",
        )
    try:
        import numpy as np
    except ImportError:
        print("[music-index] selftest: skipped (numpy missing)")
        return 0

    settings = {
        "model": "stub/model",
        "layer": -2,
        "window_seconds": 10.0,
        "windows": 3,
    }
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "music"
        out_dir = Path(tmp) / "index"
        cache_dir = out_dir / "cache"
        cache_dir.mkdir(parents=True)
        root.mkdir()
        legacy_names = []
        for name in ("a", "b", "c"):
            file = root / f"{name}.flac"
            file.write_bytes(b"")
            stat = file.stat()
            legacy = hashlib.sha1(
                f"{file}:{stat.st_mtime_ns}:{stat.st_size}".encode()
            ).hexdigest()
            (cache_dir / f"{legacy}.npy").write_bytes(b"legacy")
            legacy_names.append(legacy)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = build_index(root, out_dir, embed=stub_embed, **settings)
        _check(rc == 0, "build_index failed")
        _check(
            "3 new" in stderr.getvalue(), "first pass did not embed 3 files"
        )
        _check(
            "migrated" not in stderr.getvalue(),
            "legacy cache migrated without meta.json",
        )
        for legacy in legacy_names:
            _check(
                (cache_dir / f"{legacy}.npy").read_bytes() == b"legacy",
                "an old cache file was deleted or overwritten",
            )
        meta, tracks, matrix = load_index(out_dir)
        _check(matrix.shape == (3, STUB_DIM), f"bad matrix {matrix.shape}")
        _check(len(tracks) == 3, "bad track records")
        _check(int(meta["count"]) == 3, "bad count in meta")
        _check(int(meta["dim"]) == STUB_DIM, "bad dim in meta")
        _check(
            meta["signature"] == embed_signature(**settings),
            "meta signature does not match the settings",
        )
        _check(
            meta["model"] == settings["model"]
            and int(meta["layer"]) == settings["layer"]
            and float(meta["window_seconds"]) == settings["window_seconds"]
            and int(meta["windows"]) == settings["windows"],
            "meta does not record the settings",
        )
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = build_index(root, out_dir, embed=stub_embed, **settings)
        _check(rc == 0, "cached rebuild failed")
        _check("0 new" in stderr.getvalue(), "re-run did not reuse the cache")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = build_index(
                root,
                out_dir,
                embed=stub_embed,
                **{**settings, "windows": 1},
            )
        _check(rc == 0, "rebuild after a settings change failed")
        _check(
            "3 new" in stderr.getvalue(),
            "a settings change reused cached vectors",
        )

        # Legacy cache + matching meta.json: the vectors are copied under the
        # signature key instead of being re-embedded, and the legacy file is
        # kept for a concurrently running older build.
        legacy_root = Path(tmp) / "legacy-music"
        legacy_out = Path(tmp) / "legacy-index"
        legacy_root.mkdir()
        legacy_cache = legacy_out / "cache"
        legacy_cache.mkdir(parents=True)
        original = {}
        for name in ("a", "b", "c"):
            file = legacy_root / f"{name}.flac"
            file.write_bytes(b"")
            vector = np.asarray(stub_embed(str(file)), dtype=np.float32)
            original[file] = vector
            np.save(legacy_cache / f"{legacy_file_key(file)}.npy", vector)
        (legacy_out / "meta.json").write_text(json.dumps(settings))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = build_index(
                legacy_root, legacy_out, embed=stub_embed, **settings
            )
        _check(rc == 0, "build with a matching legacy cache failed")
        output = stderr.getvalue()
        _check(
            "migrated 3 cached vectors" in output,
            "matching legacy cache was not migrated",
        )
        _check("0 new" in output, "migration did not reuse the cache")
        _check("3 new" not in output, "migration re-embedded anyway")
        for file, vector in original.items():
            _check(
                (legacy_cache / f"{legacy_file_key(file)}.npy").exists(),
                "migration deleted a legacy cache file",
            )
            migrated = np.load(
                legacy_cache
                / f"{file_key(file, embed_signature(**settings))}.npy"
            )
            _check(
                np.allclose(migrated, vector),
                "migrated vector differs from the legacy one",
            )

        # Legacy cache + meta.json with other settings: no attribution, so
        # the files must be re-embedded.
        mismatch_root = legacy_root
        mismatch_out = Path(tmp) / "mismatch-index"
        mismatch_cache = mismatch_out / "cache"
        mismatch_cache.mkdir(parents=True)
        for file in original:
            np.save(
                mismatch_cache / f"{legacy_file_key(file)}.npy", original[file]
            )
        mismatch = {**settings, "windows": 1}
        (mismatch_out / "meta.json").write_text(json.dumps(mismatch))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rc = build_index(
                mismatch_root, mismatch_out, embed=stub_embed, **settings
            )
        _check(rc == 0, "build with a mismatching meta.json failed")
        output = stderr.getvalue()
        _check("migrated" not in output, "mismatching meta migrated cache")
        _check("3 new" in output, "mismatching meta did not re-embed")
    try:
        index_signature({"model": "incomplete"})
    except IndexProblem:
        pass
    else:
        _check(False, "incomplete meta was accepted")
    print("[music-index] selftest: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.selftest:
        return selftest()
    if args.audit:
        return audit_index(
            Path(args.root).expanduser(),
            Path(args.out).expanduser(),
            limit=args.audit_limit,
        )
    return build_index(
        Path(args.root).expanduser(),
        Path(args.out).expanduser(),
        model=args.model,
        layer=music_embed.resolve_layer(args.model, args.layer),
        window_seconds=args.window_seconds,
        windows=args.windows,
        device=args.device,
        jobs=args.jobs,
        limit=args.limit,
        rebuild=args.rebuild,
        quiet=args.quiet,
        threads=args.threads,
        adopt_legacy=args.adopt_legacy,
    )


if __name__ == "__main__":
    raise SystemExit(main())
