##
# Package: wyoming-openai
# Purpose: Wyoming protocol proxy for OpenAI-compatible STT/TTS endpoints.
# Source: https://github.com/roryeckel/wyoming-openai
# Dependencies: openai, wyoming, pysbd (all from python3Packages)
{
  lib,
  python3,
  fetchFromGitHub,
  writeShellScript,
  ...
}:
let
  pyPkgs = python3.pkgs;
  pythonBin = lib.getExe python3;
  version = "0.3.10";

  # Upstream has no console_scripts entry point; create a wrapper for `python -m wyoming_openai`
  wrapper = writeShellScript "wyoming-openai" ''
    exec ${pythonBin} -m wyoming_openai "$@"
  '';
in
pyPkgs.buildPythonApplication {
  pname = "wyoming-openai";
  inherit version;

  src = fetchFromGitHub {
    owner = "roryeckel";
    repo = "wyoming-openai";
    rev = "v${version}";
    hash = lib.fakeHash; # Set real hash: nix build 2>&1 | grep "got:\|expected:"
  };

  pyproject = true;

  build-system = [
    pyPkgs.setuptools
  ];

  dependencies = [
    pyPkgs.openai          # == 2.8.1 (nixpkgs: 2.33.0 — compatible)
    pyPkgs.wyoming         # == 1.8.0 (nixpkgs: 1.9.0 — compatible)
    pyPkgs.pysbd           # == 0.3.4 (nixpkgs: 0.3.4 — exact)
  ];

  postInstall = ''
    mkdir -p $out/bin
    ln -s ${wrapper} $out/bin/wyoming-openai
  '';

  doCheck = false;

  meta = with lib; {
    description = "OpenAI-Compatible Proxy Middleware for the Wyoming Protocol";
    longDescription = ''
      A Wyoming server that connects to OpenAI-compatible STT/TTS endpoints.
      Enables Wyoming clients (e.g. Home Assistant) to use transcription
      and text-to-speech from OpenAI, Speaches, LocalAI, Kokoro, and more.
    '';
    homepage = "https://github.com/roryeckel/wyoming-openai";
    license = licenses.asl20;
    mainProgram = "wyoming-openai";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
