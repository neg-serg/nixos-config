{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "resterm";
  version = "0.41.1";

  src = fetchurl {
    url = "https://github.com/unkn0wn-root/resterm/releases/download/v0.41.1/resterm_Linux_x86_64";
    hash = "sha256-q0EnBwnDrrdrv+RHYKoxG805WFihL+Jr6YLLq6tu1kE=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/resterm"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal REST client for .http/.rest files with HTTP, GraphQL and gRPC support";
    homepage = "https://github.com/unkn0wn-root/resterm";
    license = licenses.asl20;
    mainProgram = "resterm";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
