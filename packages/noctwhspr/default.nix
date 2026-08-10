{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-noctwhspr";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/noctwhspr;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for hyprwhspr dictation control";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
