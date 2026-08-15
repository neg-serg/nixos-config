{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "ghgrab";
  version = "2.0.1";

  src = fetchurl {
    url = "https://github.com/abhixdd/ghgrab/releases/download/v2.0.1/ghgrab-linux";
    hash = "sha256-+pb0Z/VO+1wbZdaelQtciBXGoZqO7DXnSV40ln/fNPU=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/ghgrab"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Search and download files from GitHub without leaving your CLI";
    homepage = "https://github.com/abhixdd/ghgrab";
    license = licenses.mit;
    mainProgram = "ghgrab";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
