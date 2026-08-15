{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation {
  pname = "reddix";
  version = "0.2.9";

  src = fetchurl {
    url = "https://github.com/ck-zhang/reddix/releases/download/v0.2.9/reddix-x86_64-unknown-linux-gnu.tar.xz";
    hash = "sha256-XRGV/mcpv+fUGwx8mq0S4eEcHrlTLWjZcEhh1BMXkgE=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 reddix-x86_64-unknown-linux-gnu/reddix "$out/bin/reddix"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Reddit, refined for the terminal";
    homepage = "https://github.com/ck-zhang/reddix";
    license = licenses.mit;
    mainProgram = "reddix";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
