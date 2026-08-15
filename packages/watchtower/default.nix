{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "watchtower";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/lajosdeme/watchtower/releases/download/v1.0.0/watchtower_Linux_x86_64.tar.gz";
    hash = "sha256-8xVFQ4+IhxOT3QFVEoSEZiTVl3ejuxnw4ZxmUL4/ObE=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 watchtower "$out/bin/watchtower"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A clean, minimal, terminal-based global intelligence dashboard";
    homepage = "https://github.com/lajosdeme/watchtower";
    license = licenses.mit;
    mainProgram = "watchtower";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
