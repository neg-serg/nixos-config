##
# Package: local-bin-audio
# Purpose: Rust ports of the audio/session helpers in `packages/local-bin/bin`:
#   `audio-diag` (PipeWire/RME routing health), `jam` (Vital + SuperCollider
#   live session), `shabda` (Freesound packs for Tidal/Strudel), `synth`
#   (run-or-raise), `midi-bridge` (SC MIDI -> Renoise / Midi Through),
#   `renoise-osc-config` (pin the OSC server in Config.xml), `sc-live`,
#   `sc-record`, `flacspec`, `mp`, `nb` and `qe`.
#
#   Every binary keeps the shell original's CLI/usage text, stdout/stderr split,
#   exit codes, environment defaults, file formats and external command argv
#   (`pw-link`, `wpctl`, `amixer`, `pw-record`, `aconnect`, `systemctl`,
#   `pgrep`, `sox`, `mpv`, `hyprctl`, `git`, ...). Shell logic (option parsing,
#   text filters, the renoise Config.xml rewrite that used to be a `python3`
#   heredoc, state files) is native. The crate has no dependencies and forbids
#   `unsafe`.
#
#   `cargo test` is hermetic: every external program is a fake shell script
#   first on an otherwise empty PATH, HOME/TMPDIR/XDG_RUNTIME_DIR point into a
#   per-case temporary tree, and the fakes log their argv. `tests/parity.sh`
#   additionally runs the shipped scripts and the ports side by side against the
#   same fakes.
{
  lib,
  rustPlatform,
  bash,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-audio";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests' fakes are `#!/bin/sh` scripts; a build sandbox does not
  # necessarily provide /bin/sh, so the interpreter comes from nixpkgs.
  preCheck = ''
    export LOCAL_BIN_AUDIO_TEST_SHELL=${bash}/bin/bash
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the audio helpers from packages/local-bin/bin";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "audio-diag";
  };
}
