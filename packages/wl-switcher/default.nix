{
  stdenv,
  lib,
}:
stdenv.mkDerivation {
  pname = "vicinae-wl-switcher";
  version = "0.1.0";

  src = ../../files/gui/vicinae-extensions/wl-switcher;

  installPhase = ''
    mkdir -p $out
    cp -r . $out/
  '';

  meta = lib.mkMeta {
    description = "Vicinae extension for wl wallpaper daemon — browse and switch wallpapers";
    license = lib.licenses.mit;
  };
}
