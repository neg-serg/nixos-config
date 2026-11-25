##
# Package: shtoy
# Purpose: run Shadertoy-style shaders fullscreen in esshader — the Rust port
#   of the former packages/local-bin/bin/shtoy shell helper. It keeps the CLI,
#   cache layout, diagnostics and viewer invocation of the shell version; the
#   network modes (`--import` through the Shadertoy API, `--mirror` through
#   Sourcegraph) are behind an HTTP trait.
{
  lib,
  rustPlatform,
  makeWrapper,
  esshader,
}:

rustPlatform.buildRustPackage {
  pname = "shtoy";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  # shtoy locates the viewer with a plain PATH lookup (parity with the shell's
  # `command -v esshader`, see src/viewer.rs), so the wrapper supplies it and
  # esshader stays out of the system profile.
  postInstall = ''
    wrapProgram $out/bin/shtoy --prefix PATH : ${lib.makeBinPath [ esshader ]}
  '';

  meta = lib.mkMeta {
    description = "Run Shadertoy shaders fullscreen in esshader";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "shtoy";
  };
}
