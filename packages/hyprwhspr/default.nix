{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-hyprwhspr";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/hyprwhspr;

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
