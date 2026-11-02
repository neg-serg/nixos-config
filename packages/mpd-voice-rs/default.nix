##
# Package: mpd-voice-rs
# Purpose: Stage 1 of the mpd-voice port to Rust — the MPD wire-protocol client,
#   the TOML config loader with its environment overrides, and the read-only
#   commands (`status`, `doctor`, `ping`, `config`). No crates: the daemon
#   protocol is line based and the config file is a flat table of scalars.
#
# The installed `mpd-voice` is still the Python package (capture, STT/TTS and
# the intent parser live there). This crate becomes the package once the port
# reaches parity; until then it exists for `nix build .#mpd-voice-rs`, whose
# checkPhase runs the unit tests.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "mpd-voice-rs";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Voice control for MPD — Rust port in progress (MPD client, config, status)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "mpd-voice-rs";
  };
}
