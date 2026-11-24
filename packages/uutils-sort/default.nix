##
# Package: uutils-sort
# Purpose: `uu_sort` built from the pinned uutils-coreutils source with
#   ./parallel-collation-keys.patch, installed as a single `sort` binary so it
#   can override both GNU sort and uutils' own copy through buildEnv priorities.
# Notes:
#   - Under a UTF-8 locale uu_sort computes one ICU collation key per line on
#     the single reader thread, and that serial key computation dominates a
#     plain whole-line sort. The patch computes the keys in parallel blocks and
#     concatenates them in order (the sort itself already compares keys as
#     bytes). Measured against stock uutils 0.12 and GNU 9.12 on trantor, the
#     patched sort is 2-3x faster on shuffled and already-sorted input; output
#     is byte-identical to stock uutils.
#   - Only `sort` is installed on purpose: the rest of the multicall binary is
#     already in system-path via uutils-coreutils-noprefix, and a second full
#     copy would add ~15 MiB for nothing.
#   - src/cargoDeps are reused from nixpkgs' uutils-coreutils, so the vendored
#     crates and the toolchain stay pinned to the same versions.
{
  lib,
  stdenv,
  cargo,
  rustc,
  rustPlatform,
  uutils-coreutils,
}:
stdenv.mkDerivation {
  pname = "uutils-sort";
  version = uutils-coreutils.version;

  src = uutils-coreutils.src;
  cargoDeps = uutils-coreutils.cargoDeps;

  patches = [ ./parallel-collation-keys.patch ];

  # nixpkgs drops it as well: upstream's config hardcodes cross linkers.
  postPatch = "rm -f .cargo/config.toml";

  nativeBuildInputs = [
    cargo
    rustc
    rustPlatform.cargoSetupHook
  ];

  buildPhase = ''
    runHook preBuild
    cargo build --release --offline --locked -p uu_sort
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 target/release/sort $out/bin/sort
    runHook postInstall
  '';

  meta = {
    description = "uutils sort with parallel ICU collation-key computation";
    homepage = "https://github.com/uutils/coreutils";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = [ ];
    mainProgram = "sort";
  };
}
