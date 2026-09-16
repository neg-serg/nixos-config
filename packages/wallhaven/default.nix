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

  meta = lib.mkMeta {
    description = "Vicinae extension for browsing wallhaven.cc wallpapers";
    license = lib.licenses.mit;
  };
}
