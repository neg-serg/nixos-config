{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-aura";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/aura;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = lib.mkMeta {
    description = "Vicinae extension for the Aura emotion/CBT diary: record a note by voice or text";
    license = lib.licenses.mit;
  };
}
