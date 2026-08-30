## Package: glm-osc
## Purpose: OSC bridge to Genelec SAM monitors via the genlc Python module
##   (alternative to the official GLM software; controls volume/mute/power/status
##   over the GLM USB adapter 1781:0e39 without the GLM app running).
{
  lib,
  stdenv,
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
        rev = "master";
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
    ps.python-osc
  ]);
in
stdenv.mkDerivation {
  pname = "glm-osc";
  version = "0.1.0";
  src = ./.;
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${py}/bin/python $out/bin/glm-osc-server \
      --set LD_LIBRARY_PATH "${hidapi}/lib" \
      --set-default GENLC_CLI "${py}/bin/genlc" \
      --set-default GLM_OSC_STATE "$HOME/.local/state/glm-osc-state.json" \
      --add-flags "${./server.py}"
  '';
  meta = with lib; {
    description = "OSC bridge for Genelec SAM monitors (genlc-based, no official GLM)";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
