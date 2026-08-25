#!/usr/bin/env python3
"""Audio-to-MIDI transcription (CPU): Sony hFT-Transformer and RobustAMT.

hFT-Transformer (ISMIR 2023, arXiv 2307.04305) — piano, log-mel input, fast.
RobustAMT (Zenodo 10610212) — bytedance high-resolution architecture retrained
with data augmentations for real-world audio; includes sustain-pedal output.

CLI:
  midi-transcribe <audio> [-o out.mid] [--model robust|hft] [--stride 32] ...
"""

import argparse
import io
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

BASE = os.path.dirname(os.path.abspath(__file__))
HFT_DIR = os.path.join(BASE, "hft")
VENDOR_DIR = os.path.join(BASE, "vendor")
SHIM_DIR = os.path.join(BASE, "shim")
for _p in (SHIM_DIR, VENDOR_DIR, HFT_DIR):
    sys.path.insert(0, _p)

import torch  # noqa: E402
import torch.storage as _S  # noqa: E402
import soundfile as sf  # noqa: E402
from scipy.signal import resample_poly  # noqa: E402

# hFT checkpoints are CUDA-saved legacy pickles: route every nested torch.load
# through map_location='cpu' so CPU-only machines can load them.
_orig_lfb = _S._load_from_bytes


def _cpu_lfb(b):
    return torch.load(io.BytesIO(b), weights_only=False, map_location="cpu")


_S._load_from_bytes = _cpu_lfb

ROBUST_CHECKPOINT = os.path.join(
    BASE, "robust", "high_resolution_MAESTRO_augmentations.pth"
)
_AUDIO_EXT = {".wav", ".flac", ".ogg"}


def load_audio_array(path, target_sr):
    """Return mono float32 audio at target_sr (ffmpeg fallback for mp3/etc)."""
    if os.path.splitext(path)[1].lower() not in _AUDIO_EXT:
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
                    path,
                    "-ac",
                    "1",
                    tmp_path,
                ],
                check=True,
            )
            y, fs = sf.read(tmp_path, dtype="float32")
        finally:
            os.unlink(tmp_path)
    else:
        y, fs = sf.read(path, dtype="float32")
    if y.ndim > 1:
        y = y.mean(axis=1)
    if fs != target_sr:
        g = int(np.gcd(int(fs), target_sr))
        y = resample_poly(y, target_sr // g, int(fs) // g).astype(np.float32)
    return y


# ----------------------------- hFT backend -----------------------------
def hft_setup():
    from model import amt  # noqa: E402

    with open(os.path.join(HFT_DIR, "corpus", "config.json")) as f:
        config = json.load(f)
    config["input"]["min_value"] = float(
        np.log(config["feature"]["log_offset"])
    )
    config["input"]["max_value"] = 0.0
    ckpt = os.path.join(
        HFT_DIR, "checkpoint", "MAESTRO-V3", "model_016_003.pkl"
    )
    amt_inst = amt.AMT(config, ckpt, verbose_flag=False)
    for mod in amt_inst.model.modules():
        if hasattr(mod, "device"):
            mod.device = "cpu"
    return amt_inst, config


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
    return fb.T


def hft_wav2feature(y, config):
    """y is mono at 44100; resample to the model's 16 kHz and compute log-mel."""
    sr = config["feature"]["sr"]
    if sr != 44100:
        g = int(np.gcd(44100, sr))
        y = resample_poly(y, sr // g, 44100 // g).astype(np.float32)
    n_fft = config["feature"]["fft_bins"]
    hop = config["feature"]["hop_sample"]
    y = np.pad(y, (n_fft // 2, n_fft // 2), mode="constant")
    n_frames = 1 + (len(y) - n_fft) // hop
    frames = np.stack([y[i * hop : i * hop + n_fft] for i in range(n_frames)])
    win = np.hanning(n_fft).astype(np.float32)
    spec = np.fft.rfft(frames * win, axis=1)
    power = np.abs(spec) ** 2
    fb = mel_filterbank(sr, n_fft, config["feature"]["mel_bins"])
    return np.log(power @ fb.T + config["feature"]["log_offset"]).astype(
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


def run_hft(y, out, args):
    amt_inst, config = hft_setup()
    feat = hft_wav2feature(y, config)
    print("transcribing (hFT)...", file=sys.stderr)
    if args.stride > 0:
        outs = amt_inst.transcript_stride(
            feat, args.stride, mode="combination", ablation_flag=False
        )
    else:
        outs = amt_inst.transcript(
            feat, mode="combination", ablation_flag=False
        )
    o1, f1, m1, v1, o2, f2, m2, v2 = outs
    notes = amt_inst.mpe2note(
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
    print(f"wrote {len(notes)} notes -> {out}", file=sys.stderr)
    if args.json:
        with open(args.json, "w") as f:
            json.dump(notes, f)


# --------------------------- RobustAMT backend -------------------------
def run_robust(y, out, args):
    from piano_transcription_inference import PianoTranscription, sample_rate

    print("loading RobustAMT checkpoint...", file=sys.stderr)
    transcriptor = PianoTranscription(
        device="cpu", checkpoint_path=ROBUST_CHECKPOINT
    )
    print("transcribing (RobustAMT)...", file=sys.stderr)
    result = transcriptor.transcribe(y, out)
    notes = result.get("est_note_events", [])
    pedals = result.get("est_pedal_events", [])
    print(
        f"wrote {len(notes)} notes + {len(pedals)} pedal events -> {out}",
        file=sys.stderr,
    )
    if args.json:
        with open(args.json, "w") as f:
            json.dump({"notes": notes, "pedal_events": pedals}, f)


def main():
    ap = argparse.ArgumentParser(
        description="Audio-to-MIDI transcription (CPU): RobustAMT (default) or Sony hFT-Transformer"
    )
    ap.add_argument("audio", help="input audio file (wav/flac/ogg/mp3)")
    ap.add_argument(
        "-o", "--output", help="output MIDI path (default: <audio>.mid)"
    )
    ap.add_argument(
        "--model",
        choices=["robust", "hft"],
        default="robust",
        help="transcription backend (default: robust)",
    )
    ap.add_argument(
        "--stride",
        type=int,
        default=32,
        help="hFT chunk stride in frames (0=off, 32=half-overlap, default 32)",
    )
    ap.add_argument(
        "--onset",
        type=float,
        default=0.5,
        help="hFT onset threshold (default 0.5)",
    )
    ap.add_argument(
        "--offset",
        type=float,
        default=0.5,
        help="hFT offset threshold (default 0.5)",
    )
    ap.add_argument(
        "--mpe",
        type=float,
        default=0.5,
        help="hFT multipitch threshold (default 0.5)",
    )
    ap.add_argument(
        "--json", help="also save note events as JSON to this path"
    )
    args = ap.parse_args()

    if not os.path.exists(args.audio):
        sys.exit(f"error: {args.audio}: no such file")
    out = args.output or (os.path.splitext(args.audio)[0] + ".mid")

    if args.model == "hft":
        y = load_audio_array(args.audio, 44100)
        run_hft(y, out, args)
    else:
        from piano_transcription_inference import sample_rate as bd_sr

        y = load_audio_array(args.audio, bd_sr)
        run_robust(y, out, args)


if __name__ == "__main__":
    main()
