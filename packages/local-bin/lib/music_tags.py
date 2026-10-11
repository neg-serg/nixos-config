#!/usr/bin/env python3
"""Zero-shot music tagging with CLAP (text labels against audio).

Usage:
  music_tags.py [--preset KEY|--labels a,b,c] [--top N] [--json] AUDIO
  music_tags.py --dir MUSIC_DIR --out TAGS.jsonl [--limit N] [--rebuild]

Single-file mode prints the ranked labels.  Batch mode walks a music library,
tags every file and appends one JSON object per track to the output file
(``{"path", "mtime", "size", "model", "tags":[{"label","score"}...]}``);
entries already present with the same mtime+size are skipped, so an
interrupted pass resumes and a re-run only tags new or changed files.

The default label set mixes genres, moods and instrumentation so one run
answers "what is this".  CLAP matches the labels against the audio embedding,
and the reported score is a softmax over the labels given in that run: it is
comparable inside one run, not across runs with different label sets.
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

# Focused vocabularies: a small label set gives sharper scores than the mixed
# default one, so asking a specific question ("genre? mood?") beats one run
# over everything when the answer matters.
PRESETS: dict[str, tuple[str, ...]] = {
    "default": DEFAULT_LABELS,
    "genre": (
        "ambient",
        "black metal",
        "death metal",
        "doom metal",
        "drone",
        "dungeon synth",
        "folk",
        "hip hop",
        "idm",
        "breakbeat",
        "techno",
        "house",
        "drum and bass",
        "jazz",
        "classical",
        "pop",
        "punk",
        "post-rock",
        "rock",
        "singer-songwriter",
        "soundtrack",
    ),
    "mood": (
        "aggressive",
        "angry",
        "calm",
        "dark",
        "dreamy",
        "epic",
        "happy",
        "hopeful",
        "melancholic",
        "mysterious",
        "nostalgic",
        "peaceful",
        "ritual",
        "sad",
        "tense",
        "triumphant",
    ),
    "instrument": (
        "acoustic guitar",
        "bass guitar",
        "cello",
        "choir",
        "drum kit",
        "electric guitar",
        "flute",
        "female vocal",
        "male vocal",
        "organ",
        "piano",
        "saxophone",
        "strings",
        "synthesizer",
        "trumpet",
        "violin",
    ),
    "electronic": (
        "ambient techno",
        "breakbeat",
        "drum and bass",
        "dub techno",
        "glitch",
        "idm",
        "industrial",
        "noise",
        "psytrance",
        "synthwave",
        "techno",
        "trance",
    ),
}

AUDIO_EXTS = {".mp3", ".flac", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".wma"}
# Prompt phrasing is part of the accuracy: measured on four known tracks
# (funeral doom / breakbeat / dark ambient / neofolk) plain "{label}" got 2-3
# of 4 right, "a {label} track" got 4 of 4 and put neofolk at 0.76 where the
# plain prompt picked the wrong label.  A comma separated list averages
# several templates (available, but not sharper in that probe).
DEFAULT_TEMPLATE = "a {label} track"


def load_audio(path: str, rate: int, seconds: float = 30.0):
    """Decode (see music_embed.load_audio) — same loader as the embedder."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from music_embed import load_audio as _load

    return _load(path, rate, seconds)


def pick_device(requested: str = "auto") -> str:
    import torch

    if requested != "auto":
        return requested
    return "cuda" if torch.cuda.is_available() else "cpu"


def _embedding(output):
    """Pull the projected embedding out of a model output (transformers 4/5)."""
    if hasattr(output, "pooler_output") and output.pooler_output is not None:
        return output.pooler_output
    if hasattr(output, "last_hidden_state"):
        return output.last_hidden_state.mean(dim=1)
    return output


def load_tagger(model_id: str, device: str):
    """Return ``(processor, model, rate)`` for a CLAP checkpoint."""
    from transformers import ClapModel, ClapProcessor

    processor = ClapProcessor.from_pretrained(model_id)
    model = ClapModel.from_pretrained(model_id).to(device).eval()
    rate = int(getattr(processor.feature_extractor, "sampling_rate", 48000))
    return processor, model, rate


def labels_for(args: argparse.Namespace) -> list[str]:
    if args.labels:
        return [
            label.strip() for label in args.labels.split(",") if label.strip()
        ]
    preset = PRESETS.get(args.preset)
    if preset is None:
        raise SystemExit(
            f"unknown preset {args.preset!r}; available: {', '.join(sorted(PRESETS))}"
        )
    return list(preset)


def label_templates(args: argparse.Namespace) -> list[str]:
    """Prompt templates, comma separated in --template; {label} is required."""
    templates = [
        item.strip() for item in (args.template or DEFAULT_TEMPLATE).split(",")
    ]
    templates = [item for item in templates if item]
    if not templates or any("{label}" not in item for item in templates):
        raise SystemExit("every --template entry must contain {label}")
    return templates


def score_labels(
    model,
    processor,
    samples,
    labels: list[str],
    rate: int,
    templates: tuple[str, ...] | list[str] = ("{label}",),
):
    """Mean softmax over cosine similarity of audio vs the templated labels.

    Prompt phrasing matters: on four known tracks (funeral doom, breakbeat,
    dark ambient, neofolk) plain labels got 2-3 of 4 right, while "a {label}
    track" got 4 of 4 and retrieved neofolk with 0.76 confidence where the
    plain prompt went to the wrong label.  Several templates are averaged when
    given (an ensemble is no sharper here, but it is available).
    """
    import numpy as np
    import torch

    audio_inputs = processor(
        audio=samples, sampling_rate=rate, return_tensors="pt"
    )
    audio_inputs = {k: v.to(model.device) for k, v in audio_inputs.items()}
    with torch.no_grad():
        audio_embed = _embedding(model.get_audio_features(**audio_inputs))
        audio_embed = audio_embed / audio_embed.norm(dim=-1, keepdim=True)
        scale = 100.0
        if hasattr(model, "logit_scale_a") and model.logit_scale_a is not None:
            scale = float(model.logit_scale_a.detach().exp())
        per_template = []
        for template in templates:
            prompts = [template.format(label=label) for label in labels]
            text_inputs = processor(
                text=prompts, return_tensors="pt", padding=True
            )
            text_inputs = {
                key: value.to(model.device)
                for key, value in text_inputs.items()
            }
            text_embed = _embedding(model.get_text_features(**text_inputs))
            text_embed = text_embed / text_embed.norm(dim=-1, keepdim=True)
            logits = (audio_embed @ text_embed.T)[0] * scale
            per_template.append(logits.softmax(dim=-1).cpu().numpy())
    if len(per_template) == 1:
        return per_template[0].tolist()
    return np.mean(per_template, axis=0).tolist()


def settings_key(args, labels: list[str]) -> str:
    """Anything that changes the numbers also changes the cached record."""
    return "|".join(
        [
            args.model,
            args.preset if not args.labels else "labels:" + ",".join(labels),
            args.template,
            f"{args.seconds:g}",
        ]
    )


def tag_file(tagger, path: Path, labels: list[str], args) -> dict:
    processor, model, rate = tagger
    samples = load_audio(str(path), rate, args.seconds)
    probs = score_labels(
        model, processor, samples, labels, rate, label_templates(args)
    )
    ranked = sorted(zip(labels, probs), key=lambda item: -item[1])[: args.top]
    stat = path.stat()
    return {
        "path": str(path),
        "mtime": stat.st_mtime_ns,
        "size": stat.st_size,
        "model": args.model,
        "vocabulary": args.preset if not args.labels else "custom",
        "template": args.template,
        "settings": settings_key(args, labels),
        "tags": [
            {"label": label, "score": round(float(score), 4)}
            for label, score in ranked
        ],
    }


def load_done(path: Path) -> dict[str, tuple[int, int, str]]:
    """path -> (mtime, size, settings) of the tracks already in the output."""
    done: dict[str, tuple[int, int, str]] = {}
    if not path.exists():
        return done
    for line in path.read_text().splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        # Older records carry no settings: they compare as different, so a
        # changed vocabulary or template re-tags instead of silently reusing.
        done[record["path"]] = (
            record["mtime"],
            record["size"],
            record.get("settings", ""),
        )
    return done


def run_batch(tagger, args) -> int:
    root = Path(args.dir).expanduser()
    if not root.is_dir():
        print(f"[music-tags] not a directory: {root}", file=sys.stderr)
        return 2
    labels = labels_for(args)
    out_path = Path(args.out).expanduser() if args.out else None
    if out_path is None:
        print("[music-tags] --dir needs --out FILE.jsonl", file=sys.stderr)
        return 2
    done = {} if args.rebuild else load_done(out_path)
    settings = settings_key(args, labels)
    files = [
        item
        for item in sorted(root.rglob("*"))
        if item.is_file() and item.suffix.lower() in AUDIO_EXTS
    ]
    if args.limit:
        files = files[: args.limit]
    tagged = 0
    with open(out_path, "a") as handle:
        for path in files:
            stat = path.stat()
            if done.get(str(path)) == (
                stat.st_mtime_ns,
                stat.st_size,
                settings,
            ):
                continue
            try:
                record = tag_file(tagger, path, labels, args)
            except Exception as exc:  # keep the pass going on bad files
                print(f"[music-tags] skip {path}: {exc}", file=sys.stderr)
                continue
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            tagged += 1
            if not args.quiet:
                top = record["tags"][0] if record["tags"] else {"label": "-"}
                print(
                    f"[music-tags] {tagged} new: {path.name} -> "
                    f"{top['label']} {top.get('score', 0):.3f}",
                    file=sys.stderr,
                )
    if not args.quiet:
        print(
            f"[music-tags] {tagged} new, {len(files) - tagged} skipped "
            f"-> {out_path}",
            file=sys.stderr,
        )
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("audio", nargs="?", help="audio file to tag")
    parser.add_argument(
        "--model", default=DEFAULT_MODEL, help="HuggingFace id"
    )
    parser.add_argument(
        "--labels", help="comma separated labels (overrides --preset)"
    )
    parser.add_argument(
        "--preset",
        default="default",
        choices=sorted(PRESETS),
        help="label vocabulary (default: mixed genre/mood/instrument set)",
    )
    parser.add_argument(
        "--top", type=int, default=10, help="how many to print"
    )
    parser.add_argument(
        "--seconds", type=float, default=30.0, help="clip length"
    )
    parser.add_argument(
        "--template",
        default=DEFAULT_TEMPLATE,
        help=(
            "prompt template(s) with {label}; comma separated entries are "
            f"averaged (default: {DEFAULT_TEMPLATE!r})"
        ),
    )
    parser.add_argument(
        "--dir", help="batch mode: tag a whole music directory"
    )
    parser.add_argument("--out", help="batch mode: JSONL output file")
    parser.add_argument(
        "--limit", type=int, help="batch mode: only the first N files"
    )
    parser.add_argument(
        "--rebuild", action="store_true", help="ignore already tagged files"
    )
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument(
        "--now",
        action="store_true",
        help="tag the track MPRIS reports as playing (playerctl)",
    )
    parser.add_argument("--device", default="auto", help="auto|cpu|cuda")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if not args.audio and not args.dir and not args.now:
        parser.error("need AUDIO, --dir or --now")
    return args


def current_track_path() -> str | None:
    """Path of the track MPRIS reports as playing."""
    import subprocess
    from urllib.parse import unquote, urlparse

    try:
        url = subprocess.check_output(
            ["playerctl", "metadata", "xesam:url"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    if not url.startswith("file://"):
        return None
    return unquote(urlparse(url).path)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    tagger = load_tagger(args.model, pick_device(args.device))
    if args.dir:
        return run_batch(tagger, args)
    labels = labels_for(args)
    raw = args.audio or (current_track_path() if args.now else None)
    if not raw:
        print(
            "[music-tags] no audio argument and no playerctl track",
            file=sys.stderr,
        )
        return 2
    path = Path(raw).expanduser()
    if not path.exists():
        print(f"[music-tags] file not found: {path}", file=sys.stderr)
        return 2
    record = tag_file(tagger, path, labels, args)
    if args.json:
        print(json.dumps(record, ensure_ascii=False))
    else:
        for tag in record["tags"]:
            print(f"{tag['score']:6.3f}  {tag['label']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
