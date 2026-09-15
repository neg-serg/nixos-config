# RVC — voice conversion with training (Retrieval-based Voice Conversion)

Install date: 2026-08-29 (verified, the CLI works). Status: **venv and assets are ready, training on
a target voice — not done** (a dataset/model is needed).

## What it is and why

- RVC is the industry standard for **voice conversion with training**: the model is trained on a
  specific person's voice (~10 min of clean material) and gives the maximum resemblance to it. Used
  for covers, voice-overs, streams.
- Difference from Seed-VC: Seed-VC is **zero-shot** (a reference sample is enough, no training); RVC
  is **training on a voice** (higher accuracy for a specific target). XTTS is a TTS (text→speech),
  not conversion of arbitrary audio.
- Russian: works with Russian training data (RVC itself is language-independent — quality depends on
  the dataset).

## Status on odin

| Component     | Path                                                       | Status                       |
| ------------- | ---------------------------------------------------------- | ---------------------------- |
| Repository    | `/zero/ai/music-ai/Retrieval-based-Voice-Conversion-WebUI` | cloned                       |
| venv          | `/zero/ai/music-ai/venv-rvc` (torch 2.13.0+rocm7.1, GPU)   | ready                        |
| hubert        | `assets/hubert/hubert_base.pt` (190 MB)                    | downloaded                   |
| rmvpe         | `assets/rmvpe/rmvpe.pt` (181 MB)                           | downloaded                   |
| CLI           | `infer/cli.py`                                             | loads on ROCm without errors |
| Trained model | —                                                          | ❌ needs a target voice      |

## Inference (with a ready-made model)

```bash
export LD_LIBRARY_PATH="/nix/store/7vafhlh0lmcvi75jfyy09qwr4m3x1ks3-gcc-15.2.0-lib/lib:/nix/store/483x61iy35irm4wr2b7dwzihljhp6da2-zlib-1.3.2/lib:/nix/store/13id30w3rvgj24nnz34f7qrncz48zd7l-zstd-1.5.7/lib"
cd /zero/ai/music-ai/Retrieval-based-Voice-Conversion-WebUI
/zero/ai/music-ai/venv-rvc/bin/python infer/cli.py --model weights/MYVOICE.pth --input in.wav --output out.wav --f0-method rmvpe
```

Key options: `--speaker-id` (multi-voice models), `--pitch` (pitch shift in semitones),
`--index`/`--index-rate` (embedding search, increases similarity), `--rms-mix-rate`, `--protect`.

## Training on a voice

1. **Dataset**: ~10-15 min of clean voice of the target person (no music/noise/reverb), cut into
   3-10 s files.
1. **Preprocessing**: `python train/preprocess.py` (cutting, f0/hubert extraction).
1. **Training**: `python train/train.py` (G/D networks; on RX 9070 XT 16 GB: ~10 min of data × ~50
   epochs ≈ 30-60 min).
1. Put the resulting `.pth` + `.index` into the `assets/weights/` folder → inference.

## How to get a ready-made model

- Own recordings: collect a dataset (see above) and train.
- A ready `.pth` from HuggingFace (community models):

```bash
# huggingface.co rate-limited — go through the mirror
curl -L -o model.pth https://hf-mirror.com/<owner>/<repo>/resolve/main/<file>.pth
```

## Links

- Repository: <https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI>
- Overall neural-stack report: [neural-stack-report.md](./neural-stack-report.md)
- Zero-shot alternative: seed-vc (to be documented once the SVC mode is finished)
