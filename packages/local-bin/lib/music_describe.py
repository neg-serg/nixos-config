#!/usr/bin/env python3
"""Rich text descriptions of a track with Music Flamingo (8B audio-language model).

Usage:
  music_describe.py [-p PROMPT] [--model ID|DIR] [--device auto|cpu|cuda]
                    [--max-new N] [--threads N] [--json] [--quiet] AUDIO...
  music_describe.py --now [--cache FILE] [--json]
  music_describe.py --dir MUSIC_DIR --out DESCRIPTIONS.jsonl
                    [--limit N] [--force] [--exclude GLOB]
  music_describe.py --tags --dir MUSIC_DIR --out TAGS.jsonl [--limit N]

``--now`` takes the track from playerctl and caches it, so the first listen of
a track costs the model run and every later one is instant.  ``--tags`` asks
for a one-line GENRES/MOODS/INSTRUMENTS answer and parses it into the same
record shape the MTG tagger writes, which is what ``music-mtg-tags
--tags FILE --playlists DIR --by mood`` expects — build the lists into their
own subdirectory, since those recipes rewrite one .m3u per label.

Single-file mode prints the answer.  Batch mode walks a music library and
appends one JSON object per track to the output file
(``{"path", "mtime", "size", "model", "prompt_sha", "text", "audio_seconds",
"generate_seconds"}``); rows whose path+mtime+size+model+prompt already match
are skipped, so an interrupted pass resumes and a re-run only describes new or
changed files.

Music Flamingo (nvidia/music-flamingo-2601-hf, NVIDIA OneWay Noncommercial
License — research use only) takes up to 20 minutes of audio in 30 s windows
and answers free-form questions about genre, tempo, key, instrumentation,
production, lyrics and cultural context.  Measured on this host (RX 9070 XT
unusable for torch, so CPU / 16 threads): 1.5-2.3 tokens/s, i.e. 1.5-2.5
minutes for a 200-250 token answer; the weights are 15.4 GiB in bf16 and load
through mmap, so a batch run pays the load once.

Audio is decoded here and handed to the processor as a float32 array: the
processor's own loader needs torchcodec for m4a (the bulk of this library) and
falls back to librosa, whose numba JIT cache cannot initialise from
PYTHONPATH.  Same soundfile -> soxr -> ffmpeg ladder as music_embed.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

# transformers imports librosa (and joblib) on the audio processors; both try
# to write caches next to the read-only venv tree and warn or fail there.
os.environ.setdefault(
    "NUMBA_CACHE_DIR",
    os.path.join(tempfile.gettempdir(), "music-describe-numba"),
)


DEFAULT_MODEL = os.environ.get(
    "MUSIC_DESCRIBE_MODEL", "nvidia/music-flamingo-2601-hf"
)
DEFAULT_DEVICE = os.environ.get("MUSIC_DESCRIBE_DEVICE", "cpu")
DEFAULT_MAX_NEW = int(os.environ.get("MUSIC_DESCRIBE_MAX_NEW", "320"))
# The card's own example prompt: it is what the model was tuned to answer.
DEFAULT_PROMPT = (
    "Describe this track in full detail - tell me the genre, tempo, and key, then dive "
    "into the instruments, production style, and overall mood it creates."
)
# Machine-readable variant: the answer is parsed into the same shape the MTG
# tagger writes, so music-mtg-tags --playlists can group tracks by it.
TAGS_PROMPT = (
    "Answer with exactly one line and nothing else: "
    "GENRES: <up to 3 comma separated lowercase genres> | "
    "MOODS: <up to 3 comma separated lowercase moods> | "
    "INSTRUMENTS: <up to 3 comma separated lowercase instruments>"
)
TAG_HEADS = ("genre", "mood", "instrument")
# One label per head, same keys as the MTG tagger's records.
DEFAULT_CACHE = os.path.expanduser(
    "~/.cache/music-describe/descriptions.jsonl"
)
AUDIO_RATE = 16000
# The processor truncates past this itself; decoding less keeps a 30-minute DJ
# set from costing 300 MB of PCM for audio the model will never see.
MAX_AUDIO_SECONDS = 1200


def _ffmpeg_binary() -> str:
    for name in ("ffmpeg",):
        path = os.environ.get(name.upper())
        if path:
            return path
    return "ffmpeg"


def _decode_ffmpeg(path: str, rate: int, seconds: float | None) -> "object":
    """Decode through ffmpeg: containers libsndfile cannot read (m4a/aac/wma)."""
    import numpy as np

    argv = [_ffmpeg_binary(), "-hide_banner", "-loglevel", "error"]
    if seconds:
        argv += ["-t", f"{seconds:g}"]
    argv += [
        "-i",
        path,
        "-vn",
        "-f",
        "f32le",
        "-acodec",
        "pcm_f32le",
        "-ac",
        "1",
        "-ar",
        str(rate),
        "-",
    ]
    try:
        completed = subprocess.run(
            argv, capture_output=True, check=False, timeout=600
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"ffmpeg could not decode {path}: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.decode(errors="replace").strip().splitlines()
        raise RuntimeError(
            f"ffmpeg failed on {path}: {detail[-1] if detail else completed.returncode}"
        )
    return np.frombuffer(completed.stdout, dtype="<f4").copy()


def decode_audio(
    path: str,
    rate: int = AUDIO_RATE,
    seconds: float | None = MAX_AUDIO_SECONDS,
):
    """Mono float32 PCM at ``rate`` Hz (soundfile first, ffmpeg as the fallback)."""
    import numpy as np

    try:
        import soundfile as sf

        with sf.SoundFile(path) as handle:
            native = handle.samplerate
            frames = -1
            if seconds:
                frames = min(int(seconds * native), len(handle))
            data = handle.read(frames, dtype="float32", always_2d=True)
        if data.size == 0:
            raise RuntimeError("empty")
        mono = data.mean(axis=1)
    except Exception:
        return _decode_ffmpeg(path, rate, seconds)
    if native != rate:
        import soxr

        mono = soxr.resample(mono, native, rate)
    return np.ascontiguousarray(mono, dtype=np.float32)


def pick_device(requested: str) -> str:
    import torch

    if requested == "auto":
        return "cuda" if torch.cuda.is_available() else "cpu"
    return requested


def load_model(model: str, device: str):
    """Load processor + model once; bf16 halves RSS versus fp32 at no quality cost."""
    import torch
    from transformers import (
        AutoProcessor,
        MusicFlamingoForConditionalGeneration,
    )

    processor = AutoProcessor.from_pretrained(model)
    dtype = (
        torch.float32
        if device == "cpu" and os.environ.get("MUSIC_DESCRIBE_FP32")
        else torch.bfloat16
    )
    mf = MusicFlamingoForConditionalGeneration.from_pretrained(
        model, dtype=dtype
    )
    mf.eval()
    # The composite config carries the audio encoder's 1200 at the top level,
    # so the generation length check warns on any track longer than ~4 minutes
    # even though the text backbone runs 32k positions. Point it at the real
    # limit instead of muting the warning.
    text_config = getattr(mf.config, "text_config", None)
    if text_config is not None and getattr(
        text_config, "max_position_embeddings", 0
    ):
        mf.config.max_position_embeddings = text_config.max_position_embeddings
    if device != "cpu":
        mf = mf.to(device)
    return processor, mf


def describe(processor, model, pcm, prompt: str, max_new: int):
    """Run one prompt over one decoded track; returns (text, stats)."""
    import torch

    messages = [
        {"role": "user", "content": "<sound>" + prompt.replace("<sound>", " ")}
    ]
    text = processor.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    t0 = time.time()
    inputs = processor(text=[text], audio=[pcm], return_tensors="pt")
    inputs["input_features"] = inputs["input_features"].to(model.dtype)
    if next(model.parameters()).device.type != "cpu":
        inputs = {k: v.to(model.device) for k, v in inputs.items()}
    preprocess_s = time.time() - t0

    t0 = time.time()
    with torch.inference_mode():
        outputs = model.generate(
            **inputs, max_new_tokens=max_new, do_sample=False
        )
    generate_s = time.time() - t0
    new_tokens = outputs.shape[1] - inputs["input_ids"].shape[1]
    answer = processor.batch_decode(
        outputs[:, inputs["input_ids"].shape[1] :], skip_special_tokens=True
    )[0].strip()
    return answer, {
        "audio_tokens": int(inputs["input_ids"].shape[1]),
        "new_tokens": int(new_tokens),
        "preprocess_seconds": round(preprocess_s, 2),
        "generate_seconds": round(generate_s, 2),
    }


def parse_tags(answer: str) -> dict:
    """Turn the one-line GENRES/MOODS/INSTRUMENTS answer into tag records.

    The shape matches the MTG tagger's JSONL (``{"genre": [{"label", "score"}]}``)
    with score 1.0 for every parsed label: the parser is the confidence there,
    not a softmax, and music-mtg-tags --playlists only reads the top label.
    A missing or unparsable line yields an empty dict rather than an error —
    the raw answer still lands in ``text``, so nothing is silently lost.
    """
    heads = {
        "genres": "genre",
        "genre": "genre",
        "moods": "mood",
        "mood": "mood",
        "instruments": "instrument",
        "instrument": "instrument",
    }
    tags: dict[str, list[dict]] = {}
    for chunk in re.split(r"[|;\n]", answer):
        name, _, value = chunk.partition(":")
        head = heads.get(name.strip().lower().strip("*"))
        if not head or not value.strip():
            continue
        labels = []
        for raw in re.split(r"[,/]", value):
            label = raw.strip().strip("-*.").strip().lower()
            label = re.sub(r"\s+", " ", label)
            if label and label not in labels:
                labels.append(label)
        if labels:
            tags.setdefault(head, []).extend(
                {"label": label, "score": 1.0} for label in labels[:3]
            )
    if tags:
        return tags
    # The model sometimes drops the labels and answers with the bare
    # "genres | moods | instruments" line it was asked for (seen on instrumental
    # techno). Trust that only when the answer has the pipe structure and short
    # fields: a prose sentence parses to nothing rather than to one giant label.
    chunks = [
        chunk.strip() for chunk in re.split(r"[|\n]", answer) if chunk.strip()
    ]
    if len(chunks) < 2 or any(len(chunk) > 40 for chunk in chunks[:3]):
        return tags
    for index, chunk in enumerate(chunks[:3]):
        labels = []
        for raw in re.split(r"[,/]", chunk):
            label = raw.strip().strip("-*. ").strip().lower()
            label = re.sub(r"\s+", " ", label)
            if label and label not in labels:
                labels.append(label)
        if labels:
            tags[TAG_HEADS[index]] = [
                {"label": label, "score": 1.0} for label in labels[:3]
            ]
    return tags


def current_track() -> str | None:
    """Path of the track the player reports (MPRIS via playerctl)."""
    try:
        completed = subprocess.run(
            ["playerctl", "metadata", "xesam:url"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    url = completed.stdout.strip()
    if completed.returncode != 0 or not url:
        return None
    return unquote(urlparse(url).path)


def _sha(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def _stat(path: Path) -> tuple[int, int]:
    st = path.stat()
    return st.st_mtime_ns, st.st_size


def _load_done(out: Path) -> dict:
    """Index of already described files, keyed by path."""
    done = {}
    if not out.exists():
        return done
    with out.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "path" in entry:
                done[entry["path"]] = entry
    return done


def selftest() -> int:
    """Offline checks of everything that does not need torch: decode + cache keys."""
    try:
        import numpy as np
        import soundfile as sf
    except (
        Exception
    ) as exc:  # noqa: BLE001 - a machine without the audio stack skips
        print(f"skip: numpy/soundfile unavailable ({exc})")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        tone = Path(tmp) / "tone.wav"
        t = np.arange(2 * AUDIO_RATE, dtype="float32") / AUDIO_RATE
        sf.write(
            tone,
            (0.1 * np.sin(2 * np.pi * 440 * t)).astype("float32"),
            AUDIO_RATE,
        )
        pcm = decode_audio(str(tone))
        if pcm.dtype.name != "float32" or abs(len(pcm) - 2 * AUDIO_RATE) > 1:
            print(f"fail: decoded {pcm.dtype} / {len(pcm)} samples")
            return 1

        # The ffmpeg rung of the ladder must report a hard failure, not silence.
        broken = Path(tmp) / "broken.wav"
        broken.write_bytes(b"not audio at all")
        try:
            decode_audio(str(broken))
        except RuntimeError:
            pass
        else:
            print("fail: corrupt input decoded without an error")
            return 1

        out = Path(tmp) / "descriptions.jsonl"
        out.write_text(
            json.dumps(
                {
                    "path": "/x",
                    "mtime": 1,
                    "size": 2,
                    "model": "m",
                    "prompt_sha": "s",
                }
            )
            + "\n"
        )
        done = _load_done(out)
        if done.get("/x", {}).get("size") != 2:
            print(f"fail: cache index lost a row ({done})")
            return 1

    if _sha("abc") != _sha("abc") or _sha("abc") == _sha("abd"):
        print("fail: prompt hashing is not stable")
        return 1

    parsed = parse_tags(
        "GENRES: Industrial Techno, Acid | MOODS: Dark | INSTRUMENTS: Synthesizer"
    )
    if [tag["label"] for tag in parsed.get("genre", [])] != [
        "industrial techno",
        "acid",
    ]:
        print(f"fail: tag parsing lost labels ({parsed})")
        return 1
    if parse_tags("no structure here"):
        print("fail: tag parsing invented labels")
        return 1
    print("ok music_describe")
    return 0


def _iter_library(root: Path, exclude: str | None):
    exts = {
        ".flac",
        ".mp3",
        ".m4a",
        ".ogg",
        ".opus",
        ".wav",
        ".aac",
        ".wma",
        ".aiff",
        ".aif",
    }
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in exts:
            continue
        if exclude and Path(path).match(exclude):
            continue
        yield path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="music-describe",
        description="Describe tracks with Music Flamingo (8B audio language model).",
    )
    parser.add_argument(
        "paths", nargs="*", help="audio files (single-file mode)"
    )
    parser.add_argument(
        "-p",
        "--prompt",
        default=DEFAULT_PROMPT,
        help="question or instruction",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"HuggingFace id or local directory (default {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--device",
        default=DEFAULT_DEVICE,
        choices=["auto", "cpu", "cuda"],
        help="cpu is the default: the ROCm path has crashed on this host before",
    )
    parser.add_argument(
        "--max-new",
        type=int,
        default=DEFAULT_MAX_NEW,
        help=f"tokens to generate (default {DEFAULT_MAX_NEW})",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=0,
        help="torch CPU threads (default: all)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="one JSON object per file on stdout",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="suppress progress on stderr"
    )
    parser.add_argument(
        "--dir", type=Path, help="batch mode: walk this music directory"
    )
    parser.add_argument(
        "--out", type=Path, help="batch mode: JSONL file to append to"
    )
    parser.add_argument(
        "--limit", type=int, default=0, help="batch mode: stop after N files"
    )
    parser.add_argument(
        "--force", action="store_true", help="batch mode: ignore the cache"
    )
    parser.add_argument("--exclude", help="batch mode: glob of paths to skip")
    parser.add_argument(
        "--tags",
        action="store_true",
        help="ask for the one-line GENRES/MOODS/INSTRUMENTS answer and parse it "
        "into a tag record (same shape as the MTG tagger)",
    )
    parser.add_argument(
        "--now",
        action="store_true",
        help="describe the track the player reports (playerctl) and cache it in "
        f"{DEFAULT_CACHE}",
    )
    parser.add_argument(
        "--cache",
        help="JSONL file to read cached descriptions from and append to "
        "(single-file mode only)",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the offline checks (no torch, no model) and exit",
    )
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()

    def log(msg: str):
        if not args.quiet:
            print(msg, file=sys.stderr, flush=True)

    # --tags swaps the free-form prompt for the machine-readable one unless the
    # caller passed their own; the answer is parsed into tag records below.
    prompt = (
        TAGS_PROMPT
        if (args.tags and args.prompt == DEFAULT_PROMPT)
        else args.prompt
    )
    cache_path = None
    if args.cache:
        cache_path = Path(args.cache).expanduser()
    elif args.now:
        cache_path = Path(DEFAULT_CACHE).expanduser()
    if args.now:
        track = current_track()
        if not track:
            print(
                "[music-describe] --now: playerctl reports no track",
                file=sys.stderr,
            )
            return 1
        args.paths = [track]

    if args.dir and not args.out:
        parser.error("--dir requires --out")
    if not args.dir and not args.paths:
        parser.error(
            "give at least one audio file, --dir with --out, or --now"
        )
    if args.threads:
        import torch

        torch.set_num_threads(args.threads)

    prompt_sha = _sha(prompt)
    todo: list[Path] = []
    done: dict = {}
    if args.dir:
        done = {} if args.force else _load_done(args.out)
        for path in _iter_library(args.dir, args.exclude):
            entry = done.get(str(path))
            mtime, size = _stat(path)
            if (
                entry
                and entry.get("mtime") == mtime
                and entry.get("size") == size
                and entry.get("model") == args.model
                and entry.get("prompt_sha") == prompt_sha
            ):
                continue
            todo.append(path)
            if args.limit and len(todo) >= args.limit:
                break
        if not todo:
            log(
                f"[music-describe] nothing to do: {args.dir} is already described"
            )
            return 0
        log(
            f"[music-describe] {len(todo)} track(s) to describe with {args.model}"
        )
    else:
        todo = [Path(p) for p in args.paths]
        if cache_path:
            done = {} if args.force else _load_done(cache_path)

    def emit(row: dict, path: Path, cached: bool = False) -> None:
        if args.json:
            print(json.dumps(row, ensure_ascii=False))
            return
        print(f"== {path}" + (" (cached)" if cached else ""))
        print(row.get("text", ""))
        if len(todo) > 1:
            print()

    def is_fresh(row: dict | None, path: Path) -> bool:
        if not row:
            return False
        try:
            mtime, size = _stat(path)
        except OSError:
            return False
        return (
            row.get("mtime") == mtime
            and row.get("size") == size
            and row.get("model") == args.model
            and row.get("prompt_sha") == prompt_sha
        )

    # Answer from the cache before touching the model: a hit must not pay the
    # 8B checkpoint's load time (that is the point of describing the playing
    # track — the first listen costs minutes, every later one is instant).
    if not args.dir and cache_path:
        pending = []
        for path in todo:
            row = done.get(str(path))
            if is_fresh(row, path):
                emit(row, path, cached=True)
            else:
                pending.append(path)
        todo = pending
        if not todo:
            log("[music-describe] served from cache")
            return 0

    device = pick_device(args.device)
    log(
        f"[music-describe] loading {args.model} on {device} (8B, this takes a moment)"
    )
    t0 = time.time()
    processor, model = load_model(args.model, device)
    log(f"[music-describe] model ready in {time.time() - t0:.1f}s")

    failures = 0
    for index, path in enumerate(todo, 1):
        try:
            t0 = time.time()
            pcm = decode_audio(str(path))
            decode_s = time.time() - t0
            answer, stats = describe(
                processor, model, pcm, prompt, args.max_new
            )
        except (
            Exception
        ) as exc:  # noqa: BLE001 - one bad file must not kill a batch
            failures += 1
            log(
                f"[music-describe] {path}: FAILED ({type(exc).__name__}: {exc})"
            )
            continue
        mtime, size = _stat(path)
        entry = {
            "path": str(path),
            "mtime": mtime,
            "size": size,
            "model": args.model,
            "prompt_sha": prompt_sha,
            "audio_seconds": round(len(pcm) / AUDIO_RATE, 2),
            "decode_seconds": round(decode_s, 2),
            "text": answer,
            **stats,
        }
        if args.tags:
            entry["engine"] = "mf"
            entry["tags"] = parse_tags(answer)
        out_file = args.out if args.dir else cache_path
        if out_file:
            out_file.parent.mkdir(parents=True, exist_ok=True)
            with out_file.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        if args.dir:
            log(
                f"[music-describe] {index}/{len(todo)} {path.name}: "
                f"{stats['new_tokens']} tok in {stats['generate_seconds']}s"
            )
        else:
            emit(entry, path)
            log(
                f"[music-describe] {stats['new_tokens']} tokens in "
                f"{stats['generate_seconds']}s ({stats['new_tokens'] / max(stats['generate_seconds'], 1e-6):.2f} tok/s)"
            )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
