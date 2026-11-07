#!/usr/bin/env python3
"""moss_music.py -- payload of the `moss-music` wrapper: MOSS-Music-8B analysis.

MOSS-Music is an 8B audio-language model (Qwen3-8B decoder plus a 32-layer
MOSS-Audio encoder) from the OpenMOSS team. It listens to a recording and
answers musical questions: key, tempo, beat-aligned chords with timestamps,
song structure, instrumentation, vocal type, lyrics ASR.

There is no ggml port. Checked 2026-11-07: llama.cpp's mtmd audio covers only
MiMo-Audio and Muse-Spark-Audio, audio.cpp has MOSS-TTS/transcribe families but
no music-understanding family, and the community GGUFs (scragnog, Alanine-nya)
are a separate engine's format that llama.cpp cannot load. So this payload runs
the reference PyTorch implementation. The weights are bf16 and 18.1 GB against
a 16 GB card, so CPU is the default device; `--device cuda` is only sensible
with a partial offload and is slower than CPU for a single request anyway.

Two weight directories share this loader: ``Instruct`` answers directly,
``Thinking`` reasons first (chain of thought, then the answer). ``--thinking``
switches to the second one when it is installed; the wrapper points
``$MOSS_MUSIC_MODEL`` at whatever the default directory is.

Audio is decoded to mono float32 at ``processor.config.mel_sr`` (16 kHz):
soundfile first, ffmpeg for containers libsndfile refuses (m4a, wma, some mp4).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

MOSS_BASE = os.environ.get("MOSS_MUSIC_BASE", "/zero/ai/music-ai/moss-music")

# One prompt per job. The model answers in the language it is asked in; these
# are English because that is what the published benchmarks use, and the
# wrapper passes --prompt through untouched for anything else.
PRESETS = {
    "analyze": (
        "Analyse this track for a musician. Give the key, the tempo in BPM, "
        "the chord progression with timestamps, the song structure with "
        "timestamps, the instruments you hear and the vocal type."
    ),
    "chords": (
        "Transcribe the chord progression of this track on the beat. One chord "
        "per line, each with a [mm:ss] timestamp, using standard chord symbols."
    ),
    "key": (
        "Identify the key of this track (and any key changes) and its tempo in "
        "BPM. Give the evidence for both in a few sentences."
    ),
    "structure": (
        "Label the song structure of this track (intro, verse, chorus, bridge, "
        "solo, outro) with timestamps and say what changes at each boundary."
    ),
    "lyrics": "Transcribe the lyrics of this track with [mm:ss] timestamps.",
    "theory": (
        "Act as a music theory teacher. Analyse the harmony: name the chord "
        "progression, point out the interesting moves (secondary dominants, "
        "borrowed chords, modulations) and explain why they work."
    ),
}

DEFAULT_MAX_NEW = 1024


def decode_audio(path: str, rate: int, seconds: float | None = None):
    """Mono float32 PCM at ``rate`` Hz (soundfile with a librosa resample)."""
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
        if native != rate:
            import librosa

            mono = librosa.resample(mono, orig_sr=native, target_sr=rate)
        return np.ascontiguousarray(mono, dtype=np.float32)
    except Exception:
        return _decode_ffmpeg(path, rate, seconds)


def _decode_ffmpeg(path: str, rate: int, seconds: float | None):
    """Decode through ffmpeg: containers libsndfile cannot read."""
    import numpy as np

    argv = [
        os.environ.get("FFMPEG", "ffmpeg"),
        "-hide_banner",
        "-loglevel",
        "error",
    ]
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
        done = subprocess.run(
            argv, capture_output=True, check=False, timeout=600
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"ffmpeg could not decode {path}: {exc}") from exc
    if done.returncode != 0:
        detail = done.stderr.decode(errors="replace").strip().splitlines()
        raise RuntimeError(
            f"ffmpeg failed on {path}: {detail[-1] if detail else done.returncode}"
        )
    return np.frombuffer(done.stdout, dtype="<f4").copy()


def model_class(model_path: str):
    """Load MossMusicModel from the model directory's own implementation.

    The Hugging Face config maps AutoConfig/AutoProcessor but not AutoModel, so
    ``AutoModel.from_pretrained`` cannot find the class; the reference script
    imports it from the checkout. ``get_class_from_dynamic_module`` is what
    ``trust_remote_code`` uses internally and it also resolves the sibling
    ``configuration_moss_music`` import, which a plain sys.path insert does not
    do for every copy of the file.
    """
    from transformers.dynamic_module_utils import get_class_from_dynamic_module

    try:
        return get_class_from_dynamic_module(
            "modeling_moss_music.MossMusicModel", model_path
        )
    except Exception as exc:
        # The model file imports its config relatively (`from .configuration_...`),
        # so a bare sys.path insert cannot load it. Build a throwaway package
        # around the model directory instead: that is what the dynamic loader
        # would do, minus the write into the Hugging Face modules cache.
        import importlib.util
        import types

        package = "moss_music_dynamic"
        module = types.ModuleType(package)
        module.__path__ = [model_path]
        sys.modules[package] = module
        spec = importlib.util.spec_from_file_location(
            f"{package}.modeling_moss_music",
            os.path.join(model_path, "modeling_moss_music.py"),
        )
        if spec is None or spec.loader is None:
            raise RuntimeError(
                f"cannot load MossMusicModel from {model_path}: {exc}"
            ) from exc
        loaded = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = loaded
        spec.loader.exec_module(loaded)
        return loaded.MossMusicModel


def model_config(model_path: str):
    """The checkpoint config with its audio sub-config made attribute-addressable.

    The ``configuration_moss_music.py`` shipped inside the weight directory is
    the minimal one written for SGLang: it keeps ``audio_config`` as the raw
    dict from config.json, while the PyTorch encoder reads attributes of it
    (``downsample_hidden_size``, ``output_dim``, ...). The developer
    configuration in the GitHub checkout converts the dict into a config class;
    here the same job is done with a namespace, so the published weights work
    as they are.
    """
    import types

    from transformers import AutoConfig

    config = AutoConfig.from_pretrained(model_path, trust_remote_code=True)
    audio = getattr(config, "audio_config", None)
    if isinstance(audio, dict):
        config.audio_config = types.SimpleNamespace(**audio)
    return config


def load(model_path: str, device: str):
    """Load processor + model once. Returns (processor, model)."""
    import torch
    from transformers import AutoProcessor

    cls = model_class(model_path)
    processor = AutoProcessor.from_pretrained(
        model_path, trust_remote_code=True, enable_time_marker=True
    )
    # bf16 on both devices: it is what the checkpoint holds, and on CPU it
    # halves RSS against fp32 at no quality cost.
    model = cls.from_pretrained(
        model_path,
        config=model_config(model_path),
        trust_remote_code=True,
        dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
        device_map=device,
    )
    model.eval()
    return processor, model


def analyse(processor, model, pcm, prompt: str, max_new: int, sample: bool):
    """One request: prompt + audio -> generated text (prompt tokens stripped)."""
    import torch

    inputs = processor(text=prompt, audios=[pcm], return_tensors="pt")
    # BatchFeature keeps the tensors in a dict and moves them as one group.
    inputs = inputs.to(model.device)
    if inputs.get("audio_data") is not None:
        inputs["audio_data"] = inputs["audio_data"].to(model.dtype)
    audio_token_id = getattr(processor, "audio_token_id", None)
    if audio_token_id is not None and "input_ids" in inputs:
        inputs["audio_input_mask"] = inputs["input_ids"] == audio_token_id

    generate_kwargs = {
        "max_new_tokens": max_new,
        "do_sample": sample,
        "num_beams": 1,
        "use_cache": True,
    }
    if sample:
        generate_kwargs.update({"temperature": 1.0, "top_p": 0.8, "top_k": 50})
    with torch.no_grad():
        generated = model.generate(**inputs, **generate_kwargs)
    prompt_len = inputs["input_ids"].shape[1]
    return processor.decode(
        generated[0, prompt_len:], skip_special_tokens=True
    ).strip()


def resolve_model(args) -> str:
    if args.model:
        return args.model
    if args.thinking:
        thinking = os.path.join(MOSS_BASE, "Thinking")
        if os.path.isdir(thinking):
            return thinking
        raise SystemExit(
            f"moss-music: --thinking needs {thinking}; install the Thinking weights first"
        )
    return os.environ.get("MOSS_MUSIC_MODEL") or os.path.join(
        MOSS_BASE, "Instruct"
    )


def pick_device(requested: str) -> str:
    import torch

    if requested != "auto":
        return requested
    return "cuda" if torch.cuda.is_available() else "cpu"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="moss-music",
        description="MOSS-Music-8B: key, tempo, timestamped chords, structure, instruments.",
    )
    parser.add_argument(
        "files", nargs="*", metavar="FILE", help="audio file(s) to analyse"
    )
    parser.add_argument(
        "-p",
        "--prompt",
        help="free-form question; overrides the preset",
    )
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="analyze",
        help="canned question (default: analyze)",
    )
    parser.add_argument(
        "--thinking",
        action="store_true",
        help="use the Thinking weights (chain of thought) instead of Instruct",
    )
    parser.add_argument(
        "--model", help="model directory (default: $MOSS_MUSIC_MODEL)"
    )
    parser.add_argument(
        "--device",
        default=os.environ.get("MOSS_MUSIC_DEVICE", "cpu"),
        help="cpu (default), cuda, or auto",
    )
    parser.add_argument("--max-new-tokens", type=int, default=DEFAULT_MAX_NEW)
    parser.add_argument(
        "--greedy",
        action="store_true",
        help="greedy decoding instead of the reference sampling (temperature 1.0)",
    )
    parser.add_argument(
        "--json", action="store_true", help="one JSON object per file"
    )
    parser.add_argument(
        "--list-presets",
        action="store_true",
        help="print the presets and exit",
    )
    args = parser.parse_args(argv)

    if args.list_presets:
        for name, text in sorted(PRESETS.items()):
            print(f"{name:10s} {text}")
        return 0
    if not args.files:
        parser.error("no audio file given")

    prompt = args.prompt or PRESETS[args.preset]
    model_path = resolve_model(args)
    if not os.path.isdir(model_path):
        raise SystemExit(
            f"moss-music: model directory not found: {model_path}"
        )

    device = pick_device(args.device)
    started = time.time()
    processor, model = load(model_path, device)
    print(
        f"moss-music: loaded {model_path} on {device} in {time.time() - started:.0f}s",
        file=sys.stderr,
        flush=True,
    )
    rate = int(processor.config.mel_sr)

    failures = 0
    for path in args.files:
        if not os.path.isfile(path):
            print(f"moss-music: no such file: {path}", file=sys.stderr)
            failures += 1
            continue
        began = time.time()
        pcm = decode_audio(path, rate)
        answer = analyse(
            processor,
            model,
            pcm,
            prompt,
            args.max_new_tokens,
            sample=not args.greedy,
        )
        elapsed = time.time() - began
        if args.json:
            print(
                json.dumps(
                    {
                        "file": path,
                        "model": os.path.basename(model_path.rstrip("/")),
                        "device": device,
                        "preset": args.preset,
                        "prompt": prompt,
                        "seconds_audio": round(len(pcm) / rate, 2),
                        "seconds_wall": round(elapsed, 1),
                        "text": answer,
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(
                f"=== {path} ({len(pcm) / rate:.0f}s audio, {elapsed:.0f}s on {device})"
            )
            print(answer)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
