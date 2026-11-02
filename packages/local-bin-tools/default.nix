##
# Package: local-bin-tools
# Purpose: Small `$PATH` helpers that used to be Python scripts in
#   packages/local-bin/scripts: `fetch-covers` (missing album covers via sacad)
#   and `gen-unbound-hosts` (regenerate hosts/trantor/unbound-hosts.nix from its
#   sources; `just unbound-hosts` runs it).
#
# Rust, no crates.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "local-bin-tools";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Small $PATH helpers (album covers, unbound host entries)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "gen-unbound-hosts";
  };
}
