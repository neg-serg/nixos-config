{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "lazytail";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/raaymax/lazytail/releases/download/v0.10.0/lazytail-linux-x86_64.tar.gz";
    hash = "sha256-Ks94hsUJ6eT3YRyvGj7nB27hFaLyvLNDN4xgJNcBjWQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 lazytail "$out/bin/lazytail"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A fast, universal terminal-based log viewer with live filtering and follow mode";
    homepage = "https://github.com/raaymax/lazytail";
    license = licenses.mit;
    mainProgram = "lazytail";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
