{
  lib,
  python3,
  inputs,
  makeWrapper,
  xdotool,
  xclip,
}:
let
  pyPkgs = python3.pkgs;
  version = "1.0.0+${inputs.talktype.shortRev or "dirty"}";
in
pyPkgs.buildPythonApplication {
  pname = "talktype";
  inherit version;
  pyproject = true;

  src = inputs.talktype;

  build-system = [
    pyPkgs.setuptools
  ];

  dependencies = [
    pyPkgs.numpy
    pyPkgs.scipy
    pyPkgs.sounddevice
    pyPkgs.pynput
    pyPkgs.pyperclip
    pyPkgs.requests
    pyPkgs.rich
    pyPkgs.pyyaml
    pyPkgs.beaupy
    pyPkgs.faster-whisper
  ];

  nativeBuildInputs = [
    makeWrapper
  ];

  postFixup = ''
    wrapProgram $out/bin/talktype \
      --prefix PATH : ${lib.makeBinPath [ xdotool xclip ]}
  '';

  pythonImportsCheck = [ "talktype" ];

  meta = with lib; {
    description = "Push-to-talk voice typing that works everywhere";
    homepage = "https://github.com/lmacan1/talktype";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "talktype";
  };
}
