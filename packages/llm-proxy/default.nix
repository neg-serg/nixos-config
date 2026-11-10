{ lib, python3 }:
python3.pkgs.buildPythonApplication {
  pname = "llm-proxy";
  version = "0.1.0";
  format = "other";
  src = ./.;
  dontBuild = true;
  # Stdlib-only regression suite (no pytest in the closure): it covers the
  # guards that are easy to break silently — the single-system-message
  # invariant, tool-result normalization, and the trimming invariants.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3.interpreter} -m unittest discover -s . -p 'test_*.py' -v
    runHook postCheck
  '';
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
