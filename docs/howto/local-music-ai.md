# Local music AI stack (odin)

Everything about neural networks for music/audio on this machine: where it lives, how
it is called, how to recreate it. Complements `wine-vst-bridge.md` (Windows VSTs via
yabridge in Renoise) and `local-llm.md` (speech stack, LLM).

## venv inventory (all in /zero/ai/music-ai/, Python from the nix store)

| venv | Python | Purpose | Recreate |
| --- | --- | --- | --- |
| `venv-rave311` | 3.11 (store `python3-3.11.15`) | acids-rave 2.3.1: RAVE VC/inference | `uv pip install --python $(ls -d /nix/store/*python3-3.11*/bin/python3.11)/bin/python3.11` not needed: the venv already exists; packages: `uv pip install --python /zero/ai/music-ai/venv-rave311/bin/python acids-rave` |
| `venv-beat` | 3.11 | madmom (beats), torchcrepe (pitch), librosa | numpy==1.23.5 + scipy==1.10.1 (for madmom), then `--no-build-isolation` madmom; torchcrepe with plain pip |
| `venv-nam` | 3.11 | neural-amp-modeler (NAM inference) | `uv pip install --python .../venv-nam/bin/python neural-amp-modeler` |
| `venv-demucs` | 3.13 (default) | demucs 4.1 + audio-separator (BS-RoFormer) | `uv pip install --python .../bin/python demucs audio-separator onnxruntime audioread`; librosa==0.10.2.post1 (for audio-separator) |
| `venv-xtts` | 3.11 | coqui-tts 0.27.5 (XTTS-v2 RU cloning) | `coqui-tts` + CPU torch 2.8/torchaudio 2.8 (NOT 2.9+: requires torchcodec/CUDA) + transformers==4.53.0; the first launch accepts the ToS (echo y) |

General pattern for pip things on NixOS:
`export LD_LIBRARY_PATH=/nix/store/7vafhlh0lmcvi75jfyy09qwr4m3x1ks3-gcc-15.2.0-lib/lib:/nix/store/483x61iy35irm4wr2b7dwzihljhp6da2-zlib-1.3.2/lib:/nix/store/13id30w3rvgj24nnz34f7qrncz48zd7l-zstd-1.5.7/lib`

## RAVE (neural autoencoder)

- Models: `/zero/ai/music/rave/*.ts` — guitar (16-latent, 48k), VCTK (voice v1), isis +
  sol_ordinario (vocal v2, official IRCAM), crozzoli (18-latent).
- **RaveLive** (live processor in SuperCollider): class in
  `~/.local/share/SuperCollider/Extensions/rave-live/RaveLive.sc`. Chain
  `SoundIn -> NN(\rave,\encode) -> manipulations -> NN(\rave,\decode) -> out`, controls
  amount/morph/freeze/gain, OSC /rave/ctl (Tidal). Latency ~85 ms. Docs:
  `/zero/ai/music/rave-live/README.md` + `tidal-rave.md`.
- **Voice conversion**: `rave-vc IN.wav OUT.wav [--src isis] [--tgt sol_ordinario]` (wrapper over
  `/zero/ai/music/rave-live/vc.py`, resamples to 48k automatically). Demo:
  `/zero/ai/music/rave-live/demo/`. Important: model latent sizes differ (isis=8, sol=4) —
  conversion works through AdaIN normalization of the decoder; judge the quality by ear.

## NAM (Neural Amp Modeler) — neural amplifier

- Plugin: `~/.lv2/neural_amp_modeler.lv2` (v0.2.3, Linux x64, GPL-3.0,
  mikeoliphant/neural-amp-modeler-lv2). Available as LV2 in any LV2 host; see
  wine-vst-bridge.md about the VST part.
- Plugin path: `LV2_PATH` is set in envs.nix (`~/.lv2:/run/current-system/sw/lib/lv2`).
- Models (.nam captures): `/zero/ai/music/nam-models/` (example — Ceriatone King Kong). Big
  catalog: tonehunt.org. Inference outside Carla: `venv-nam` + python (init_from_nam; a
  tkinter stub on import; old .nam v0.5.0 — only in the plugin).
- Chain: guitar → NAM (amp, LV2/standalone) → RAVE (morphs) → recording (Renoise/SC).

## AIDA-X (second neural amplifier)

- LV2 plugin: `~/.lv2/AIDA-X.lv2` (v1.1.0, DPF, GPL-3.0) — CLAP/LV2/VST, real-time CPU. A
  second model format besides NAM (also tonehunt.org). Instantiates without errors
  (verified with lv2info 2026-08-20).
- Models: downloaded into `~/.local/share/AIDA-X` (model picker in the plugin).

## Voice (zero-shot cloning, RU)

- `tts-clone "TEXT" REFERENCE.wav OUT.wav [--lang ru]` — XTTS-v2: clones a voice from a
  reference recording and speaks new text (RU/EN, 17 languages). CPU, ~6-8 s per phrase.
  CPML license (non-commercial) — fine for personal use.
- Verified: piper-irina voice cloning (2026-08-20).

## Source separation

- `stems input.wav [-o OUT] [--single-stem vocals|instrumental]` — BS-RoFormer (viperx ep_317, sdr
  12.97) — better than Demucs for vocal extraction. CPU, ~3× realtime.
- `demucs` — htdemucs_ft, 4 stems (vocals/drums/bass/other), 1.4× realtime.
- venv: `venv-demucs` (python 3.13): `pip install torch==2.8.0 --index-url …/whl/cpu` FIRST (otherwise
  pip pulls CUDA torch 2.13 + 2 GB of nvidia packages), then
  `pip install demucs audio-separator onnxruntime audioread librosa==0.10.2.post1 numpy`. Recreated
  2026-08-28 (the old one had fallen apart: bin→3.14, packages in 3.12/3.13).

## Whole-song transcription (chords/drums/vocals → MIDI)

- `song2midi FILE [--model chord|vocal|drum|piano|bass|beat|music] [-o OUT]` — Omnizart: chords,
  drums, vocal melody, bass → MIDI+CSV. CPU ~10-30 s per minute of audio. For a monophonic
  melody basic-pitch/pitch-f0 is faster; Omnizart adds chords/drums.
- venv: `venv-omnizart` (py3.11): madmom + pyaudio (from source, nix-portaudio) + **TensorFlow
  2.12** (2.21 is incompatible with the numpy 1.23 madmom needs) + sitecustomize patch for collections.
  Checkpoints 381 MB in site-packages/omnizart/checkpoints.
- Important: `omnizart transcribe` (without a model) is a stub in 0.6.3; only per-model works.
- Verified: C-Am-F-G → 12 notes (4 chords × 3), 2026-08-20.

## Beats and pitch (for Tidal sync)

- `audio-beats FILE` — BPM + beat times (madmom, offline; CC BY-NC-SA weights — fine for personal
  use). Output: `bpm 137.06` + seconds.
- `pitch-f0 FILE [--notes] [--hop MS] [--model tiny|full]` — f0 curve (torchcrepe, CPU ~14x
  realtime on tiny; --notes adds MIDI notes). Output: `time f0 [midi]` per frame.

## Shabda — Freesound packs for Strudel

- `shabda` — helper for [shabda.ndre.gr](https://shabda.ndre.gr) (Freesound banks, licenses
  CC0/BY/BY-NC, generated by name on the fly).
  - `shabda` — open the site in Vivaldi;
  - `shabda 808` — open the site + copy `!reslist "…/808.json…"` (Tidal) to the clipboard;
  - `shabda -s amen` — `samples('…?strudel=1')` (Strudel);
  - `shabda -l amen` — only print the string (no browser/clipboard).
- In Strudel: paste the `!reslist …` string into the browser pattern. (The Tidal stack is back in
  the system — see [renoise-tidal-live.md](./renoise-tidal-live.md); the shabda string in Strudel
  format differs from the Tidal format.)
- Example: `shabda -l 808` → `!reslist "https://shabda.ndre.gr/808.json?licenses=by,cc0,by-nc"`.

## Misc

- OCR: `got-ocr` (GOT-OCR-2.0, Chinese/complex documents) and `pic-ocr` (tesseract/qwen3-vl,
  Russian).
- STT: `whisperx FILE` — recognition + diarization (small model, ru). Verified 2026-08-28.
- Melody transcription: `mt3 file.wav [out.mid]` (MR-MT3, checkpoint `/zero/ai/music/mt3`);
  `basic-pitch OUTDIR file.wav --save-midi` (ONNX backend — the TF saved_model is broken on TF 2.21).
- MIDI generation: `amt-generate` removed (2026-08-28, user decision — utter garbage).
  Transcription is `mt3`/`basic-pitch` (see above).
- Images: `rembg i in.png out.png` (u2net default, models in `/zero/ai/imgproc`; bria-rmbg also
  available); `triposr img.png --output-dir out` (image → 3D OBJ mesh, model in `/zero/ai/3d`).
- All wrappers live in `packages/local-bin/bin/`; after changes — `nh os switch`.
