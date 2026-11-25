##
# Package: local-bin-audio
# Purpose: Rust ports of the audio/session helpers in `packages/local-bin/bin`:
#   `audio-diag` (PipeWire/RME routing health), `jam` (Vital + SuperCollider
#   live session), `shabda` (Freesound packs for Tidal/Strudel), `synth`
#   (run-or-raise), `midi-bridge` (SC MIDI -> Renoise / Midi Through),
#   `renoise-osc-config` (pin the OSC server in Config.xml), `sc-live`,
#   `sc-record`, `flacspec`, `mp`, `nb` and `qe`.
#
#   One multicall binary; every installed command name is an argv[0] symlink to
#   it. Every command keeps the shell original's CLI/usage text, stdout/stderr
#   split, exit codes, environment defaults, file formats and external command
#   argv (`pw-link`, `wpctl`, `amixer`, `pw-record`, `aconnect`, `systemctl`,
#   `pgrep`, `sox`, `mpv`, `hyprctl`, `git`, ...). Shell logic (option parsing,
#   text filters, the renoise Config.xml rewrite that used to be a `python3`
#   heredoc, state files) is native. The crate's only dependency is the shared
#   `local-bin-core` helper crate, and it forbids `unsafe`.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-audio";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-audio";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in audio-diag jam shabda synth midi-bridge renoise-osc-config \
      sc-live sc-record flacspec mp nb qe; do
      ln -s local-bin-audio "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the audio helpers from packages/local-bin/bin (audio-diag, jam, shabda, synth, midi-bridge, renoise-osc-config, sc-live, sc-record, flacspec, mp, nb, qe), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "audio-diag";
  };
}
