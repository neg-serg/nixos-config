{
  stdenv,
  fetchzip,
  jdk,
  makeWrapper,
  lib,
}:

stdenv.mkDerivation rec {
  pname = "joern";
  version = "4.0.599";

  src = fetchzip {
    url = "https://github.com/joernio/joern/releases/download/v${version}/joern-cli-linux-x86_64.zip";
    hash = "sha256-xLFX9gRUdliTNT3gGfd2ajelyh8vGhlw87xkBg8punE=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ jdk ];

  installPhase = ''
    mkdir -p $out/bin $out/share/joern
    cp -r . $out/share/joern
    for bin in joern joern-parse joern-export joern-scan joern-flow joern-slice joern-vectors; do
      if [ -f $out/share/joern/$bin ]; then
        chmod +x $out/share/joern/$bin
        ln -s $out/share/joern/$bin $out/bin/$bin
        wrapProgram $out/bin/$bin --prefix PATH : ${lib.makeBinPath [ jdk ]}
      fi
    done
  '';

  meta = with lib; {
    description = "Open-source code analysis platform for C/C++, Java, JS, Python, and more";
    homepage = "https://joern.io";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "joern";
  };
}
