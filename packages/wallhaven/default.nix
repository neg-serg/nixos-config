{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-wallhaven";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/wallhaven;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for browsing wallhaven.cc wallpapers";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
