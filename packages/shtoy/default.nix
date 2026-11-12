##
# Package: shtoy
# Purpose: run Shadertoy-style shaders fullscreen in esshader — the Rust port
#   of the former packages/local-bin/bin/shtoy shell helper. It keeps the CLI,
#   cache layout, diagnostics and viewer invocation of the shell version; the
#   network modes (`--import` through the Shadertoy API, `--mirror` through
#   Sourcegraph) are behind an HTTP trait so the test suite uses fixtures only.
#
#   `cargo test` covers id parsing, --list ordering/shadowing, the byte-exact
#   shader rewrite, texture2D legacy detection, Sourcegraph ranking from a fixture
#   NDJSON stream, API JSON extraction, and CLI parity for all local paths.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "shtoy";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Run Shadertoy shaders fullscreen in esshader";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "shtoy";
  };
}
