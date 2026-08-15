{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "strace-tui";
  version = "1.0.1";

  src = fetchurl {
    url = "https://github.com/Rodrigodd/strace-tui/releases/download/v1.0.1/strace-tui-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-t1eeN6DgHF6ndYQpL3ryhLHA4L8ZmYFmWCgjfw8npCw=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 strace-tui "$out/bin/strace-tui"
    runHook postInstall
  '';

  meta = with lib; {
    description = "TUI for visualizing and exploring strace output";
    homepage = "https://github.com/Rodrigodd/strace-tui";
    license = licenses.mit;
    mainProgram = "strace-tui";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
