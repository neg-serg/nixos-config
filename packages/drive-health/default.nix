{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-drive-health";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/drive-health;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for SMART drive health monitoring";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
