#!/usr/bin/env python3
"""Audio-to-MIDI transcription (CPU): RobustAMT and Sony hFT-Transformer.

Backends:
  RobustAMT (Zenodo 10610212) — bytedance high-resolution architecture
    retrained with data augmentation; includes sustain-pedal events.
  hFT-Transformer (ISMIR 2023, arXiv 2307.04305) — piano, log-mel input.

Post-processing (all on by default, disable with --post ...):
  pedal    — extend note offsets to the sustain-pedal interval (RobustAMT only)
  quantize — snap onsets/offsets to a tempo grid (auto BPM, --grid subdivision)
  velocity — median-smooth velocity per pitch, clamp to [8,120]

CLI:
  midi-transcribe <audio> [-o out.mid] [--model robust|hft] [--post pedal,quantize,velocity]
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


# ----------------------------- post-processing -----------------------------
def _to_common(events):
    """Normalise a model's note events to {'pitch','onset','offset','velocity'}."""
    out = []
    for e in events:
        out.append(
            {
                "pitch": int(round(e.get("midi_note", e.get("pitch")))),
                "onset": float(e.get("onset_time", e.get("onset"))),
                "offset": float(e.get("offset_time", e.get("offset"))),
                "velocity": int(round(e.get("velocity", 80))),
            }
        )
    return [n for n in out if n["offset"] > n["onset"]]


def detect_bpm(onsets):
    """Estimate BPM via autocorrelation of the onset envelope (60-200)."""
    if len(onsets) < 8:
        return 120.0
    ons = np.sort(np.asarray(sorted(onsets), dtype=np.float64))
    dur = max(ons) + 0.05
    env, _ = np.histogram(ons, bins=np.arange(0.0, dur, 0.05))
    env = env.astype(np.float64)
    env -= env.mean()
    ac = np.correlate(env, env, "full")[len(env) - 1 :]
    ac = ac / (ac[0] + 1e-9)
    env_sr = 20.0  # 50ms bins
    best_bpm, best_score = 120.0, -np.inf
    for bpm in np.arange(60.0, 201.0, 0.5):
        lag = env_sr * 60.0 / bpm
        score = 0.0
        for k in (1, 2, 4):
            li = int(round(lag * k))
            if 0 < li < len(ac):
                score += ac[li]
        if score > best_score:
            best_score, best_bpm = score, bpm
    return best_bpm


def apply_pedal(notes, pedals):
    """Extend a note's offset to the end of the sustain-pedal interval it starts in."""
    if not pedals:
        return notes
    ped = sorted(
        (
            {
                "onset": float(p.get("onset_time", p.get("onset"))),
                "offset": float(p.get("offset_time", p.get("offset"))),
            }
            for p in pedals
        ),
        key=lambda p: p["onset"],
    )
    for n in notes:
        for p in ped:
            if p["onset"] <= n["onset"] < p["offset"]:
                if p["offset"] > n["offset"]:
                    n["offset"] = p["offset"]
                break
    return notes


def apply_quantize(notes, bpm=None, grid=16):
    """Snap onsets/offsets to the tempo grid (tolerance 30% of a grid step)."""
    if grid <= 0 or not notes:
        return notes
    if bpm is None:
        bpm = detect_bpm([n["onset"] for n in notes])
    beat = 60.0 / bpm
    step = beat / (grid / 4.0)

    def snap(t):
        nearest = round(t / step) * step
        return nearest if abs(nearest - t) < 0.3 * step else t

    for n in notes:
        onset = snap(n["onset"])
        offset = snap(n["offset"])
        if offset <= onset:
            offset = onset + step
        n["onset"] = onset
        n["offset"] = offset
    return notes


def apply_velocity(notes, window=0.15):
    """Median-smooth velocity per pitch over a time window, clamp [8,120]."""
    if not notes:
        return notes
    by_pitch = {}
    for n in notes:
        by_pitch.setdefault(n["pitch"], []).append(n)
    smoothed = []
    for ns in by_pitch.values():
        ns.sort(key=lambda n: n["onset"])
        times = np.array([n["onset"] for n in ns])
        vels = np.array([n["velocity"] for n in ns], dtype=np.float64)
        for i in range(len(ns)):
            lo = np.searchsorted(times, times[i] - window)
            hi = np.searchsorted(times, times[i] + window)
            ns[i]["velocity"] = int(
                round(max(8.0, min(120.0, np.median(vels[lo:hi]))))
            )
        smoothed.extend(ns)
    smoothed.sort(key=lambda n: n["onset"])
    return smoothed


def postprocess(notes, pedals, which, bpm=None, grid=16):
    """Apply the requested post-processing steps (comma-separated names)."""
    steps = {s.strip() for s in which.split(",") if s.strip()}
    if "pedal" in steps:
        notes = apply_pedal(notes, pedals)
    if "quantize" in steps:
        notes = apply_quantize(notes, bpm=bpm, grid=grid)
    if "velocity" in steps:
        notes = apply_velocity(notes)
    return notes


def write_midi(notes, pedals, out_path, bpm=120):
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
        vel = max(1, min(127, n["velocity"]))
        events.append((st, "note_on", n["pitch"], vel))
        events.append((en, "note_off", n["pitch"], 0))
    for p in pedals:
        pon = int(round(p["onset"] * ticks_per_sec))
        poff = int(round(p["offset"] * ticks_per_sec))
        if poff > pon:
            events.append((pon, "cc", 64, 127))
            events.append((poff, "cc", 64, 0))
    events.sort(key=lambda e: e[0])

    now = 0
    for t, kind, a, b in events:
        delta = max(0, t - now)
        now = t
        if kind == "note_on":
            track.append(Message("note_on", note=a, velocity=b, time=delta))
        elif kind == "note_off":
            track.append(Message("note_off", note=a, velocity=0, time=delta))
        else:
            track.append(
                Message("control_change", control=a, value=b, time=delta)
            )
    mid.save(out_path)


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
    raw = amt_inst.mpe2note(
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
    notes = postprocess(
        _to_common(raw), [], args.post, bpm=args.bpm, grid=args.grid
    )
    write_midi(notes, [], out, bpm=(args.bpm or 120.0))
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
    # The upstream package never calls .eval(): dropout stays active and the
    # transcription is non-deterministic. Fix it (dropout OFF = as evaluated).
    transcriptor.model.eval()
    print("transcribing (RobustAMT)...", file=sys.stderr)
    result = transcriptor.transcribe(y, out)
    audio_dur = len(y) / sample_rate
    raw = [
        e
        for e in result.get("est_note_events", [])
        if float(e.get("onset_time", e.get("onset", 0.0))) < audio_dur - 0.1
    ]
    # Cap offsets at the audio length (segment padding can spill past it)
    for e in raw:
        e["offset_time"] = min(float(e.get("offset_time", 0.0)), audio_dur)
    pedals = [
        {
            "onset": float(p.get("onset_time", p.get("onset"))),
            "offset": float(p.get("offset_time", p.get("offset"))),
        }
        for p in result.get("est_pedal_events", [])
    ]
    notes = postprocess(
        _to_common(raw), pedals, args.post, bpm=args.bpm, grid=args.grid
    )
    write_midi(notes, pedals, out, bpm=(args.bpm or 120.0))
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
        help="hFT chunk stride in frames (0=off, 32=half-overlap)",
    )
    ap.add_argument(
        "--post",
        default="pedal,quantize,velocity",
        help="post-processing steps, comma-separated (pedal/quantize/velocity; empty = none)",
    )
    ap.add_argument(
        "--grid",
        type=int,
        default=16,
        help="quantization subdivision (16 = 1/16 note; 0 = off)",
    )
    ap.add_argument(
        "--bpm",
        type=float,
        default=None,
        help="quantization tempo (default: auto-detect)",
    )
    ap.add_argument(
        "--onset", type=float, default=0.5, help="hFT onset threshold"
    )
    ap.add_argument(
        "--offset", type=float, default=0.5, help="hFT offset threshold"
    )
    ap.add_argument(
        "--mpe", type=float, default=0.5, help="hFT multipitch threshold"
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
