{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  bun,
}:

let
  version = "17.0.0";
in
buildNpmPackage {
  pname = "omp";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@oh-my-pi/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-MXd6v2uGMajtdCTjDdpLHAoSHE89/bMIkNmVbGersJI=";
  };

  npmDepsHash = "sha256-7r7P+3HS69hh6S9FuJiVHqNef9xqOQhiTLJk8IqOTRs=";

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # Patch bun version check (nixpkgs bun 1.3.13, omp wants >=1.3.14)
    sed -i 's/1\.3\.14/1.3.13/g' dist/cli.js
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/omp $out/bin
    cp -r . $out/share/omp/
    # Use bun as runtime (omp uses bun-specific APIs)
    makeWrapper ${lib.getExe bun} $out/bin/omp \
      --add-flags "run $out/share/omp/dist/cli.js"
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
