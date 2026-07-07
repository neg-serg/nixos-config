{
  stdenv,
  lib,
  fetchurl,
  makeWrapper,
  appimage-run,
}:
let
  version = "1.9.0";
  pname = "bazecor-appimage";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/Dygmalab/Bazecor/releases/download/v${version}/Bazecor-${version}-x64.AppImage";
    hash = lib.fakeHash; # FIXME: replace with real hash after first build (bazecor-1.9.0 AppImage, ~132MB)
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp $src $out/bin/bazecor.appimage
    chmod +x $out/bin/bazecor.appimage
    # AppImage binfmt registration handles execution transparently
    ln -s bazecor.appimage $out/bin/bazecor
    runHook postInstall
  '';

  meta = {
    description = "Bazecor — Dygma keyboard configurator (AppImage)";
    homepage = "https://github.com/Dygmalab/Bazecor";
    license = stdenv.lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bazecor";
  };
}
