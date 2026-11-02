##
# Package: mpd-voice
# Purpose: Voice control for MPD — one microphone utterance becomes an intent
#   ("next track", "volume 40", "play album …") and is executed against the
#   Music Player Daemon; the confirmation is spoken back through the same local
#   speech stack.
#
# Rust, no crates: the MPD wire protocol, the HTTP speech clients, the OSC-free
# config reader and the intent parser are all std. Speech recognition and
# synthesis stay outside the client — capture goes through pw-record/arecord/
# ffmpeg/sox (or a command template), STT through an OpenAI-compatible endpoint
# or whisper.cpp, TTS through piper or a local tool — because those are
# deployment decisions, not program decisions.
#
# The binary used to be a Python package; the port replaced it file for file,
# and its behaviour is pinned by the tests in `src/` (104 of them, run in the
# sandbox build below, including an in-process fake MPD).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "mpd-voice";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Voice control for MPD: local speech recognition into player commands";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "mpd-voice";
  };
}
