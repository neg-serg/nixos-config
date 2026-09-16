# Decay GTK3 theme — the GTK side of the FVWM "An essence of decay" rice.
#
# Upstream: github.com/decaycs/gtk3 (variant `decay`, commit 07dbf07, 2022-10-24,
# the revision the rice used: gtk-theme-name=decay in ~/.config/gtk-3.0). The
# sources are vendored under files/x11/decay-gtk/ (see its UPSTREAM.txt) so the
# build needs nothing but sass and stays reproducible offline.
{
  lib,
  stdenv,
  sass,
}:
stdenv.mkDerivation {
  pname = "decay-gtk-theme";
  version = "unstable-2022-10-24";

  src = ../../files/x11/decay-gtk;

  nativeBuildInputs = [
    sass # dart-sass: compiles src/gtk-3.0/gtk.scss (upstream Makefile's `sass` step)
  ];

  buildPhase = ''
    runHook preBuild
    mkdir -p dist/gtk-3.0
    sass src/gtk-3.0/gtk.scss dist/gtk-3.0/gtk.css
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # Directory name is the GTK theme name: GTK_THEME=decay (set by the session).
    install -d $out/share/themes/decay
    install -m644 index.theme $out/share/themes/decay/index.theme
    cp -r assets dist/gtk-3.0 $out/share/themes/decay/
    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "GTK3 port of the Decay colour scheme (FVWM rice)";
    homepage = "https://github.com/decaycs/gtk3";
    license = lib.licenses.gpl3Only;
  };
}
