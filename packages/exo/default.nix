{
  lib,
  stdenv,
  exo-src,
}:
stdenv.mkDerivation {
  pname = "exo";
  version = "unstable";
  src = exo-src;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/exo
    cp -r ignis $out/share/exo/
    cp -r matugen $out/share/exo/
    cp -r exodefaults $out/share/exo/

    install -Dm644 LICENSE $out/share/licenses/exo/LICENSE
  '';

  meta = with lib; {
    description = "Material 3 inspired desktop shell for Niri and Hyprland created with Ignis";
    homepage = "https://github.com/debuggyo/Exo";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
