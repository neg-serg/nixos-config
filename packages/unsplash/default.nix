{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-unsplash";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/unsplash;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for browsing Unsplash wallpapers";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
