{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "repeater";
  version = "0.1.10";

  src = fetchurl {
    url = "https://github.com/shaankhosla/repeater/releases/download/v0.1.10/repeater-x86_64-unknown-linux-gnu.tar.xz";
    hash = "sha256-z54NDmhztJNJulheuYqaicxXYTsacMKU6tZx74B7sCY=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 repeater-x86_64-unknown-linux-gnu/repeater "$out/bin/repeater"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Spaced repetition, in your terminal";
    homepage = "https://github.com/shaankhosla/repeater";
    license = licenses.asl20;
    mainProgram = "repeater";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
