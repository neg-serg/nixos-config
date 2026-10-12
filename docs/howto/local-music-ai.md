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
$ music-tags --now --preset genre --top 5     # tags of the track playerctl reports
$ music-tags --dir ~/music --out ~/tags.jsonl # batch, resumable by mtime+size
$ music-embed --out /tmp/afx.npy ~/music/AFX-*/A01*.flac
$ music-index ~/music --out ~/.cache/music-index      # hours for the full library, resumable
$ music-similar --index ~/.cache/music-index -k 5     # current track via playerctl
$ music-similar --queue -k 5                          # ...and append them to the queue
```

The queue path is also on a key: `Super+Shift+P` (the `music` submap) then `q` —
`music-similar --queue -k 5` — and by voice: `mpd-voice say "similar tracks"`.

Notes:

- Model size and throughput: MERT-v1-95M runs ~1.5 s per track (3×10 s windows) on CPU; the stronger
  `m-a-p/MERT-v2-30s` costs ~1.3× time and 2.3× RSS for +15 points rank-1 — see the measured table
  below. Switching is `--model` or `features.media.audio.musicTagging.embedModel`.

- CLAP scores are a softmax over the labels you pass: comparable inside one run, not across runs
  with different label sets. `--preset {genre,mood,instrument,electronic,default}` picks a focused
  vocabulary (a smaller set gives sharper scores), `--labels a,b,c` is free-form, and
  `--dir ~/music --out ~/tags.jsonl` tags a whole library, resuming by mtime+size **and settings**
  (model, vocabulary, template, clip length) — change any of those and the pass re-tags instead of
  reusing stale rows.

- Prompt phrasing moves the answer as much as the vocabulary does: on four known tracks (funeral
  doom, breakbeat, dark ambient, neofolk) plain labels hit 2-3 of 4, while `a {label} track` hit 4
  of 4 and pulled neofolk at 0.76 where the plain prompt chose the wrong label. That template is the
  default; `--template "{label}"` restores the raw form and a comma separated list averages several
  (measured no sharper, but available). Expect near-ties to flip between runs: the ranking comes
  from a softmax over 30 s of audio, not from a trained head.

- Layer choice is measured, not guessed, and it is resolved **per checkpoint**: `m-a-p/MERT-v1-95M`
  → `-2`, `m-a-p/MERT-v2-30s` → `-1` (for v2 the last layer wins), anything else → `-2`; `--layer`
  overrides it and the value is part of the index signature, so an index built with a different
  layer is never mixed with a query embedded by another one.

- Model comparison on the same probe (same track, two 30 s excerpts, 10 albums, 3×10 s windows, 16
  threads):

  | Model                         | Best layer | rank1 | Mean margin | s / clip | RSS     |
  | ----------------------------- | ---------- | ----- | ----------- | -------- | ------- |
  | `m-a-p/MERT-v1-95M` (default) | -2         | 0.50  | +0.025      | 1.5      | 1.4 GiB |
  | `m-a-p/MERT-v2-30s`           | -1         | 0.65  | +0.046      | 2.0      | 3.2 GiB |

  v2 embeds noticeably better for ~1.3× the time; `--threads 4` instead of the default 16 costs
  ~1.8× (2.05 vs 1.14 s per clip), so only use it to keep the machine responsive.

- `music-index --adopt-legacy` trusts pre-signature cache entries as if they came from the current
  settings (it prints what it assumes). It exists for a build that started before the signature was
  introduced: `music-index --layer -1 --adopt-legacy` keeps such a run's vectors instead of
  re-embedding the whole library; without the flag the same run re-embeds.

- Models land in `features.media.audio.musicTagging.hfHome` (default `/zero/ai/music-ai/hf`, created
  by tmpfiles) on first use.

- The index is plain numpy (`vectors.npy` + `tracks.jsonl` + `cache/`): for a few thousand tracks a
  brute-force cosine pass costs milliseconds, so there is no Annoy dependency. Files are cached by
  path+mtime+size+embed signature, so a re-run after new albums only embeds those.

- Decoding goes through soundfile, and through **ffmpeg** for containers libsndfile cannot read
  (m4a/aac/wma). That gap was real: the first index of this library came up 1005 tracks short and
  `music-index --audit` now names them, grouped by extension — .m4a 878, .mp3 113, .flac 13, .wav 1.
  The incremental run with the settings the index was built with (`music-index --layer -1`) closed
  most of that gap — 37 498 of 37 627 tracks — and the 129 still missing fall into two groups.
  Truncated files (61 mp3) report a nominal length in the header while the audio stops early, so the
  tail window decoded to nothing and MERT died in conv1d; `read_window` now falls back to the start
  of the file, which recovers them. Genuinely corrupt files (a truncated streaminfo reports a
  duration of 2e14 s) are skipped with an explicit reason instead of a torch traceback, and no
  decoder will fix those — they need re-downloading.

- Building with *different* settings than the index on disk re-embeds everything, so the tool says
  so before starting and prints the exact flags that would keep the existing index.

- Raw MERT cosine is anisotropic: on the real 36 565-track index the mean top-1 similarity was
  0.958, so everything looked equally close. `music-similar` therefore subtracts the corpus mean
  from both sides and re-normalises (`center.npy`, written by `music-index`; readers derive it when
  the file is absent, so older indexes work unchanged). Measured over 2000 queries:

  | Variant                         | same-album rank1 | same-album P@5 | same-artist rank1 | same-artist P@5 |
  | ------------------------------- | ---------------- | -------------- | ----------------- | --------------- |
  | as stored                       | 0.213            | 0.157          | 0.310             | 0.186           |
  | **mean centered**               | **0.232**        | **0.160**      | **0.331**         | **0.192**       |
  | all-but-the-top (-4/-8/-16/-32) | 0.218–0.222      | ≤0.159         | 0.320–0.324       | ≤0.186          |
  | CSLS (k=10)                     | 0.088–0.115      | ≤0.093         | 0.102–0.137       | ≤0.109          |

  All-but-the-top and CSLS were measured on the same probe and rejected; `--no-center` restores the
  raw cosines for comparison. Treat the absolute numbers as a proxy: the point of the queue-similar
  feature is "the same neighbourhood", not "the same album".

- Keeping the index fresh: `features.media.audio.musicTagging.autoIndex` (default **off**) adds a
  user timer (`music-index.service` / `music-index.timer`, `OnCalendar = "Sun 04:00"`, `Persistent`,
  `Nice = 10`, idle IO, `--quiet --threads 4`) that runs the incremental pass while the machine
  idles. Warm runs take minutes because the per-file cache decides what to embed.

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

## Trained tags (MTG / Essentia)

CLAP labels are zero-shot — free text matched against an embedding, sensitive to phrasing. The MTG
heads are *trained* on fixed taxonomies: EffNet-Discogs embeddings followed by `genre_discogs400`
(400 Discogs styles), `mtg_jamendo_moodtheme`, `mtg_jamendo_instrument` and, with `--set all`,
`danceability` and `voice_instrumental`.

```console
$ just music-mtg-setup              # venv-mtg (essentia-tensorflow) + sha256-pinned models
$ music-mtg-tags --check            # models present?
$ music-mtg-tags --top 5 TRACK.flac
$ music-mtg-tags --set all --dir ~/music --json > ~/tags-mtg.jsonl
```

Measured on the same four known tracks (30 s, mean over 29 EffNet frames):

| Clip   | MTG Discogs-400 top labels                          | CLAP for comparison                        |
| ------ | --------------------------------------------------- | ------------------------------------------ |
| Evoken | Doom Metal .11, Ambient .09, Funeral Doom Metal .08 | funeral doom .95 (plain) / .75 (templated) |
| AFX    | Jungle .20, Drum n Bass .19, Breakcore .19, IDM .18 | breakbeat .86–.98                          |
| Cryo   | Dark Ambient .39, Ambient .26, Industrial .21       | drone/ambient (coarser label)              |
| Rome   | Experimental .32, Ambient .12, Neofolk .09          | neofolk .76–.81 (more confident here)      |

Magnitudes are not comparable between the two (400-class sigmoid vs softmax over the labels you
pass). Trust call: **genre → MTG** (canonical Discogs names, prompt-insensitive), mood/instrument →
MTG's trained Jamendo heads, free-form text ("sounds like a rainy city") → CLAP. The `danceability`
head called dark ambient "danceable .72" — do not trust it outside club music.

Agreement with the library's own GENRE tags (169 labelled tracks, strict = the label appears in a
Discogs style, lenient = in its parent): **top-1 0.24 strict / 0.34 lenient, top-5 0.44 / 0.54**.
The misses are mostly neighbouring families (`idm` → Electronic/Ambient, `trip-hop` → Hip Hop/Trap)
or tracks the hand tag over-generalised (an ambient intro labelled `funeral doom metal` → Electronic
/ Ambient), with real errors in between (`symphonic metal` → Euro House). So the genre head is a
coarse, prompt-free family classifier — good for grouping and for feeding mood/voice features, not a
replacement for curated tags. The mood head has no ground truth in the files at all; its labels rest
on the spot checks above.

Cost: ~0.36 s per 30 s clip on CPU (0.33 s EffNet + 0.03 s for all heads), 660 MB RSS, one-time
graph load ~0.4 s; long inputs scale with the ~1 s frame hop (5 min → 0.94 s). CPU-only: the TF
runtime wants libcudart/libcuda, so no GPU is involved.

Batch (the whole library): `music-mtg-tags --dir ~/music --out ~/.cache/music-mtg/tags.jsonl --json`
appends one JSON object per track and resumes by mtime+size+settings, so an interrupted pass only
costs the remaining files — the line is written and flushed as soon as a track is tagged. A stride
sample of this library (111 tracks spread over the 37k): tagged in 65 s with `--jobs 4` (~0.58 s per
track; a single process does ~0.36 s/track, so the pool mostly fights over cores — `--jobs 1` is as
fast and leaves the machine alone), 95% of tracks got a mood label above 0.10, top styles Ambient 26
/ Experimental 14 / Black Metal 8 / Funeral Doom Metal 5 / Techno 4, top moods dark 24 / film 16 /
epic 14 / energetic 12 / relaxing 9. A full pass over this 37k library runs at ~1.1 s per track on
CPU (whole-file decode plus 30 s of inference) — around 11 h single-process, ~7 h with `--jobs 4`,
and any partial file stays valid, so an interrupted run resumes where it stopped. The measured full
pass took 5.5 h for 34 029 tracks (3 598 unreadable files skipped) and produced, library-wide:
styles Ambient 8 617 / Experimental 6 840 / Post-Modern 1 188 / Black Metal 1 141 / Industrial 859,
moods dark 7 018 / film 6 606 / relaxing 4 896 / epic 2 531 / energetic 2 500, instruments
synthesizer 19 377 / piano 5 950 / drums 3 333, with mood coverage above 0.10 on 32 366 of 34 029
tracks. Add `--exclude 'samples/*'` (or `--min-seconds 20`) when the library keeps one-shot sample
packs: a mood queue otherwise picked a two-second VCSL piano note, and each record now carries
`audio_seconds` so readers can filter short clips themselves.
`music-mtg-tags --stats ~/.cache/music-mtg/tags.jsonl` prints that same distribution for a finished
run (label counts per head plus mood coverage) and counts broken lines.

Playlists come out of the same file:
`music-mtg-tags --tags ~/.cache/music-mtg/tags.jsonl --playlists DIR --by mood --min-score 0.15 --per-list 120`
writes one `.m3u` per label (`--by mood|style|parent|instrument`, `--filter metal` narrows the
labels, paths are relative to `--music-dir`), which MPD loads as `mpc load dark` once the files sit
in its playlist_directory. On the finished library that is 31 mood lists, 15 parent genres or 20
metal styles, best scores first.

Layout and provenance: the tagger needs `essentia-tensorflow` (the shared venv-analysis has a plain
essentia without the `TensorflowPredict*` classes), so `just music-mtg-setup` fills a separate
`features.media.audio.musicTagging.mtgVenv`; models go to `...mtgModels` (both created by tmpfiles,
~25 MB). `essentia.upf.edu` is unreachable from this network, so `scripts/dev/music-mtg-models.sh`
downloads the files from sha256-pinned GitHub mirrors and archive.org with cross-checked hashes.

## GPU (ROCm) for the embedding models

The music-AI venv carries a CUDA torch build (`2.14.0+cu130`), which never sees the AMD GPU, so MERT
and CLAP run on CPU. The ROCm build is already on disk
(`/zero/ai/music/tmp-dl/torch-2.13.0+rocm7.1-cp312-*.whl`), and `scripts/dev/music-ai-rocm.sh` (also
`just music-ai-rocm`) swaps it in:

```console
$ just music-ai-rocm --check     # read-only: is the venv GPU-ready?
$ just music-ai-rocm --dry-run   # show the three installs
$ just music-ai-rocm             # torch + torchaudio + torchvision -> +rocm7.1
$ MUSIC_EMBED_DEVICE=cuda music-embed TRACK.flac   # or --device cuda
```

- `torchaudio`/`torchvision` are swapped together with torch on purpose: transformers imports
  torchaudio whenever it exists, and the CUDA build of it cannot load next to ROCm torch
  (`libcudart.so.13: cannot open shared object file`). Without the companions MERT/CLAP break.
- The wheel ships gfx1201 code objects (`TensileLibrary_lazy_gfx1201.dat`, gfx1201 `.hsaco`), so no
  `HSA_OVERRIDE_GFX_VERSION` is needed for the RX 9070 XT.
- The script re-points the venv's dead `bin/python` symlink when it has to install (the same repair
  as `just fix-music-venvs`), refuses ABI mismatches, installs nothing without `--force` when a ROCm
  set is already there, downloads nothing (local wheels only) and never touches other venvs.
- `MUSIC_EMBED_DEVICE` is the shared device knob for the music-AI stack (`MUSIC_TAGS_DEVICE`
  overrides it for `music-tags`); `auto` takes the GPU as soon as torch sees one.
- Verified in this repo's sandbox: the wheel installs into a scratch venv and HIP 7.1 loads, but the
  sandbox denies `/dev/kfd` (device policy, `neg` is in `render`), so GPU-vs-CPU numbers must be
  measured on the host — CPU remains the fallback and the numbers above stay CPU numbers.

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
