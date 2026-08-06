{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-fd-search";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/fd-search;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for fast filesystem search powered by fd";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
