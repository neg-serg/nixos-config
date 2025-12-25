# music_clap

Standalone CLI to compute LAION-CLAP embeddings for audio files.

```sh
music-clap ~/music --text "dreamy shoegaze" --dump ~/.cache/music-clap
```

## CPU parallelism

By default PyTorch chooses a conservative number of CPU worker threads. Use the new flags to let
CLAP analysis utilise more cores:

```sh
music-clap track.flac --text "blackened doom metal" --torch-threads 8
```

`--torch-inter-op-threads` is also available when you need to tune PyTorch's operator inter-op pool
separately.

## Checkpoints & cache

`music-clap` writes nothing into the Nix store. Model checkpoints download to `$LAION_CLAP_CACHE`
(or `$XDG_CACHE_HOME/laion_clap`, falling back to `~/.cache/laion_clap`). To persist per-track
embeddings, pass `--dump` so the CLI mirrors your audio tree into a writable directory:

```sh
music-clap ~/music --text "doom metal" --dump ~/.cache/music-clap
```

Without `--dump` the embeddings stay in memory and are not saved.

When a dump directory is provided, subsequent runs reuse the cached `.npy` embeddings. Pass
`--refresh` to ignore existing files and recompute vectors.
