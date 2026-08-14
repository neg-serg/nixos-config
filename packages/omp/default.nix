{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  bun,
  stdenv,
}:
let
  version = "17.3.4";
in
buildNpmPackage {
  pname = "omp";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@oh-my-pi/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-2bRsv9r8FGqL4hrTEJQW/qViU7eDwOmYSzqZgaIj5r0=";
  };

  npmDepsHash = "sha256-u1kVT5PBZIKqNxsTSuVbcV+k2+NFEXuPl7njWT9PU2w=";
  npmDepsFetcherVersion = 2;

  dontNpmBuild = true;
  # onnxruntime-node tries to download native binaries from nuget.org in its install script
  npmInstallFlags = [ "--ignore-scripts" ];
  # Prevent node-gyp rebuild from also triggering scripts
  npmRebuildFlags = [ "--ignore-scripts" ];

  makeCacheWritable = true;

  buildInputs = [ stdenv.cc.cc.lib ];
  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # Inject package-lock.json (not bundled in the npm tarball)
    cp ${./package-lock.json} package-lock.json
    # Patch bun version check (nixpkgs bun 1.3.13, omp wants >=1.3.14)
    sed -i 's/1\.3\.14/1.3.13/g' dist/cli.js
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/omp $out/bin
    cp -r . $out/share/omp/
    # Use bun as runtime (omp uses bun-specific APIs)
    makeWrapper ${lib.getExe bun} $out/bin/omp \
      --add-flags "run $out/share/omp/dist/cli.js" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
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
