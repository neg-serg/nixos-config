##
# Package: renoise-osc
# Purpose: Send OSC messages to Renoise's built-in OSC server from the shell
#   (UDP 127.0.0.1:9002 by default). Commands: status/eval/reverb/load,
#   transport, bpm/lpb/tpl, loop, track/instr/device mixing, record (pw-record
#   of the Renoise audio) and raw OSC patterns; `renoise-osc help <cmd>` has
#   examples.
#
# Rust, no runtime dependencies: the OSC encoder is ~40 lines of std code, so
# there is no interpreter and no crate behind the binary. `renoise-reverb` and
# `renoise-record` are symlinks to the same binary and prepend their subcommand
# from argv[0]. Renoise's OSC socket stays UDP on 9002 — pin it with Preferences
# -> OSC while Renoise is closed.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "renoise-osc";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  postInstall = ''
    ln -s renoise-osc $out/bin/renoise-reverb
    ln -s renoise-osc $out/bin/renoise-record
  '';

  meta = lib.mkMeta {
    description = "Send OSC messages to Renoise's built-in OSC server from the shell";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "renoise-osc";
  };
}
