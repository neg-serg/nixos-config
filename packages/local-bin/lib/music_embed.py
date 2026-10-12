#!/usr/bin/env python3
"""Music embeddings from a HuggingFace audio model (MERT by default).

Usage:
  music_embed.py [--model ID] [--layer N] [--device auto|cpu|cuda]
                 [--window-seconds S] [--windows N] [--out FILE.npy] AUDIO...

One JSON object per line is printed for every input file
(``{"path":…, "dim":…, "embedding":[…]}``); with ``--out`` the stacked
float32 matrix goes to ``FILE.npy`` instead.

Long tracks are embedded in several windows (start / middle / end) and the
window vectors are averaged: a transformer over a whole 5-minute track is
both slow and out of distribution for models trained on short contexts.

Runs inside the music-AI venv (torch + transformers + librosa); the
``music-embed`` wrapper sets PYTHONPATH/LD_LIBRARY_PATH/HF_HOME.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_MODEL = os.environ.get("MUSIC_EMBED_MODEL", "m-a-p/MERT-v1-95M")
DEFAULT_WINDOW_SECONDS = 10.0
DEFAULT_WINDOWS = 3
# Layer choice is measured, not guessed.  On same-track/different-excerpt
# probes the best layer differs per checkpoint, so it is looked up by model:
#   v1-95M  (12 layers): -2 beats the last layer (margin 0.085 vs 0.052 on 6
#           albums, 0.046 vs 0.020 on 12; 0.025 vs 0.011 on 10 albums);
#   v2-30s  (24 layers): -1 wins (rank1 0.65 / margin 0.046 vs 0.30-0.50 /
#           0.025 for the layers below it) — and v2 as a whole beats v1
#           (rank1 0.65 vs 0.50) at 1.3x the time and 2.3x the RSS.
LAYER_BY_MODEL = {
    "m-a-p/MERT-v1-95M": -2,
    "m-a-p/MERT-v2-30s": -1,
}
# Fallback for checkpoints that were not measured: second layer from the top.
DEFAULT_LAYER = -2
# "auto" takes CUDA/ROCm as soon as torch sees a device; MUSIC_EMBED_DEVICE
# pins one globally — "cuda" once the ROCm wheel is in the venv
# (scripts/dev/music-ai-rocm.sh), or "cpu" to keep the GPU for something else.
DEFAULT_DEVICE = os.environ.get("MUSIC_EMBED_DEVICE", "auto")


def resolve_layer(model_id: str, requested: int | None) -> int:
    """Layer to pool: the explicit request wins, else the measured per-model one."""
    if requested is not None:
        return int(requested)
    return LAYER_BY_MODEL.get(model_id, DEFAULT_LAYER)


def pick_device(requested: str = "auto") -> str:
    import torch

    if requested != "auto":
        return requested
    return "cuda" if torch.cuda.is_available() else "cpu"


def load_model(model_id: str, device: str):
    """Return ``(processor, model, sample_rate)`` for an audio embedding model."""
    from transformers import AutoFeatureExtractor, AutoModel

    processor = AutoFeatureExtractor.from_pretrained(
        model_id, trust_remote_code=True
    )
    model = (
        AutoModel.from_pretrained(model_id, trust_remote_code=True)
        .to(device)
        .eval()
    )
    rate = int(getattr(processor, "sampling_rate", 16000) or 16000)
    return processor, model, rate


class LayerRecorder:
    """Collect encoder layer activations with forward hooks.

    MERT's remote code drops the ``output_hidden_states`` flag on the way to
    its encoder, so layer selection reads the activations directly instead of
    fighting the config: the same trick works for any model with
    ``model.encoder.layers``.
    """

    def __init__(self, model) -> None:
        self.store: list = []
        self.handles: list = []
        layers = getattr(getattr(model, "encoder", None), "layers", None)
        for layer in layers or []:
            self.handles.append(layer.register_forward_hook(self._capture))

    def _capture(self, _module, _inputs, output) -> None:
        tensor = output[0] if isinstance(output, tuple) else output
        self.store.append(tensor.detach())

    def clear(self) -> None:
        self.store = []

    def latest(self, layer: int):
        if not self.store:
            return None
        return self.store[layer]

    def close(self) -> None:
        for handle in self.handles:
            handle.remove()
        self.handles = []


def _resample(mono, native: int, rate: int):
    if native == rate:
        return mono
    try:
        import soxr

        return soxr.resample(mono, native, rate, quality="HQ")
    except Exception:  # pragma: no cover - fallback for a missing soxr
        from math import gcd

        import numpy as np
        from scipy.signal import resample_poly

        divisor = gcd(int(native), int(rate))
        resampled = resample_poly(mono, rate // divisor, native // divisor)
        return np.asarray(resampled, dtype="float32")


def _ffmpeg_binary() -> str:
    return (
        os.environ.get("MUSIC_AI_FFMPEG") or shutil.which("ffmpeg") or "ffmpeg"
    )


def _ffprobe_binary() -> str:
    return (
        os.environ.get("MUSIC_AI_FFPROBE")
        or shutil.which("ffprobe")
        or "ffprobe"
    )


def _ffmpeg_pcm(
    path: str, rate: int, start_seconds: float, seconds: float | None
):
    """Decode a region with ffmpeg (mp4/m4a/wma/… that libsndfile cannot read)."""
    import numpy as np

    argv = [_ffmpeg_binary(), "-hide_banner", "-loglevel", "error"]
    if start_seconds:
        argv += ["-ss", f"{start_seconds:g}"]
    if seconds:
        argv += ["-t", f"{seconds:g}"]
    argv += [
        "-i",
        path,
        "-vn",
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-ac",
        "1",
        "-ar",
        str(rate),
        "-",
    ]
    try:
        completed = subprocess.run(
            argv, capture_output=True, check=False, timeout=300
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"ffmpeg could not decode {path}: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.decode(errors="replace").strip().splitlines()
        raise RuntimeError(
            f"ffmpeg failed on {path}: {detail[-1] if detail else completed.returncode}"
        )
    pcm = np.frombuffer(completed.stdout, dtype="<i2")
    return (
        (pcm.astype("float32") / 32768.0)
        if pcm.size
        else pcm.astype("float32")
    )


def _ffprobe_duration(path: str) -> float:
    completed = subprocess.run(
        [
            _ffprobe_binary(),
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "csv=p=0",
            path,
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    try:
        return float(completed.stdout.strip())
    except ValueError:
        return 0.0


def load_audio(path: str, rate: int, seconds: float | None = None):
    """Decode a file to mono float32 at ``rate``.

    soundfile + soxr instead of librosa: librosa pulls numba, whose JIT cache
    refuses to initialise when the package is imported from PYTHONPATH (and
    the venv tree sits outside the interpreter prefix in this setup).
    Only the requested prefix is decoded — a 12-minute track should not be
    read in full to tag or embed 30 s of it. Formats libsndfile cannot read
    (m4a/aac/wma) go through ffmpeg; that gap cost 1062 tracks of a 37k
    library its index entry before it was noticed.
    """
    import soundfile as sf

    try:
        with sf.SoundFile(path) as handle:
            native = handle.samplerate
            frames = int(seconds * native) if seconds else -1
            samples = handle.read(frames, dtype="float32", always_2d=True)
    except (RuntimeError, sf.LibsndfileError):
        return _ffmpeg_pcm(path, rate, 0.0, seconds)
    return _resample(samples.mean(axis=1), native, rate)


def read_window(path: str, rate: int, start_seconds: float, seconds: float):
    """Decode one region without touching the rest of the file."""
    import soundfile as sf

    try:
        with sf.SoundFile(path) as handle:
            native = handle.samplerate
            handle.seek(max(0, int(start_seconds * native)))
            samples = handle.read(
                int(seconds * native), dtype="float32", always_2d=True
            )
    except (RuntimeError, sf.LibsndfileError):
        return _ffmpeg_pcm(path, rate, start_seconds, seconds)
    if samples.size == 0 and start_seconds > 0:
        # A truncated file still reports its nominal length in the header, but
        # the audio past the cut is garbage: the tail window decodes to nothing
        # and MERT then dies in conv1d ("padded input size 0"), which cost 61
        # mp3 files their index entry.  Retry from the start instead.
        return read_window(path, rate, 0.0, seconds)
    return _resample(samples.mean(axis=1), native, rate)


def file_duration(path: str) -> float:
    """Duration in seconds, from the header only (ffprobe as the fallback)."""
    import soundfile as sf

    try:
        info = sf.info(path)
        return float(info.frames) / float(info.samplerate or 1)
    except (RuntimeError, sf.LibsndfileError):
        return _ffprobe_duration(path)


def window_starts(path: str, seconds: float, count: int) -> list[float]:
    """Evenly spaced window offsets (start/middle/end) for a track."""
    import numpy as np

    duration = file_duration(path)
    if count <= 1 or duration <= seconds:
        return [0.0]
    if count == 2:
        return [0.0, duration - seconds]
    return [float(x) for x in np.linspace(0.0, duration - seconds, count)]


def windows(samples, rate: int, seconds: float, count: int):
    """Evenly spaced analysis windows over the track (one if it is short)."""
    import numpy as np

    span = int(seconds * rate)
    if len(samples) <= span or count <= 1:
        return [samples]
    if count == 2:
        starts = [0, len(samples) - span]
    else:
        starts = np.linspace(0, len(samples) - span, count).astype(int)
    return [samples[start : start + span] for start in starts]


def embed_windows(
    model, processor, chunks, rate: int, layer: int, recorder=None
):
    """Mean-pooled, L2-normalised embedding for each window."""
    import numpy as np
    import torch

    vectors = []
    for chunk in chunks:
        inputs = processor(chunk, sampling_rate=rate, return_tensors="pt")
        inputs = {k: v.to(model.device) for k, v in inputs.items()}
        if recorder is not None:
            recorder.clear()
        with torch.no_grad():
            outputs = model(**inputs, output_hidden_states=True)
        hidden = None
        if recorder is not None:
            hidden = recorder.latest(layer)
        if hidden is None:
            hidden = outputs.last_hidden_state
        vector = hidden.mean(dim=1)[0].float().cpu().numpy()
        vectors.append(vector)
    stacked = np.stack(vectors).mean(axis=0)
    norm = float(np.linalg.norm(stacked))
    return (stacked / (norm + 1e-8)).astype(np.float32)


def embed_file(
    model, processor, path: str, rate: int, layer: int, args, recorder=None
):
    starts = window_starts(path, args.window_seconds, args.windows)
    chunks = [
        read_window(path, rate, start, args.window_seconds) for start in starts
    ]
    usable = [c for c in chunks if len(c) >= rate // 10]
    if not usable:
        raise RuntimeError(
            f"no decodable audio in {path} (corrupt or empty file?)"
        )
    return embed_windows(
        model, processor, usable, rate, layer, recorder=recorder
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("paths", nargs="+", help="audio files")
    parser.add_argument(
        "--model", default=DEFAULT_MODEL, help="HuggingFace id"
    )
    parser.add_argument(
        "--layer",
        type=int,
        default=None,
        help=(
            "hidden layer to pool (negative indexes from the top); default is "
            "per model — -2 for MERT-v1, -1 for MERT-v2 (both measured)"
        ),
    )
    parser.add_argument(
        "--device", default=DEFAULT_DEVICE, help="auto|cpu|cuda"
    )
    parser.add_argument(
        "--window-seconds", type=float, default=DEFAULT_WINDOW_SECONDS
    )
    parser.add_argument("--windows", type=int, default=DEFAULT_WINDOWS)
    parser.add_argument("--out", help="write the stacked matrix to FILE.npy")
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    import numpy as np

    device = pick_device(args.device)
    if not args.quiet:
        print(
            f"[music-embed] {args.model} on {device}",
            file=sys.stderr,
        )
    processor, model, rate = load_model(args.model, device)
    recorder = LayerRecorder(model)
    layer = resolve_layer(args.model, args.layer)
    if not args.quiet:
        print(f"[music-embed] layer {layer}", file=sys.stderr)
    rows = []
    try:
        for raw in args.paths:
            path = Path(raw).expanduser()
            if not path.exists():
                print(f"[music-embed] file not found: {path}", file=sys.stderr)
                return 2
            vector = embed_file(
                model, processor, str(path), rate, layer, args, recorder
            )
            rows.append(vector)
            if not args.quiet:
                print(
                    f"[music-embed] {path.name}: dim {vector.shape[0]}",
                    file=sys.stderr,
                )
            if not args.out:
                print(
                    json.dumps(
                        {
                            "path": str(path),
                            "dim": int(vector.shape[0]),
                            "model": args.model,
                            "embedding": [round(float(x), 6) for x in vector],
                        }
                    )
                )
    finally:
        recorder.close()
    if args.out:
        np.save(args.out, np.stack(rows))
        if not args.quiet:
            print(
                f"[music-embed] wrote {args.out} ({len(rows)}x{rows[0].shape[0]})",
                file=sys.stderr,
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
