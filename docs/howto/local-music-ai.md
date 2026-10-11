# Local music AI stack (trantor)

Everything about neural networks for music/audio on this machine: where it lives, how it is called,
how to recreate it. Complements `wine-vst-bridge.md` (Windows VSTs via yabridge in Renoise) and
`local-llm.md` (speech stack, LLM).

## venv inventory (all in /zero/ai/music-ai/, Python from the nix store)

| venv           | Python                         | Purpose                                     | Recreate                                                                                                                                                                                                                 |
| -------------- | ------------------------------ | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `venv-rave311` | 3.11 (store `python3-3.11.15`) | acids-rave 2.3.1: RAVE VC/inference         | `uv pip install --python $(ls -d /nix/store/*python3-3.11*/bin/python3.11)/bin/python3.11` not needed: the venv already exists; packages: `uv pip install --python /zero/ai/music-ai/venv-rave311/bin/python acids-rave` |
| `venv-beat`    | 3.11                           | madmom (beats), torchcrepe (pitch), librosa | numpy==1.23.5 + scipy==1.10.1 (for madmom), then `--no-build-isolation` madmom; torchcrepe with plain pip                                                                                                                |
| `venv-nam`     | 3.11                           | neural-amp-modeler (NAM inference)          | `uv pip install --python .../venv-nam/bin/python neural-amp-modeler`                                                                                                                                                     |
| `venv-demucs`  | 3.13 (default)                 | demucs 4.1 + audio-separator (BS-RoFormer)  | `uv pip install --python .../bin/python demucs audio-separator onnxruntime audioread`; librosa==0.10.2.post1 (for audio-separator)                                                                                       |
| `venv-xtts`    | 3.11                           | coqui-tts 0.27.5 (XTTS-v2 RU cloning)       | `coqui-tts` + CPU torch 2.8/torchaudio 2.8 (NOT 2.9+: requires torchcodec/CUDA) + transformers==4.53.0; the first launch accepts the ToS (echo y)                                                                        |

General pattern for pip things on NixOS — derive the library dirs instead of pasting hashes:

```sh
export LD_LIBRARY_PATH="$(nix eval --raw --impure --option substitute false --expr 'let p = (builtins.getFlake "/etc/nixos").inputs.nixpkgs.legacyPackages.x86_64-linux; in "${p.gcc.cc.lib}/lib:${p.zlib}/lib:${p.zstd.out}/lib"'):${LD_LIBRARY_PATH:-}"
```

Those are the same three dirs the `~/.local/bin` wrappers (`demucs`, `rave`, `stems`, …) export from
`modules/user/nix-maid/cli/local-bin.nix` (`@GCC_LIB_DIR@`/`@ZLIB_LIB_DIR@`/`@ZSTD_LIB_DIR@`, see
[runbook-scripts.md](../runbook-scripts.md)); the manual export is only needed when calling a venv
by hand. Never copy a literal `/nix/store/...` path: it goes stale on the next nixpkgs bump and a
`nix-collect-garbage -d` removes it (2026-09-15: the old `gcc-15.2.0-lib` prefix had no gc root
left).

## Tagging and embeddings (MERT + CLAP)

Four wrappers in `packages/local-bin/bin/` share the payloads in `packages/local-bin/lib/` and the
`venv-analysis` packages. They run on a nix python (GC-rooted) with the venv on `PYTHONPATH`, so a
`nix-collect-garbage` run cannot break them the way it broke the venvs' own `bin/python` symlinks.

| Command                   | What it does                                                         | Model                                                     |
| ------------------------- | -------------------------------------------------------------------- | --------------------------------------------------------- |
| `music-embed FILE...`     | embeddings, one JSON per file or `--out FILE.npy`                    | `m-a-p/MERT-v1-95M` (env `MUSIC_EMBED_MODEL`, `--model`)  |
| `music-tags FILE`         | zero-shot genre/mood/instrument tags                                 | `laion/clap-htsat-unfused` (apache-2.0), `--labels a,b,c` |
| `music-index [MUSIC_DIR]` | builds the similarity index (embeddings + `vectors.npy`)             | embed model from the flag (`--model` to override)         |
| `music-similar [FILE]`    | top-k neighbours; without FILE it asks playerctl for the current one | the model recorded in the index `meta.json`               |

```console
$ music-tags ~/music/AFX-*/A01\ -\ AFX\ -\ Children\ Talking.flac --top 5
 0.863  breakbeat
 0.059  hip hop
$ music-tags --preset mood FILE               # focused vocabulary, sharper scores
$ music-tags --dir ~/music --out ~/tags.jsonl # batch, resumable by mtime+size
$ music-embed --out /tmp/afx.npy ~/music/AFX-*/A01*.flac
$ music-index ~/music --out ~/.cache/music-index      # hours for the full library, resumable
$ music-similar --index ~/.cache/music-index -k 5     # current track via playerctl
```

Notes:

- MERT-v1-95M on CPU: ~1 s per 10 s window, so the index builds at roughly 3 windows per track
  (`--windows`, `--window-seconds`). `m-a-p/MERT-v2-30s` is stronger (Jamendo genre ROC 88.0 vs 86.1
  on the model card) but 632M — pass `--model` or set
  `features.media.audio.musicTagging.embedModel`.
- CLAP scores are a softmax over the labels you pass: comparable inside one run, not across runs
  with different label sets. `--preset {genre,mood,instrument,electronic,default}` picks a focused
  vocabulary (a smaller set gives sharper scores), `--labels a,b,c` is free-form, and
  `--dir ~/music --out ~/tags.jsonl` tags a whole library, resuming by mtime+size.
- Layer choice was measured, not guessed: two same-album probes (6 and 12 albums, 30 s clips taken
  from different parts of the same track) put the **second-to-last** encoder layer above the last
  one — mean same-album margin 0.085 vs 0.052 and 0.046 vs 0.020, each with one more rank-1 hit.
  That is `DEFAULT_LAYER = -2`; `--layer` overrides it, and the layer is part of the index
  signature, so an index built with a different layer is never mixed with a query embedded by
  another one.
- Models land in `features.media.audio.musicTagging.hfHome` (default `/zero/ai/music-ai/hf`, created
  by tmpfiles) on first use.
- The index is plain numpy (`vectors.npy` + `tracks.jsonl` + `cache/`): for a few thousand tracks a
  brute-force cosine pass costs milliseconds, so there is no Annoy dependency. Files are cached by
  path+mtime+size+embed signature, so a re-run after new albums only embeds those.
- The voice client queues neighbours of the playing track: `mpd-voice say "similar tracks"` (the
  Russian phrases are listed by `mpd-voice phrases`) runs `music-similar --json` on the current song
  and appends the results to the MPD queue (`similar_cmd` and `music_dir` in the client's config —
  see [mpd-voice.md](./mpd-voice.md)).
- Corpus status (verified 2026-10-10 with the built wrapper text): a query excerpt of a track ranked
  its own album's indexed track first in 4 of 5 probes (scores 0.90–0.95); the miss was an
  ambient/atmospheric pair.
- Same wrappers, same idea for the older tool: `audio-analysis tag` now runs the CLAP payload from
  `lib/music_tags.py` instead of the `laion_clap` package, whose Zenodo checkpoint is not on disk
  any more.

## Repairing the venvs (nix-collect-garbage)

Every venv was created with a nix python and its `bin/python` is a symlink to that store path. Those
paths have no GC root, so `nix-collect-garbage -d` deletes them and the venvs die with
`No such file or directory` — on 2026-10-10 16 of 20 were down (packages and weights were all still
there; only the interpreter link was gone).

```console
$ just fix-music-venvs --check     # read-only report, non-zero when broken
$ just fix-music-venvs             # re-point every venv (idempotent)
$ just fix-music-venvs --dry-run   # show the planned actions
```

The script re-points `bin/python` (plus `python3`/`python3.X`) at the uv-managed interpreter of the
same version in `~/.local/share/uv/python` (it lives in `$HOME`, so nix GC cannot touch it), falls
back to the system profile, and rewrites the `home =` line of `pyvenv.cfg` so the stdlib is found.
Venvs whose interpreter is still healthy are reported `ok` and left alone.

Nothing under `/zero` is downloaded or reinstalled by it; if a version has no interpreter on the
machine it is reported and skipped rather than guessed.

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
  mikeoliphant/neural-amp-modeler-lv2). Available as LV2 in any LV2 host; see wine-vst-bridge.md
  about the VST part.
- Plugin path: `LV2_PATH` is set in envs.nix (`~/.lv2:/run/current-system/sw/lib/lv2`).
- Models (.nam captures): `/zero/ai/music/nam-models/` (example — Ceriatone King Kong). Big catalog:
  tonehunt.org. Inference outside Carla: `venv-nam` + python (init_from_nam; a tkinter stub on
  import; old .nam v0.5.0 — only in the plugin).
- Chain: guitar → NAM (amp, LV2/standalone) → RAVE (morphs) → recording (Renoise/SC).

## AIDA-X (second neural amplifier)

- LV2 plugin: `~/.lv2/AIDA-X.lv2` (v1.1.0, DPF, GPL-3.0) — CLAP/LV2/VST, real-time CPU. A second
  model format besides NAM (also tonehunt.org). Instantiates without errors (verified with lv2info
  2026-08-20).
- Models: downloaded into `~/.local/share/AIDA-X` (model picker in the plugin).

## Voice (zero-shot cloning, RU)

- `tts-clone "TEXT" REFERENCE.wav OUT.wav [--lang ru]` — XTTS-v2: clones a voice from a reference
  recording and speaks new text (RU/EN, 17 languages). CPU, ~6-8 s per phrase. CPML license
  (non-commercial) — fine for personal use.
- Verified: piper-irina voice cloning (2026-08-20).

## Source separation

- `stems input.wav [-o OUT] [--single-stem vocals|instrumental]` — BS-RoFormer (viperx ep_317, sdr
  12.97) — better than Demucs for vocal extraction. CPU, ~3× realtime.
- `demucs` — htdemucs_ft, 4 stems (vocals/drums/bass/other), 1.4× realtime.
- venv: `venv-demucs` (python 3.13): `pip install torch==2.8.0 --index-url …/whl/cpu` FIRST
  (otherwise pip pulls CUDA torch 2.13 + 2 GB of nvidia packages), then
  `pip install demucs audio-separator onnxruntime audioread librosa==0.10.2.post1 numpy`. Recreated
  2026-08-28 (the old one had fallen apart: bin→3.14, packages in 3.12/3.13).

## Whole-song transcription (chords/drums/vocals → MIDI)

- `song2midi FILE [--model chord|vocal|drum|piano|bass|beat|music] [-o OUT]` — Omnizart: chords,
  drums, vocal melody, bass → MIDI+CSV. CPU ~10-30 s per minute of audio. For a monophonic melody
  basic-pitch/pitch-f0 is faster; Omnizart adds chords/drums.
- venv: `venv-omnizart` (py3.11): madmom + pyaudio (from source, nix-portaudio) + **TensorFlow
  2.12** (2.21 is incompatible with the numpy 1.23 madmom needs) + sitecustomize patch for
  collections. Checkpoints 381 MB in site-packages/omnizart/checkpoints.
- Important: `omnizart transcribe` (without a model) is a stub in 0.6.3; only per-model works.
- Verified: C-Am-F-G → 12 notes (4 chords × 3), 2026-08-20.

## Beats and pitch (for Tidal sync)

- `audio-beats FILE` — BPM + beat times (madmom, offline; CC BY-NC-SA weights — fine for personal
  use). Output: `bpm 137.06` + seconds.
- `pitch-f0 FILE [--notes] [--hop MS] [--model tiny|full]` — f0 curve (torchcrepe, CPU ~14x realtime
  on tiny; --notes adds MIDI notes). Output: `time f0 [midi]` per frame.

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
  `basic-pitch OUTDIR file.wav --save-midi` (ONNX backend — the TF saved_model is broken on TF
  2.21).
- MIDI generation: `amt-generate` removed (2026-08-28, user decision — utter garbage). Transcription
  is `mt3`/`basic-pitch` (see above).
- Images: `rembg i in.png out.png` (u2net default, models in `/zero/ai/imgproc`; bria-rmbg also
  available); `triposr img.png --output-dir out` (image → 3D OBJ mesh, model in `/zero/ai/3d`).
- All wrappers live in `packages/local-bin/bin/`; after changes — `nh os switch`.
