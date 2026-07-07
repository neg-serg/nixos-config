{
  stdenv,
  lib,
  fetchurl,
}:
let
  version = "1.9.0";
  pname = "bazecor-appimage";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/Dygmalab/Bazecor/releases/download/v${version}/Bazecor-${version}-x64.AppImage";
    hash = "sha256-DAUqQf6Sku4oz3vR+bxAXfPtu2sJREbp5a6Mpj90dM0=";
  };

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
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bazecor";
  };
}
