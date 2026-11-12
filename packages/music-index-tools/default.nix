##
# Package: music-index-tools
# Purpose: Build and query the MERT music similarity index (`music-index`,
#   `music-similar`). The Rust port of packages/local-bin/lib/music_index.py and
#   music_similar.py: same CLI, cache keys, index layout and self-tests.
#
# The model itself stays Python: the indexer shells out to the existing
# `music-embed` executable (PATH, or `MUSIC_EMBED_BIN`) for every batch of
# embeddings. The `.npy` reader/writer is in-crate (float32, C order,
# little-endian, v1/v2 headers), so there is no numpy dependency here.
#
# `just music-selftest` runs both `--selftest` modes with the deterministic
# SHAKE-128 stub embedder: no torch, model or venv needed.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "music-index-tools";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Build and query the MERT music similarity index (music-index, music-similar)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "music-index";
  };
}
