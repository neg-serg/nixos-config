# Report: testing neural-network tools on odin

Check date: **2026-08-28 … 2026-09-05**. Host: odin (NixOS, AMD RX 9070 XT, Ryzen 9 9950X3D, 60
GB RAM). Goal — verify that all installed neural tools really work after the build, fix what is
broken, document the status. All models live in `/zero/ai/**`.

## Summary table

| Tool | Purpose | Status | Verified |
| --- | --- | --- | --- |
| `whisperx` | STT + diarization (faster-whisper, CPU) | ⚠️ STT ✓, align ✗ | 2026-08-29: ru recognition ✓ ('Hi! This is a speech-synthesis test…'); **alignment/diarization hang** (regression — worked on 19.08; needs debugging, probably torch/lightning versions) |
| `mt3` | audio → MIDI (MR-MT3, PyTorch) | ✅ works | 171 notes; **GPU (ROCm): 11.2s vs 30.3s CPU** (40s track, identical result, 2026-08-29) |
| `midi-transcribe` | hFT-Transformer / RobustAMT (piano) | ✅ works | CPU: `midi-transcribe`; **GPU (ROCm): `midi-transcribe-gpu`** — hFT 40s in ~11s instead of 20+ min CPU (2026-08-29, venv-denoise + torch 2.13 rocm7.1) |
| ~~`amt-generate`~~ | ~~MIDI generation (Anticipatory Music Transformer)~~ | ❌ removed | 2026-08-28, user decision |
| `audio-analysis` | Essentia key/beat + CLAP tags + mastering | ✅ works | 2026-08-29: Zinovia → **B minor (conf 0.85), ~110 BPM**; CLAP: ambient 0.169. ROCm torch in venv-analysis |
| `pitch-f0` | f0 tracking (torchcrepe) | ✅ works | 2026-08-29: 2164 frames, f0 49-50 Hz, CPU >10x realtime |
| `got-ocr` | OCR (GOT-OCR-2.0) | ✅ works | 2026-08-29: venv fixed (python was missing), image OCR ~20s CPU |
| `denoise` | noise reduction | ✅ works | inside transcribe-high (noisereduce), 2026-08-28 |
| `song2midi` | Omnizart (chords/vocals/bass/drums) | ✅ works | 2026-08-29: 15s of chords in ~30s (TF/CPU) |
| `stems` | BS-RoFormer vocal extraction | ✅ works | 2026-08-29: **GPU auto + fp16: 16s vs 64s** (×4) on 40s |
| `audio-beats` | BPM/beats (madmom) | ✅ works | 2026-08-29: 82 BPM on a Zinovia segment |
| `midi2tidal` | MIDI → Tidal code | ✅ works | 2026-08-29: pattern from zinovia_best (polyphony 6) |
| `transcribe-high --tidal` | pipeline + Tidal code | ✅ works | 2026-08-29: tempo 109.1 BPM, pattern generated |
| `groovae` | groove-humanize (magenta GrooVAE) | ✅ works | **GPU (ROCm)** 2026-08-29: drum loop humanize (venv-groovae + torch rocm) |
| `xtts-clone` | XTTS-v2 voice clone (zero-shot) | ✅ works | **GPU (ROCm)** 2026-08-29: synthesis on GPU (venv-xtts + torch 2.8 rocm6.4; needs free VRAM — ollama occupies it) |
| `rave`/`rave-vc` | neural-VAE encode/decode + voice conversion | ✅ works | **GPU (ROCm)** 2026-08-29: 10s of audio in ~10-13s (venv-rave311 + torch rocm; wrapper moved off the broken venv-rave) |
| `demucs` | source separation (htdemucs_ft) | ✅ works | torch rocm installed (venv-demucs, minus 2 GB nvidia); **GPU fp32 ≈ CPU** (9.7 vs 10.9s), fp16 breaks internally — CPU stays the default |
| `transcribe-high` | pipeline: denoise→Demucs→basic-pitch→merge | ✅ works | verified 2026-08-28 (see details); for clean recordings prefer `--no-denoise --no-stems` |
| `basic-pitch` | polyphonic transcription → MIDI | ✅ works | melody10s → MIDI (ONNX) |
| `rembg` | background removal (u2net / bria-rmbg / birefnet) | ✅ works | u2net + bria |
| `triposr` | image → 3D mesh | ✅ works | mesh.obj 7.2 MB |
| `audio-analysis master` | reference mastering (matchering) | ✅ works | 2026-08-29: Zinovia + DOOM ref → **-13.3 → -9.8 dB** |
| `vsmlrt-models` | ONNX vs-mlrt models (mpv upscale) | ✅ works | 2026-09-05: Alt+I in mpv truly fixed — the YUV vpy path crashed without `matrix_in_s` (3074) and silently fell back to Spline36 (vsncnn, onnx loading); added **RealESRGAN-x4plus** (generic 4x, exported from the official `.pth`) — 320×240→1280×960 **~2.3 fps**, 640×360→2560×1440 **~0.7 fps** (GPU free); fixed the YUV vpy path (matrix_in_s — otherwise a silent Spline36 fallback); xsx2 (anime 2x) — **49.8 fps** (live viewing), x4plus — for pauses/SD |
| `seed-vc` | zero-shot voice conversion (ByteDance SOTA) | ✅ works | 2026-09-04: **--svc (singing) is ready**: 44k f0 checkpoint (820 MB) + rmvpe + bigvgan; RTF ~5-10; wrapper `seed-vc ... --svc` verified |
| `rvc` | voice conversion with training (industry standard) | 🚧 ready | 2026-08-29: venv-rvc (torch rocm, numpy<2, gradio patch), hubert/rmvpe (370 MB), CLI `infer/cli.py` loads on ROCm; a trained model is needed |
| SC reverbs (mdugens/portedplugins/sc-faust) | PlateReverb, Fverb, jpverb (Faust) | ✅ built | 2026-08-29: 3 nix packages (CMake/scPluginFarm + release binaries), load in scsynth; land in SC_PLUGIN_PATH/Extensions after `nh os switch` |

## Tool details

### whisperx — STT + diarization

- Wrapper: `packages/local-bin/bin/whisperx` (venv `/zero/ai/music-ai/venv-whisperx`).
- Command: `whisperx audio.wav --model small --language ru --diarize --output_dir out/`.
- Result: `/tmp/whisperx-out/test-ru.{txt,srt,vtt,json,tsv}` — recognition + speaker labeling.
- Coexists with `whisper.cpp` (:8002) from the speech stack — that is a different backend.

### mt3 — audio-to-MIDI transcription

- Wrapper: `packages/local-bin/bin/mt3` (venv `/zero/ai/music-ai/venv-mt3`, inference
  `/zero/ai/music-ai/mt3-infer`).
- Command: `mt3 file.wav [out.mid]`; MR-MT3 checkpoint at `/zero/ai/music/mt3/mr_mt3`.
- Result: `/tmp/mt3-out.mid` — 171 notes.

### ~~amt-generate~~ — removed (2026-08-28)

The user dismissed the generation as garbage; removed: wrappers `/zero/ai/music-ai/bin/amt-*`, venv
`venv-amt` (incl. torch 2.13.0+rocm7.1), sources `anticipation/`, models
`music-small-100k`/`music-small-ar-100k` (980 MB), artifacts and wheels
(`/zero/ai/music/renders/amt-20260828/`, `/zero/ai/music/tmp-dl/`), symlink in `~/.local/bin`.

### basic-pitch — polyphonic transcription

- Wrapper: `packages/local-bin/bin/basic-pitch` (venv `venv-bp`) — **new**, forces
  `--model-serialization onnx`: the built-in TF saved_model is incompatible with TF 2.21.
- Command: `basic-pitch OUT_DIR audio.wav --save-midi`.
- Result: `/tmp/bp-test/melody10s_basic_pitch.mid`.

### rembg — background removal

- Wrapper: `packages/local-bin/bin/rembg` (venv `venv-rembg`). Default is `-m u2net` unless the
  user passed their own `-m` (bria-rmbg-2.0 was downloaded from a blocked GitHub).
- Models in `/zero/ai/imgproc/models/`: `u2net/u2net.onnx`, `bria-rmbg/bria-rmbg.onnx` (1.02 GB,
  downloaded via a socks proxy from the danielgatis/rembg release),
  `birefnet-general/birefnet-general.onnx`.
- Command: `rembg i in.png out.png`; `rembg i -m birefnet-general in.png out.png`.
- Result: `/tmp/rembg-out4.png`, `/tmp/rembg-bria.png`.

### triposr — image → 3D

- Wrapper: `packages/local-bin/bin/triposr` (venv `venv-triposr`, torch CPU +
  torchmcubes/xatlas/moderngl).
- Model VAST-AI/TripoSR (~700 MB) in `/zero/ai/3d` (HF_HOME).
- Command: `triposr img.png --output-dir out`.
- Result: `/tmp/triposr-out3/0/mesh.obj` (7.2 MB) — used to hang on downloading the bria model;
  works after installing bria into `/zero/ai/imgproc`.

## Fixed issues

1. **Broken venvs due to python 3.14** (system python is now 3.14.7, packages in the venv sit in
   `lib/python3.12` or 3.13 → ModuleNotFoundError). Fixed by relinking `bin/python3` to the
   3.12.13 store path:
   `ln -sfn /nix/store/71d4s2c3dfqk4afkjp8w8g4l3f1glcsy-python3-3.12.13/bin/python3.12 $venv/bin/python3`
   + `ln -sfn python3 $venv/bin/python`. Affected: whisperx, amt, mt3, bp, rembg, triposr, denoise,
   analysis.
1. **numba 0.67 broken on py3.12** (`coverage.types`) → `pip install 'numba<0.62'` (0.61.2 +
   llvmlite 0.44 + numpy 2.2.6).
1. **rembg pulls bria-rmbg-2.0.onnx from GitHub** (blocked) → model downloaded via a socks5h proxy
   (`127.0.0.1:10808`) into `/zero/ai/imgproc/models/bria-rmbg/`; the wrapper defaults to
   u2net.
1. **basic-pitch: TF saved_model broken on TF 2.21** → the wrapper forces ONNX serialization.
1. **venv-demucs** (bin→3.14, packages in 3.13): recreated on python3.13, CPU torch installed first
   (`pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cpu`), otherwise pip pulls
   CUDA torch + 2 GB of nvidia wheels.
1. **colibri serve: "Address already in use"** on 8000/8001/8002 → manual port **8003**; the service
   is off by default (enabled manually).

## Infrastructure

- **venv**:
  `/zero/ai/music-ai/venv-{amt,analysis,bp,demucs,denoise,groovae,magenta,midi2tidal,mt3,nam,omnizart,rave,rave311,rembg,tags,triposr,whisperx,xtts}`.
- **Wrappers**: `packages/local-bin/bin/` (Nix-managed; test via the direct path from the repo —
  they land in `~/.local/bin` after `nh os switch`). `amt-generate` — symlink to `/zero/ai/music-ai/bin/`.
- **Models (`/zero/ai`)**: `3d` (TripoSR), `imgproc` (rembg/u2net/bria/birefnet, RealESRGAN,
  vs-mlrt), `music` (mt3/mr_mt3, rave, nam-models, separation, instruments), `speech`
  (piper/whisper.cpp/cosyvoice-engines, voices), `whisperx` (hub), `ocr` (got-ocr2, paddleocr),
  `image` (flux/sdxl/taesd), `llama` (qwen3-vl, glm gguf), `ollama` (23 models), `glm52_i4`
  (colibri, 144 shards/384 GB), `embeddings`, `t5-summarization`, `video` (comfyui).
- **Ports**: 8000 = omnirouter (LLM), 8001 = piper TTS, 8002 = whisper STT, 8003 = colibri (manual
  start), 11434 = ollama.

## Commits (2026-08-28)

- `3b00ea9e` — `[docs]` neural tools in the local-music-ai howto + `basic-pitch` (new) and `rembg`
  (u2net-default) wrappers.
- Earlier in the session: `5389989a` (venv-demucs doc), `0c11f102` (colibri serve 8003), `60d29a89`
  (colibri manual-serve doc, serve off).

## Not verified / deferred (as of 2026-09-04)

- `whisperx` alignment/diarization — hangs (regression since 19.08; STT works). Fix: pin
  torch/lightning versions in venv-whisperx.
- `rvc` — venv/assets ready, CLI loads; no trained model (a target voice is needed).
- `pic-ocr` NN engine (qwen3-vl) — one-off run when the "OCR NN" button in the screenshot toast is
  used.
- `venv-tags`/PANNs — orphan (no weights, python hangs on a nonexistent path) — a removal
  candidate.
- `colibri` — service off by default (user decision); manual recipe: see
  `docs/howto/local-llm.md`.
