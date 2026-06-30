{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "proxypilot";
  version = "0.3.0-dev-0.40";

  src = fetchurl {
    url = "https://github.com/Finesssee/ProxyPilot/releases/download/v0.3.0-dev-0.40/proxypilot-linux-amd64";
    hash = "sha256-1hGxvJTm092gPtH9wI/DvlorH2bljnfmONJsmHSkShA=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/proxypilot
  '';

  meta = with lib; {
    description = "Local AI proxy for coding tools (Claude Code, OpenCode)";
    homepage = "https://github.com/Finesssee/ProxyPilot";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "proxypilot";
  };
}
