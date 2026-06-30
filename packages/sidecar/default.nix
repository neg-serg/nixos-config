{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "sidecar";
  version = "0.77.0";

  src = fetchurl {
    url = "https://github.com/marcus/sidecar/releases/download/v0.77.0/sidecar_0.77.0_linux_amd64.tar.gz";
    hash = "sha256-PXXRlHaresWxWgrDv1XUST7/DWEINAoGJotwp+mqJrQ=";
  };

  sourceRoot = ".";

  installPhase = ''
    install -Dm755 sidecar $out/bin/sidecar
  '';

  meta = with lib; {
    description = "AI agent tool for code assistance";
    homepage = "https://github.com/marcus/sidecar";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sidecar";
  };
}
