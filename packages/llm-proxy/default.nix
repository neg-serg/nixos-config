{ lib, python3 }:
python3.pkgs.buildPythonApplication {
  pname = "llm-proxy";
  version = "0.1.0";
  format = "other";
  src = ./.;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 main.py $out/bin/llm-proxy
    runHook postInstall
  '';
  meta = {
    description = "Context guard and tool-protocol normalizer in front of llama-swap";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "llm-proxy";
    maintainers = [ ];
  };
}
