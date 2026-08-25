"""Minimal librosa shim (basic-pitch + bytedance piano transcription paths)."""

import sys
import types
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, get_window as _scipy_get_window


def load(path, sr=22050, mono=True):
    y, fs = sf.read(str(path), dtype="float32", always_2d=True)
    if y.shape[1] > 1 and mono:
        y = y.mean(axis=1, keepdims=True)
    y = y[:, 0]
    if fs != sr:
        g = int(np.gcd(fs, sr))
        y = resample_poly(y, sr // g, fs // g).astype(np.float32)
    return y, sr


def hz_to_midi(f):
    return 69.0 + 12.0 * np.log2(np.asarray(f, dtype=np.float64) / 440.0)


def midi_to_hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=np.float64) - 69.0) / 12.0)


def cqt_frequencies(n_bins, fmin, bins_per_octave=12):
    return fmin * 2.0 ** (np.arange(0, n_bins) / float(bins_per_octave))


def frames_to_time(frames, sr=22050, hop_length=512):
    return np.asarray(frames, dtype=np.float64) * hop_length / float(sr)


# --- librosa.filters ---
def _hz_to_mel_htk(f):
    return 2595.0 * np.log10(1.0 + f / 700.0)


def _hz_to_mel_slaney(f):
    scalar = np.isscalar(f) or (np.ndim(f) == 0)
    f = np.atleast_1d(np.asarray(f, dtype=np.float64))
    f_sp = 200.0 / 3.0
    mels = (f - f_sp) / (700.0 / 3.0) + 1000.0 / (np.log(2.0))
    low = f < f_sp
    mels[low] = (f[low] / f_sp) * (1000.0 / (np.log(2.0)))
    return float(mels[0]) if scalar else mels


def _mel_to_hz_htk(m):
    return 700.0 * (10.0 ** (np.asarray(m, dtype=np.float64) / 2595.0) - 1.0)


def _mel_to_hz_slaney(m):
    m = np.asarray(m, dtype=np.float64)
    f_sp = 200.0 / 3.0
    f = 700.0 / 3.0 * (m - 1000.0 / np.log(2.0)) + f_sp
    low = m < 1000.0 / np.log(2.0)
    f[low] = m[low] * f_sp * np.log(2.0) / 1000.0
    return f


def _hz_to_mel(f, htk=False):
    return _hz_to_mel_htk(f) if htk else _hz_to_mel_slaney(f)


def _mel_to_hz(m, htk=False):
    return _mel_to_hz_htk(m) if htk else _mel_to_hz_slaney(m)


def mel(
    sr,
    n_fft,
    n_mels=128,
    fmin=0.0,
    fmax=None,
    htk=False,
    norm="slaney",
    dtype=np.float32,
):
    if fmax is None:
        fmax = sr / 2.0
    n_freqs = n_fft // 2 + 1
    all_freqs = np.linspace(0, sr / 2.0, n_freqs)
    m_min = _hz_to_mel(fmin, htk)
    m_max = _hz_to_mel(fmax, htk)
    m_pts = np.linspace(m_min, m_max, n_mels + 2)
    f_pts = _mel_to_hz(m_pts, htk)
    f_diff = np.diff(f_pts)
    slopes = f_pts[None, :] - all_freqs[:, None]
    down = -slopes[:, :-2] / f_diff[:-1]
    up = slopes[:, 2:] / f_diff[1:]
    fb = np.minimum(down, up).clip(min=0)
    if norm == "slaney":
        enorm = 2.0 / (f_pts[2:] - f_pts[:-2])
        fb *= enorm[None, :]
    return fb.T.astype(dtype)


def get_window(window, Nx, fftbins=True):
    return _scipy_get_window(window, Nx, fftbins=fftbins)


# --- librosa.util ---
def pad_center(data, size, axis=-1, **kwargs):
    n = data.shape[axis]
    lpad = int((size - n) // 2)
    lengths = [(0, 0)] * data.ndim
    lengths[axis] = (lpad, int(size - n - lpad))
    return np.pad(data, lengths, mode="constant", **kwargs)


def normalize(S, norm=None, axis=-1, threshold=None, fill=None):
    S = np.asarray(S, dtype=np.float64)
    mag = np.abs(S)
    if norm is None:
        mag_max = mag.max(axis=axis, keepdims=True)
        mag_max = np.where(mag_max == 0, 1.0, mag_max)
        return S / mag_max
    mag = np.linalg.norm(S, ord=norm, axis=axis, keepdims=True)
    mag = np.where(mag == 0, 1.0, mag)
    return S / mag


# --- librosa.core.audio ---
def to_mono(y):
    if y.ndim > 1:
        return y.mean(axis=tuple(range(1, y.ndim)))
    return y


def resample(y, orig_sr, target_sr, res_type="soxr_hq", **kwargs):
    g = int(np.gcd(orig_sr, target_sr))
    return resample_poly(y, target_sr // g, orig_sr // g).astype(np.float32)


def buf_to_float(x, n_bytes=2, dtype=np.float32):
    scale = 1.0 / float(1 << ((8 * n_bytes) - 1))
    return x.astype(dtype) * scale


# --- module assembly ---
_filters = types.ModuleType("librosa.filters")
_filters.mel = mel
_filters.get_window = get_window
sys.modules["librosa.filters"] = _filters
filters = _filters

_util = types.ModuleType("librosa.util")
_util.pad_center = pad_center
_util.normalize = normalize
sys.modules["librosa.util"] = _util
util = _util

_audio = types.ModuleType("librosa.core.audio")
_audio.to_mono = to_mono
_audio.resample = resample
_audio.buf_to_float = buf_to_float
sys.modules["librosa.core.audio"] = _audio
core_audio = _audio

_core = types.ModuleType("librosa.core")
_core.cqt_frequencies = cqt_frequencies
_core.frames_to_time = frames_to_time
_core.hz_to_midi = hz_to_midi
_core.midi_to_hz = midi_to_hz
_core.audio = _audio
sys.modules["librosa.core"] = _core
core = _core
