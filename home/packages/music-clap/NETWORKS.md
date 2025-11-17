# Essentia Neural Assets (English)

This repository ships the full `essentia-extractor` toolset (Essentia 2.1 beta2) and a Python-based
CLAP wrapper. The following machine-learning models/descriptors are readily available:

## High-level classifiers in `streaming_extractor_music`

The default music extractor profile bundles neural networks that return semantic tags. Common
outputs include:

- `genre_dortmund`, `genre_rosamerica`, `genre_tzanetakis` – multi-class genre estimators trained on
  Dortmund, Rosamerica and GTZAN corpora.
- `danceability` – probability of suitability for dancing.
- `gender`, `age_rating` – vocal gender and perceived age.
- `voice_instrumental`, `voice_presence` – probability of prominent vocals versus instrumental
  tracks.
- Mood models: `moods_mirex`, `moods_acoustic`, `moods_aggressive`, `moods_electronic`,
  `moods_happy`, `moods_party`, `moods_relaxed`, `moods_sad`, `moods_instrumental`, `moods_voice`,
  `moods_timbre`.
- `tonal_atonal` – tonal versus atonal estimate.

> **Note:** The upstream release only exposes these classifiers when the associated weight files are
> available. If your JSON outputs are missing the `highlevel` section, you need to supply the model
> bundle (Essentia provides it under a separate download).

## Other extractor profiles

Besides the all-in-one music extractor, the following specialised profiles are installed:

- `streaming_extractor_lowlevel` – spectral, temporal and energy descriptors.
- `streaming_extractor_tonal` – key, scale, tuning frequency, HPCP descriptors.
- `streaming_extractor_rhythm` / `streaming_extractor_beats` – tempo, beat positions, onset
  descriptors.
- `streaming_extractor_summary` – aggregate descriptors for cataloguing large folders.
- `streaming_extractor_freesound_{general,music}` – taggers used in the Freesound content and
  quality estimators.

Each profile is a YAML graph under Essentia's `streaming_extractor_*` examples; you can call it
directly or override with a custom profile path.

## CLAP integration

- `pkgs.neg.laion_clap` packages the LAION-CLAP (HTSAT-tiny + Roberta) checkpoints, tokenizer, and
  runtime dependencies.
- `pkgs.neg.music_clap` exposes a CLI (`music-clap`) that batches audio files, saves embeddings
  (`--dump`), and scores against arbitrary text prompts.
- Checkpoints are cached under `$LAION_CLAP_CACHE` / `$XDG_CACHE_HOME` / `~/.cache/laion_clap` to
  avoid writes into the Nix store.

## Handy entry points

- `streaming_extractor_music input.wav output.json`
- `music-highlevel dir/ --taxonomies moods_mirex genre_dortmund`
- `music-clap songs/ --text "dreamy shoegaze" --dump ~/.cache/music-clap`

### Usage examples

- **Extract tempo / BPM**

  ```sh
  streaming_extractor_rhythm track.wav rhythm.json
  jq '.rhythm.bpm' rhythm.json
  ```

  The rhythm profile also exposes `rhythm.onset_times` and `rhythm.beats_position` for beat-tracking
  tasks.

- **Grab tonal descriptors (key, scale, tuning)**

  ```sh
  streaming_extractor_tonal track.wav tonal.json
  jq -r '.tonal.key_key, .tonal.key_scale, .tonal.tuning_frequency' tonal.json
  ```

- **Batch semantic tags for a folder**

  ```sh
  music-highlevel ~/music --taxonomies moods_mirex genre_dortmund --output results
  ```

  This writes one JSON per file; use `jq '.highlevel.moods_mirex.value' results/song.json` to
  inspect tag probabilities.

- **Compare CLAP embeddings against multiple prompts**

  ```sh
  music-clap ~/music --text "blackened doom metal" --text "cinematic ambient" --limit 10
  ```

  The CLI prints cosine similarities so you can quickly surface tracks that best match each
  description.

- **Persist embeddings via cache**

  ```sh
  music-clap ~/music --text "blackened doom metal" --dump ~/.cache/music-clap
  ```

  Model weights live under `$LAION_CLAP_CACHE` (falls back to `~/.cache/laion_clap`); use `--dump`
  when you want per-track vectors written to disk. Re-runs reuse the cached `.npy` files
  automatically; add `--refresh` to force recomputation.

- **Inspect low-level spectral stats**

  ```sh
  streaming_extractor_lowlevel track.wav lowlevel.json
  jq '.lowlevel.spectral_centroid.mean' lowlevel.json
  jq '.lowlevel.mfcc.mean' lowlevel.json
  ```

  Combine the resulting means/std-dev fields when you need raw features for downstream ML.

- **Summarise an album**

  ```sh
  find ~/music/album -type f -name '*.flac' > files.txt
  streaming_extractor_summary --list files.txt summary.json
  jq '.summary.statistics.mean.bpm' summary.json
  ```

  The summary profile aggregates descriptors across multiple tracks for rapid library cataloguing.

- **Dump CLAP embeddings to reuse in Python**

  ```sh
  music-clap ~/music --dump ~/.cache/music-clap
  python - <<'PY'
  import numpy as np
  ref = np.load('$HOME/.cache/music-clap/song.npy')
  other = np.load('$HOME/.cache/music-clap/other.npy')
  print(ref @ other / (np.linalg.norm(ref) * np.linalg.norm(other)))
  PY
  ```

  The dump directory mirrors your audio tree; load the `.npy` vectors to script custom similarity
  pipelines.

- **Hint PyTorch to use more CPU cores**

  ```sh
  music-clap ~/music --text "blackened doom metal" --torch-threads 12
  ```

  Adjust `--torch-inter-op-threads` as needed when the default inter-op pool is too small.

## Translations

- Russian translation: [NETWORKS.ru.md](./NETWORKS.ru.md)

