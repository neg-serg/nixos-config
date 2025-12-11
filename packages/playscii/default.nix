{
  lib,
  fetchhg,
  python3Packages,
  makeDesktopItem,
  copyDesktopItems,
}:
python3Packages.buildPythonApplication rec {
  pname = "playscii";
  version = "9.17.1";

  src = fetchhg {
    url = "https://heptapod.host/jp-lebreton/playscii";
    rev = version;
    sha256 = "0fck5hs4ly1fnjwy658slry5q9c7b2b6mj86pmbgx1swiw3iw0kc";
  };

  format = "other";

  propagatedBuildInputs = with python3Packages; [
    pysdl2
    pyopengl
    numpy
    pillow
    appdirs
  ];

  nativeBuildInputs = [
    copyDesktopItems
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/playscii
    cp -r * $out/share/playscii

    mkdir -p $out/bin
    makeWrapper ${python3Packages.python.interpreter} $out/bin/playscii \
      --add-flags "$out/share/playscii/playscii.py" \
      --prefix PYTHONPATH : "$PYTHONPATH:$out/share/playscii" \
      --run "cd $out/share/playscii"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "playscii";
      exec = "playscii";
      icon = "playscii";
      comment = "ASCII art, animation, game creation tool";
      desktopName = "Playscii";
      categories = ["Graphics" "Art"];
    })
  ];

  meta = with lib; {
    description = "Open source ASCII art and animation program";
    homepage = "http://vectorpoem.com/playscii/";
    license = licenses.mit;
    mainProgram = "playscii";
  };
}
