#!/usr/bin/env python3
"""Zero-shot music tagging with CLAP (text labels against one audio file).

Usage:
  music_tags.py [--model laion/clap-htsat-unfused] [--labels a,b,c]
                [--top N] [--json] AUDIO

The default label set mixes genres, moods and instrumentation so a single run
answers "what is this".  Labels are free text: CLAP matches them against the
audio embedding, and the reported score is a softmax over the given labels
(comparable inside one run, not across runs with different label sets).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_MODEL = os.environ.get("MUSIC_TAGS_MODEL", "laion/clap-htsat-unfused")
DEFAULT_LABELS = (
    "ambient",
    "drone",
    "black metal",
    "doom metal",
    "death metal",
    "post-rock",
    "idm",
    "breakbeat",
    "techno",
    "house",
    "drum and bass",
    "hip hop",
    "jazz",
    "classical",
    "folk",
    "pop",
    "punk",
    "singer-songwriter",
    "field recording",
    "soundtrack",
    "melancholic",
    "aggressive",
    "calm",
    "happy",
    "dark",
    "epic",
    "instrumental",
    "female vocal",
    "male vocal",
    "choir",
)


def load_audio(path: str, rate: int, seconds: float = 30.0):
    """Decode (see music_embed.load_audio) — same loader as the embedder."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from music_embed import load_audio as _load

    return _load(path, rate, seconds)


def _embedding(output):
    """Pull the projected embedding out of a model output (transformers 4/5)."""
    if hasattr(output, "pooler_output") and output.pooler_output is not None:
        return output.pooler_output
    if hasattr(output, "last_hidden_state"):
        return output.last_hidden_state.mean(dim=1)
    return output


def score_labels(model, processor, samples, labels: list[str], rate: int):
    """Softmax over cosine similarity of audio vs each label."""
    import torch

    audio_inputs = processor(
        audio=samples, sampling_rate=rate, return_tensors="pt"
    )
    text_inputs = processor(text=labels, return_tensors="pt", padding=True)
    audio_inputs = {k: v.to(model.device) for k, v in audio_inputs.items()}
    text_inputs = {k: v.to(model.device) for k, v in text_inputs.items()}
    with torch.no_grad():
        audio_embed = _embedding(model.get_audio_features(**audio_inputs))
        text_embed = _embedding(model.get_text_features(**text_inputs))
    audio_embed = audio_embed / audio_embed.norm(dim=-1, keepdim=True)
    text_embed = text_embed / text_embed.norm(dim=-1, keepdim=True)
    scale = (
        float(getattr(model, "logit_scale_a", None).exp())
        if hasattr(model, "logit_scale_a")
        else 100.0
    )
    logits = (audio_embed @ text_embed.T)[0] * scale
    probs = logits.softmax(dim=-1)
    return probs.tolist()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("audio", help="audio file to tag")
    parser.add_argument(
        "--model", default=DEFAULT_MODEL, help="HuggingFace id"
    )
    parser.add_argument(
        "--labels", help="comma separated labels (default: built-in set)"
    )
    parser.add_argument(
        "--top", type=int, default=10, help="how many to print"
    )
    parser.add_argument(
        "--seconds", type=float, default=30.0, help="clip length"
    )
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument("--device", default="auto", help="auto|cpu|cuda")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    import torch

    device = args.device
    if device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    labels = (
        [label.strip() for label in args.labels.split(",") if label.strip()]
        if args.labels
        else list(DEFAULT_LABELS)
    )
    from transformers import ClapModel, ClapProcessor

    processor = ClapProcessor.from_pretrained(args.model)
    model = ClapModel.from_pretrained(args.model).to(device).eval()
    rate = int(getattr(processor.feature_extractor, "sampling_rate", 48000))
    samples = load_audio(args.audio, rate, args.seconds)
    probs = score_labels(model, processor, samples, labels, rate)
    ranked = sorted(zip(labels, probs), key=lambda item: -item[1])[: args.top]
    if args.json:
        print(
            json.dumps(
                {
                    "path": args.audio,
                    "model": args.model,
                    "tags": [
                        {"label": label, "score": round(score, 4)}
                        for label, score in ranked
                    ],
                },
                ensure_ascii=False,
            )
        )
    else:
        for label, score in ranked:
            print(f"{score:6.3f}  {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
