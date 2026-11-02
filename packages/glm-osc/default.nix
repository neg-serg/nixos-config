## Package: glm-osc
## Purpose: OSC bridge to Genelec SAM monitors via the genlc Python module
##   (alternative to the official GLM software; controls volume/mute/power/status
##   over the GLM USB adapter 1781:0e39 without the GLM app running).
##
## The bridge itself is Rust (src/main.rs): OSC over UDP, the state file and the
## replies are hand-rolled, no python-osc. `genlc` stays a Python CLI because it
## *is* the third-party implementation of the GLM USB protocol — reimplementing
## that would be a different project, so the wrapper pins its interpreter and
## the hidapi library path.
{
  lib,
  rustPlatform,
  python3,
  fetchFromGitHub,
  fetchPypi,
  hidapi,
  makeWrapper,
}:

let
  libscrc = python3.pkgs.buildPythonPackage rec {
    pname = "libscrc";
    version = "1.8.1";
    format = "setuptools";
    src = fetchPypi {
      inherit pname version;
      sha256 = "1j575dq5hizim4y2w9am87mdi5vgdigpklqakmr3pszx7kr6pfnp";
    };
    doCheck = false;
  };
  py = python3.withPackages (ps: [
    (ps.buildPythonPackage rec {
      pname = "genlc";
      version = "0.1.0";
      src = fetchFromGitHub {
        owner = "markbergsma";
        repo = "genlc";
        # Pinned to the master tip (2021-08-29): the repo has seen no commits
        # since, and this SHA's tarball hashes to the sha256 recorded below
        # (verified with nix-prefetch-url --unpack). Was `rev = "master"`, the
        # last floating rev in packages/ (audit 2026-09-15).
        rev = "a210f8b5e15df8ff7be38f4aa7089860272cf90b";
        sha256 = "sha256-26cM5Cz4KdDLQsIUJ+qqaQByDvwyz7Uif1t79IFID30=";
      };
      pyproject = true;
      build-system = [ ps.poetry-core ];
      dependencies = [
        ps.hid
        libscrc
        ps.click
      ];
    })
    ps.hid
    libscrc
    ps.click
  ]);
in
rustPlatform.buildRustPackage {
  pname = "glm-osc";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  # genlc controls the monitors over hidapi, so both the interpreter and the
  # library path have to come from the store; GLM_OSC_STATE keeps the volume
  # across restarts.
  postInstall = ''
    wrapProgram $out/bin/glm-osc-server \
      --prefix PATH : ${lib.makeBinPath [ py ]} \
      --set LD_LIBRARY_PATH "${hidapi}/lib" \
      --set-default HIDAPI_LIB "${hidapi}/lib" \
      --set-default GENLC_CLI "${py}/bin/genlc" \
      --set-default GLM_OSC_STATE "$HOME/.local/state/glm-osc-state.json"
  '';

  meta = lib.mkMeta {
    description = "OSC bridge for Genelec SAM monitors (genlc-based, no official GLM)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.gpl3Plus;
    mainProgram = "glm-osc-server";
  };
}
