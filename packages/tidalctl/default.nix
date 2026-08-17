##
# Package: tidalctl
# Purpose: TidalCycles session controller — SuperDirt engine start/stop/status,
#   opens the editor, records output, monitors PipeWire. Rust CLI replacing the
#   old `just tidal-*` recipes.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "tidalctl";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "TidalCycles session controller — engine start/stop, editor, recording";
    longDescription = ''
      CLI for managing a TidalCycles live-coding session on NixOS:
      starts/stops the SuperDirt engine (sclang + scsynth) with the correct
      PipeWire-jack LD_LIBRARY_PATH, opens the editor in the tidal workspace,
      records SuperDirt output, and monitors the PipeWire graph.
    '';
    homepage = "https://github.com/neg-serg/nixos-config";
    license = licenses.mit;
    mainProgram = "tidalctl";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
