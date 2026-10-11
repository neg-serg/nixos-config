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
import sys
from pathlib import Path

DEFAULT_MODEL = os.environ.get("MUSIC_EMBED_MODEL", "m-a-p/MERT-v1-95M")
DEFAULT_WINDOW_SECONDS = 10.0
DEFAULT_WINDOWS = 3
# Layer choice is measured, not guessed: on two same-album probes (6 and 12
# albums, 30 s clips taken from different parts of the same track) the
# second-to-last encoder layer separated same-album pairs better than the last
# one — mean margin 0.085 vs 0.052 (6 albums) and 0.046 vs 0.020 (12 albums),
# each with one more rank-1 hit.  -2 scales with the model depth, so it lands on
# the second block from the top for 24-layer checkpoints as well.
DEFAULT_LAYER = -2
# "auto" takes CUDA/ROCm as soon as torch sees a device; MUSIC_EMBED_DEVICE
# pins one globally — "cuda" once the ROCm wheel is in the venv
# (scripts/dev/music-ai-rocm.sh), or "cpu" to keep the GPU for something else.
DEFAULT_DEVICE = os.environ.get("MUSIC_EMBED_DEVICE", "auto")


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


def load_audio(path: str, rate: int, seconds: float | None = None):
    """Decode a file to mono float32 at ``rate``.

    soundfile + soxr instead of librosa: librosa pulls numba, whose JIT cache
    refuses to initialise when the package is imported from PYTHONPATH (and
    the venv tree sits outside the interpreter prefix in this setup).
    Only the requested prefix is decoded — a 12-minute track should not be
    read in full to tag or embed 30 s of it.
    """
    import soundfile as sf

    with sf.SoundFile(path) as handle:
        native = handle.samplerate
        frames = int(seconds * native) if seconds else -1
        samples = handle.read(frames, dtype="float32", always_2d=True)
    return _resample(samples.mean(axis=1), native, rate)


def read_window(path: str, rate: int, start_seconds: float, seconds: float):
    """Decode one region without touching the rest of the file."""
    import soundfile as sf

    with sf.SoundFile(path) as handle:
        native = handle.samplerate
        handle.seek(max(0, int(start_seconds * native)))
        samples = handle.read(
            int(seconds * native), dtype="float32", always_2d=True
        )
    return _resample(samples.mean(axis=1), native, rate)


def file_duration(path: str) -> float:
    """Duration in seconds, from the header only."""
    import soundfile as sf

    info = sf.info(path)
    return float(info.frames) / float(info.samplerate or 1)


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
    return embed_windows(
        model, processor, chunks, rate, layer, recorder=recorder
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
        default=DEFAULT_LAYER,
        help="hidden layer to pool (negative indexes from the top; -2 measured best)",
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
    rows = []
    try:
        for raw in args.paths:
            path = Path(raw).expanduser()
            if not path.exists():
                print(f"[music-embed] file not found: {path}", file=sys.stderr)
                return 2
            vector = embed_file(
                model, processor, str(path), rate, args.layer, args, recorder
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
