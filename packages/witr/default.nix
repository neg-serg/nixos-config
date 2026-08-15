{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "witr";
  version = "0.3.2";

  src = fetchurl {
    url = "https://github.com/pranshuparmar/witr/releases/download/v0.3.2/witr-linux-amd64";
    hash = "sha256-dGDP0Jn/QaJKCJ5vYESWwipB1GY3ScsRtAFAGYmOFtQ=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/witr"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A Linux CLI tool that explains the causal chain behind running processes";
    homepage = "https://github.com/pranshuparmar/witr";
    license = licenses.asl20;
    mainProgram = "witr";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
