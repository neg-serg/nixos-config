{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-nix-monitor";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/nix-monitor;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = with lib; {
    description = "Vicinae extension for NixOS update and generation monitoring";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
