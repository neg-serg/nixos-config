{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "simutil";
  version = "0.5.0";

  src = fetchurl {
    url = "https://github.com/dungngminh/simutil/releases/download/v0.5.0/simutil-linux-x64.tar.gz";
    hash = "sha256-SyrDsZIdpXZ2WGfrPzdW+eBHXb2x4Pb7Elk+cvcQLZA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 simutil-linux-x64 "$out/bin/simutil"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Cross platform utility TUI app for launching iOS simulators / Android emulators";
    homepage = "https://github.com/dungngminh/simutil";
    license = licenses.mit;
    mainProgram = "simutil";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
