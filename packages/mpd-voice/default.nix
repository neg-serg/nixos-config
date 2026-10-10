{
  lib,
  python3Packages,
  ...
}:
python3Packages.buildPythonApplication rec {
  pname = "mpd-voice";
  version = "0.1.0";

  format = "pyproject";
  src = ./.;

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
  ];

  # The suite is plain unittest and needs no test framework, so nothing is
  # pulled in just to run it.  Tests that want a real MPD or whisper.cpp skip
  # themselves, which keeps the sandbox build hermetic.
  preCheck = ''
    export PYTHONPATH="$PWD/src''${PYTHONPATH:+:$PYTHONPATH}"
  '';
  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests -t . -v
    runHook postCheck
  '';

  meta = lib.mkMeta {
    description = "Voice control for MPD: local speech recognition into player commands";
    license = lib.licenses.mit;
    mainProgram = "mpd-voice";
  };
}
