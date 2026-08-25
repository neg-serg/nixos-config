#!/usr/bin/env python3
"""Audio-to-MIDI transcription with Sony hFT-Transformer (CPU, no GPU needed).

hFT-Transformer (ISMIR 2023, arXiv 2307.04305) transcribes piano recordings
into note events. The input is a log-mel spectrogram (16 kHz, 256 mel bands,
torchaudio-equivalent, computed here with numpy/scipy); the pretrained
MAESTRO-V3 checkpoint ships inside the package.

CLI:
  midi-transcribe <audio> [-o out.mid] [--onset 0.5] [--offset 0.5] [--mpe 0.5]
"""

import argparse
import io
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
import torch
import torch.storage as _S
import soundfile as sf
from scipy.signal import resample_poly

HFT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hft")
sys.path.insert(0, HFT_DIR)

# hFT checkpoints are CUDA-saved legacy pickles: route every nested torch.load
# through map_location='cpu' so CPU-only machines can load them.
_orig_lfb = _S._load_from_bytes


def _cpu_lfb(b):
    return torch.load(io.BytesIO(b), weights_only=False, map_location="cpu")


_S._load_from_bytes = _cpu_lfb

from model import amt  # noqa: E402

with open(os.path.join(HFT_DIR, "corpus", "config.json")) as _f:
    CONFIG = json.load(_f)
CONFIG["input"]["min_value"] = float(np.log(CONFIG["feature"]["log_offset"]))
CONFIG["input"]["max_value"] = 0.0
CHECKPOINT = os.path.join(
    HFT_DIR, "checkpoint", "MAESTRO-V3", "model_016_003.pkl"
)

_AUDIO_EXT = {".wav", ".flac", ".ogg"}


def hz_to_mel(f):
    return 2595.0 * np.log10(1.0 + f / 700.0)


def mel_to_hz(m):
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


def mel_filterbank(sr, n_fft, n_mels):
    """Torchaudio-equivalent mel filterbank (HTK mel scale, slaney norm)."""
    n_freqs = n_fft // 2 + 1
    all_freqs = np.linspace(0, sr // 2, n_freqs)
    m_pts = np.linspace(hz_to_mel(0.0), hz_to_mel(sr // 2), n_mels + 2)
    f_pts = mel_to_hz(m_pts)
    f_diff = np.diff(f_pts)
    slopes = f_pts[None, :] - all_freqs[:, None]
    down = -slopes[:, :-2] / f_diff[:-1]
    up = slopes[:, 2:] / f_diff[1:]
    fb = np.minimum(down, up).clip(min=0)
    fb *= (2.0 / (f_pts[2:] - f_pts[:-2]))[None, :]
    return fb.T  # [n_mels, n_freqs]


def wav2feature(path):
    """Log-mel feature [n_frames, 256], identical to the hFT training pipeline."""
    y, fs = sf.read(path, dtype="float32")
    sr = CONFIG["feature"]["sr"]
    if fs != sr:
        g = int(np.gcd(int(fs), sr))
        y = resample_poly(y, sr // g, int(fs) // g).astype(np.float32)
    n_fft = CONFIG["feature"]["fft_bins"]
    hop = CONFIG["feature"]["hop_sample"]
    y = np.pad(y, (n_fft // 2, n_fft // 2), mode="constant")
    n_frames = 1 + (len(y) - n_fft) // hop
    frames = np.stack([y[i * hop : i * hop + n_fft] for i in range(n_frames)])
    win = np.hanning(n_fft).astype(np.float32)
    spec = np.fft.rfft(frames * win, axis=1)
    power = np.abs(spec) ** 2
    fb = mel_filterbank(sr, n_fft, CONFIG["feature"]["mel_bins"])
    return np.log(power @ fb.T + CONFIG["feature"]["log_offset"]).astype(
        np.float32
    )


def write_midi(notes, out_path, bpm=120):
    import mido
    from mido import MidiFile, MidiTrack, MetaMessage, Message

    tpb = 480
    mid = MidiFile(ticks_per_beat=tpb)
    track = MidiTrack()
    mid.tracks.append(track)
    track.append(MetaMessage("set_tempo", tempo=mido.bpm2tempo(bpm)))
    track.append(MetaMessage("time_signature", numerator=4, denominator=4))
    ticks_per_sec = tpb * bpm / 60.0
    events = []
    for n in notes:
        st = int(round(n["onset"] * ticks_per_sec))
        en = int(round(n["offset"] * ticks_per_sec))
        if en <= st:
            continue
        pitch = int(round(n["pitch"]))
        vel = max(1, min(127, int(round(n.get("velocity", 80)))))
        events.append((st, "on", pitch, vel))
        events.append((en, "off", pitch))
    events.sort(key=lambda e: e[0])
    now = 0
    for t, kind, pitch, *rest in events:
        delta = max(0, t - now)
        now = t
        if kind == "on":
            track.append(
                Message("note_on", note=pitch, velocity=rest[0], time=delta)
            )
        else:
            track.append(
                Message("note_off", note=pitch, velocity=0, time=delta)
            )
    mid.save(out_path)


def main():
    ap = argparse.ArgumentParser(
        description="Audio-to-MIDI transcription (Sony hFT-Transformer, CPU)"
    )
    ap.add_argument("audio", help="input audio file (wav/flac/ogg/mp3)")
    ap.add_argument(
        "-o", "--output", help="output MIDI path (default: <audio>.mid)"
    )
    ap.add_argument(
        "--onset",
        type=float,
        default=0.5,
        help="onset threshold (default 0.5)",
    )
    ap.add_argument(
        "--offset",
        type=float,
        default=0.5,
        help="offset threshold (default 0.5)",
    )
    ap.add_argument(
        "--mpe",
        type=float,
        default=0.5,
        help="multipitch threshold (default 0.5)",
    )
    ap.add_argument(
        "--json", help="also save note events as JSON to this path"
    )
    args = ap.parse_args()

    if not os.path.exists(args.audio):
        sys.exit(f"error: {args.audio}: no such file")
    out = args.output or (os.path.splitext(args.audio)[0] + ".mid")

    print("loading hFT-Transformer model...", file=sys.stderr)
    AMT = amt.AMT(CONFIG, CHECKPOINT, verbose_flag=False)
    for mod in AMT.model.modules():
        if hasattr(mod, "device"):
            mod.device = "cpu"

    print("computing log-mel features...", file=sys.stderr)
    if os.path.splitext(args.audio)[1].lower() not in _AUDIO_EXT:
        # transcode mp3/other via ffmpeg (soundfile cannot read them)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name
        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-v",
                    "error",
                    "-i",
                    args.audio,
                    "-ac",
                    "1",
                    tmp_path,
                ],
                check=True,
            )
            feat = wav2feature(tmp_path)
        finally:
            os.unlink(tmp_path)
    else:
        feat = wav2feature(args.audio)

    print("transcribing...", file=sys.stderr)
    o1, f1, m1, v1, o2, f2, m2, v2 = AMT.transcript(
        feat, mode="combination", ablation_flag=False
    )
    notes = AMT.mpe2note(
        o2,
        f2,
        m2,
        v2,
        thred_onset=args.onset,
        thred_offset=args.offset,
        thred_mpe=args.mpe,
        mode_velocity="ignore_zero",
        mode_offset="shorter",
    )
    write_midi(notes, out)
    print(f"wrote {len(notes)} notes -> {out}")
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(notes, fh)
        print(f"wrote notes json -> {args.json}")


if __name__ == "__main__":
    main()
