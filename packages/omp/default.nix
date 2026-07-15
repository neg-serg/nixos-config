{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "16.5.2";
  tag = "v${version}";
in
stdenvNoCC.mkDerivation {
  pname = "omp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/${tag}/omp-linux-x64";
    hash = "sha256-zCyKlY4JrcNDKGBVUXTXDxy84L6Khq9BP/3PLsGMsQ4=";
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents, and more";
    longDescription = ''
      A fork of Pi with batteries included: LSP integration, debugger (DAP) support,
      first-class subagents with isolated worktrees, code execution (Python + Bun),
      time-traveling stream rules, advisor model, and 32 built-in tools.
    '';
    homepage = "https://omp.sh";
    license = licenses.mit;
    mainProgram = "omp";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
