# Removing torch from the audio-AI stack — analysis (2026-11-23)

Question: can the torch-dependent audio tooling be ported to a runtime that does not require Python
(TensorFlow was suggested), or otherwise bypassed, without losing functionality?

Mode of this document: analysis only. No venv, package or config was changed. The decision is
deferred; the "Decision log" at the end records what was decided so far.

## Baseline: where torch actually lives

Nix side: nothing depends on torch at runtime.

```
nix-store -qR /run/current-system | rg -i torch
/nix/store/...-NoiseTorch-0.12.2
```

`NoiseTorch` is a PipeWire/PulseAudio noise gate, unrelated to PyTorch. The single Nix-level torch
dependency is `packages/midi-transcribe` (`ps.torch`, CPU build), and it is deliberately kept out of
the system closure: flake app `nix run .#midi-transcribe` plus `flake/devshells/media.nix` (the
comment there calls it "a 2.7G torch env"). `packages/nix-det-pgo/workload.nix` mentions
`python3Packages.torch` only as an attrpath that the PGO trainer *instantiates (evaluates, never
builds)*, so it is not a dependency either.

Everything else is a pip venv under `/zero/ai`, owned by the main user, invisible to Nix.

| venv                               | torch          | size (du) | consumer                                                                      |
| ---------------------------------- | -------------- | --------- | ----------------------------------------------------------------------------- |
| music-ai/venv-analysis             | 2.13.0+rocm7.1 | 9.8 GB    | music-embed, music-tags, music-describe (mf engine), audio-analysis           |
| music-ai/venv-demucs               | 2.13.0+rocm7.1 | 2.4 GB    | demucs, stems, stems-all                                                      |
| music-ai/venv-beat                 | 2.13.0         | 2.0 GB    | audio-beats (madmom), pitch-f0 (torchcrepe)                                   |
| music-ai/venv-denoise              | 2.14.0         | 0.8 GB    | transcribe-high denoise; also the ROCm torch provider for midi-transcribe-gpu |
| music-ai/venv-whisperx             | 2.8.0          | 5.2 GB    | whisperx (faster-whisper + pyannote)                                          |
| music-ai/venv-seedvc               | 2.4.0          | 4.2 GB    | seed-vc                                                                       |
| music-ai/venv-rvc                  | 2.13.0+rocm7.1 | 2.3 GB    | RVC voice conversion                                                          |
| music-ai/venv-mt3                  | 2.14.0         | 0.3 GB    | mt3                                                                           |
| music-ai/venv-triposr              | 2.14.0+cpu     | 0.7 GB    | triposr                                                                       |
| music-ai/venv-moss                 | 2.9.1+cpu      | 0.6 GB    | moss-music                                                                    |
| music-ai/venv-magenta              | 2.13.0+cpu     | 0.6 GB    | magenta stack                                                                 |
| music-ai/venv-rave                 | 2.13.0+cpu     | 0.4 GB    | RAVE models; the `rave`/`rave-vc` wrappers do not use it (see findings)       |
| music-ai/venv-groovae              | 2.14.0         | 0.2 GB    | groove-humanize                                                               |
| music-ai/venv-nam                  | 2.13.0         | 0.4 GB    | NAM amp models                                                                |
| music-ai/venv-xtts                 | 2.8.0          | 0.3 GB    | tts-clone                                                                     |
| video/comfyui/venv                 | 2.9.1+rocm6.4  | 7.5 GB    | ComfyUI                                                                       |
| video/wangp/venv                   | 2.13.0+rocm7.1 | 9.2 GB    | WanGP / wallpaper-video                                                       |
| midi-gen/venv{,-midilm,-text2midi} | 2.13.0+rocm7.1 | 21 GB     | no reference in the repo outside this document                                |

Caveat on sizes: uv hardlinks packages from its cache, so `du` of separate venvs is not additive;
the numbers are for orientation, not for a budget.

Already torch-free (the stack is half-ported already):

- ASR/TTS: whisper.cpp (Vulkan) and sherpa-onnx, both C++ (`modules/media/audio/speech.nix`,
  `modules/llm/asr.nix`); `aubio` for onset/beat CLIs.
- Audio description: audio.cpp (ggml, Vulkan) with the Audio Flamingo Next GGUF;
  `music-describe --engine afnext` is the primary path, the torch `mf` engine is only the CPU
  fallback.
- Similarity index and ranking: Rust (`packages/music-index-tools`); the m3u playlists are a
  tag-file -> playlist step inside `music-mtg-tags` (Python/TF stack, no torch).
- Bulk DSP features: `essentia-extractor` C++ CLI.
- Music tags (MTG trained heads): `venv-mtg`, essentia-tensorflow — TF, no torch.
- Basic Pitch (`venv-bp`, ONNX), Omnizart (`venv-omnizart`, TF + sherpa-onnx), rembg (`venv-rembg`,
  ONNX) — Python wrappers, but no torch.

## The TensorFlow question

TensorFlow is not a way out of Python here:

- nixpkgs ships TF as a **binary wheel**: `pkgs/development/python-modules/tensorflow/bin.nix`,
  `format = "wheel"`, CPU variant unless `cudaSupport`. Python stays.
- The C++ side was removed from nixpkgs: `libtensorflow` and `libtensorflow-bin` are throws in
  `pkgs/top-level/aliases.nix` ("removed as it was broken for years and unmaintained").
- TF has no GPU path on this host (no ROCm backend), while torch+ROCm is what the GPU parts use
  today.
- The one place where TF genuinely drops Python: Essentia's TF integration. Upstream supports
  `waf configure --with-tensorflow`, and `TensorflowPredict*` are C++ algorithms wrapping the TF C
  API (`.pb`/SavedModel inputs); the PyPI `essentia-tensorflow` is only the binding distribution.
  Driving it without Python therefore means building essentia + libtensorflow ourselves and writing
  an extractor CLI — nothing is packaged, and `essentia-extractor` in nixpkgs is the prebuilt
  AcousticBrainz 2.1_beta2 binary without TF.

Verdict: TF is viable as one packaging project (Essentia + libtensorflow + a small CLI), not as a
general replacement for torch. Its realistic benefit is the MTG tagger, which is already TF and
already torch-free — so even that project buys "no Python", not "no torch".

## Function-by-function map

Legend: readiness = what exists today; loss = expected functional difference; effort is a rough size
for a Nix package plus wrapper.

| Function                     | Today                           | Non-torch option                                                                                                                                                                       | Readiness                                                                              | Loss                                                                                                           | Effort |
| ---------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------ |
| Audio description            | audio.cpp GGUF (done)           | —                                                                                                                                                                                      | ready                                                                                  | none                                                                                                           | —      |
| ASR, TTS                     | whisper.cpp, sherpa-onnx (done) | —                                                                                                                                                                                      | ready                                                                                  | none                                                                                                           | —      |
| MTG trained tags             | essentia-tensorflow, TF         | Essentia C++ + libtensorflow                                                                                                                                                           | library only, unpackaged                                                               | none if parity holds                                                                                           | L      |
| Basic Pitch (MIDI)           | ONNX backend in `venv-bp`       | same ONNX model under ORT C++/Rust                                                                                                                                                     | weights exist, no CLI                                                                  | none if parity holds                                                                                           | M      |
| f0 (`pitch-f0`)              | torchcrepe                      | onnxcrepe weights, or Rust `pitch-core-onnx`                                                                                                                                           | weights exist (demo last pushed 2022-10), no CLI                                       | same CREPE family, parity plausible                                                                            | S–M    |
| Beats/tempo (`audio-beats`)  | madmom + torchcrepe in one venv | madmom stays; aubio/essentia for track-level tempo                                                                                                                                     | CLIs exist                                                                             | older algorithms, beat times not equivalent                                                                    | S      |
| Denoise                      | noisereduce (`venv-denoise`)    | DeepFilterNet `deep-filter` Rust CLI (prebuilt binaries)                                                                                                                               | ready upstream, only LADSPA in nixpkgs                                                 | different algorithm, likely better                                                                             | S      |
| Stems/demucs                 | htdemucs_ft PyTorch CPU         | demucs.cpp (C++17, Eigen/OpenBLAS), audio.cpp `--task sep`                                                                                                                             | no binaries, no package; audio.cpp GGUF has no `_ft`                                   | speed: 31.7 s vs 16.2 s per 60 s clip locally (audio.cpp), demucs.cpp author states it trades speed for memory | M      |
| Vocal separation             | BS-RoFormer (`stems`)           | audio.cpp `--family bs_roformer`, BSRoformer.cpp                                                                                                                                       | audio.cpp ready; BSRoformer.cpp young (2026-01)                                        | quality unverified on this host                                                                                | M      |
| MT3 / MR-MT3                 | torch                           | none found (T5X/JAX or Python only)                                                                                                                                                    | absent                                                                                 | replaces with basic-pitch/omnizart, different coverage                                                         | —      |
| NAM amp models               | torch                           | NeuralAmpModelerCore (C++/Eigen, `loadmodel`/`benchmodel`) or `nam-rs` (Rust, within 1e-5 of the reference)                                                                            | engines only, no CLI                                                                   | none if a wrapper is written                                                                                   | S–M    |
| GrooVAE (`groove-humanize`)  | torch                           | none maintained (TF1 magenta original; the torch port is a 1-star repo)                                                                                                                | absent                                                                                 | —                                                                                                              | —      |
| RAVE / rave-vc               | TorchScript `.ts` models        | libtorch (`nn~`) is still torch; ONNX export unsupported upstream                                                                                                                      | absent                                                                                 | none without dropping the feature; the wrappers are already broken by a venv mismatch (see findings)           | —      |
| RVC / seed-vc / XTTS         | torch                           | RVC: `xdna-rvc` (C++20 + ORT, source build, one-time `.pth` conversion needs Python); seed-vc: no ONNX path (export blocked by weight-norm/WaveNet); XTTS: ONNX exists but Python-only | partial                                                                                | voice conversion/cloning semantics change; one-time conversion step remains                                    | L      |
| whisperx                     | faster-whisper + pyannote       | `sherpa-onnx-offline-speaker-diarization` ships in nixpkgs (the PATH launcher exposes only `sherpa-onnx`); `pyannote-rs` is a library                                                  | components exist                                                                       | diarization accuracy unverified; no parity benchmark                                                           | M      |
| MERT embeddings              | transformers + torch            | community ONNX export (opset 14), `last_hidden_state [B,T,768]`                                                                                                                        | ONNX weights only, no CLI; license mismatch (card apache-2.0 vs upstream cc-by-nc-4.0) | index signature changes, full re-embed, parity claim unverified                                                | L      |
| CLAP zero-shot tags          | transformers + torch            | official Xenova ONNX (audio 118 MB, text 502 MB)                                                                                                                                       | library only (ORT/Node), no CLI; mel placement in graph unverified                     | parity gate needed                                                                                             | M      |
| MOSS-music                   | torch reference code            | none; audio.cpp supports MOSS-TTS/SoundEffect/Transcribe but not moss_music                                                                                                            | absent                                                                                 | —                                                                                                              | —      |
| Music Flamingo v1 (15.4 GiB) | torch `mf` fallback             | audio.cpp packages only Music Flamingo 2601 q8_0                                                                                                                                       | partial                                                                                | v1 checkpoints have no GGUF                                                                                    | —      |
| ComfyUI / WanGP              | torch                           | none                                                                                                                                                                                   | absent                                                                                 | —                                                                                                              | —      |
| TripoSR                      | torch                           | only a browser ONNX WebGPU PoC (unverified)                                                                                                                                            | absent                                                                                 | —                                                                                                              | —      |
| Training (`nightjob`)        | ROCm torch wheels               | none                                                                                                                                                                                   | absent                                                                                 | torch is the point                                                                                             | —      |

All candidate ports are inference-only; training stays on Python either way.

## What blocks a full "no torch" end state

1. Embeddings. MERT/CLAP are the largest single torch consumer (`venv-analysis`, 9.8 GB) and the
   only one with no ready non-Python packaging. Both ONNX paths are libraries, not CLIs. MERT ONNX
   is third-party with a license mismatch; the parity claim (cosine ≈ 1.0) is unverified, and a
   model change invalidates the index signature, forcing a full re-embed of the library.
1. Model file formats. RAVE ships TorchScript only; upstream states ONNX export is untested for v2
   and streaming models fail to convert. MOSS-music has no port at all.
1. Voice conversion/cloning and generative video are torch-native by construction.

## Findings that are not about porting (recorded, not acted upon)

- Dead weight on `/zero` (~30 GB): `video/comfyui/venv.broken-usrbin` (6.4 GB duplicate),
  `midi-gen/venv*` (21 GB, no reference in the repo outside this document), and
  `venv-analysis/.../nvidia` (2.4 GB CUDA leftovers after the ROCm wheel swap; the ROCm wheel's
  metadata declares no nvidia Requires-Dist, but confirm with `pip check` before deleting).
  `scripts/dev/music-ai-dedupe.sh` hardlinks duplicate packages instead of copying them.
- `rave` and `rave-vc` are broken independently of torch: both exec
  `/zero/ai/music-ai/venv-rave311`, an empty venv (`import torch` → `ModuleNotFoundError`), while
  the working `venv-rave` (rave + torch 2.13.0+cpu) is referenced by nothing.
- The weekly `music-index.timer` failed on 2026-11-22 with `status=1`. Localized on 2026-11-23: the
  failing step is `tags` (`music-mtg-tags`), not the describe ledger. The step walked
  `~/music/samples` (3647 one-shot files EffNet cannot frame), and `run_batch` returned 1 whenever
  it wrote nothing and skipped something, so every incremental no-op pass failed; the 2026-11-22 run
  also segfaulted inside essentia-tensorflow (not reproduced on a rerun). Fixed during hygiene: the
  refresh chain now passes `--exclude 'samples/*'` to the tags step, and `run_batch` records
  untaggable files in a `<out>.failed.jsonl` sidecar and exits 0, mirroring the describe ledger.

## Recommendation (pending a decision)

1. Do not migrate the stack to TensorFlow. It keeps Python, removes the GPU path, and its only real
   no-Python use (Essentia + libtensorflow) is a packaging project, not a swap.
1. If "fewer Python venvs" becomes a goal, the cheapest real wins are `pitch-f0` (CREPE via ONNX),
   splitting `venv-beat` (madmom stays, torchcrepe goes), and `deep-filter` for denoise. Each needs
   a small wrapper because none of the candidates ships a CLI.
1. Source separation only after a measured spike: demucs.cpp on the same 60 s clip, with SDR and
   wall time compared against the current 16.2 s PyTorch CPU run. Do not re-wire `stems` on a README
   claim; the repo already measured audio.cpp GGUF as 2x slower.
1. MERT/CLAP last, and only behind a parity gate plus the willingness to pay one full re-embed.
1. Leave RAVE (fix the venv mismatch first), RVC/seed-vc/XTTS, ComfyUI/WanGP/TripoSR, MOSS-music and
   training alone.

## Open questions

- Does the Xenova CLAP ONNX graph include the mel front end and logit scaling, or are they only in
  the JS feature extractor?
- Is the MERT ONNX export numerically equal on real tracks (same layer, same pooling), and what is
  the actual license of the exported weights?
- How fast is demucs.cpp on this CPU for a 60 s clip, and does its SDR match htdemucs_ft?
- Do audio.cpp's HIP and ORT's ROCm EP work on gfx1201 at all? Every quoted GPU number so far comes
  from CUDA.

## Evidence

Local checks (run 2026-11-23 on trantor):

- `nix-store -qR /run/current-system | rg -i torch` -> only `NoiseTorch`.
- `rg -n 'midi-transcribe' flake/` -> only `flake/apps.nix` and `flake/devshells/media.nix`.
- venv inventory and versions: `dist-info/METADATA` under
  `/zero/ai/*/venv*/lib/python*/site-packages`.
- Timer failure: `journalctl --user -u music-index.service --since '2026-11-22 16:00'`.
- RAVE: `/zero/ai/music-ai/venv-rave311/bin/python -c 'import torch'` -> `ModuleNotFoundError`.
- nixpkgs claims: pinned source at `/nix/store/...-source` (`pkgs/top-level/aliases.nix`,
  `pkgs/development/python-modules/tensorflow/bin.nix`, `pkgs/by-name/es/essentia-extractor`).

Upstream claims are linked inline; the ones that could not be reproduced locally are marked
"unverified" in the table.

## Decision log

- 2026-11-23: analysis only. No venv, timer, package or config was modified; porting decisions are
  deferred until the questions above are answered.
- 2026-11-23 (later): hygiene mode enabled. Removed `video/comfyui/venv.broken-usrbin` (6.3 GiB) and
  `venv-analysis/.../nvidia` (2.3 GiB; torch still imports) and the three `midi-gen` venvs (21 GiB
  du), keeping `models/`, `repos/`, `bin/` by request; fixed the MTG tags exit path and the refresh
  exclusion.
- 2026-11-23 (deployed): the fix reached the system together with the pending nixpkgs bump
  (generation 2971, `26.11.20261121`); the store script carries `--exclude 'samples/*'` and an
  end-to-end run of the deployed `music-mtg-tags` recorded 120 untaggable files and exited 0.
- 2026-11-23 (dedupe): `music-ai-dedupe.sh --apply` hardlinked 2690 duplicate files (0 failures);
  only 0.1 GiB remained reclaimable because the big duplicates lived in the deleted `midi-gen`
  venvs. `df /zero` is unchanged at ~156 GiB while logical `du` dropped, so verifying what still
  holds the blocks (`zpool list`, `zfs list -t snapshot -r zero`) needs root.
