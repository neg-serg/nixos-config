##
# Package: music-apply-tags
# Purpose: Write the ML mood (and optionally the Discogs style) into the audio
#   files, so players and MPD's own `search` see what the tag cache holds. Dry
#   run unless `--apply`; every change is appended to a JSONL log (old -> new)
#   for review or a hand revert; paths outside `--music-dir` are refused.
#
# Rust port of scripts/dev/music-apply-tags.py. One code path through `lofty`:
# Vorbis comments for FLAC/Ogg/Opus, ID3 TMOO/TCON for MP3/WAV, and the
# `----:com.apple.iTunes:MOOD` freeform atom for M4A. aac/wma are reported as
# unsupported. `just music-apply-tags` runs it; the music-tagging module puts it
# on PATH with the rest of the stack.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "music-apply-tags";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Write ML mood/Discogs style tags into audio files (dry run by default)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "music-apply-tags";
  };
}
