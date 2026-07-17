{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  bun,
  python3,
}:

let
  version = "17.0.1";
in
buildNpmPackage {
  pname = "omp";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@oh-my-pi/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-bJ3s6uLJW0Eb9xQr+2wDBrBC2FLfj6hoPQ3Lbvog6H4=";
  };

  npmDepsHash = "sha256-z1fcxkRbw1x4H9W1f9bHinrcf+34Na1/gJJej2GaUSI=";
  npmDepsFetcherVersion = 2;

  dontNpmBuild = true;
  # onnxruntime-node tries to download native binaries from nuget.org in its install script
  npmInstallFlags = [ "--ignore-scripts" ];
  # Prevent node-gyp rebuild from also triggering scripts
  npmRebuildFlags = [ "--ignore-scripts" ];

  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # Inject package-lock.json (not bundled in the npm tarball)
    cp ${./package-lock.json} package-lock.json
    # Downgrade @oh-my-pi/* deps in package.json to match lockfile (17.0.0)
    ${lib.getExe python3} -c "
import json
with open('package.json') as f:
    pkg = json.load(f)
for dep in list(pkg.get('dependencies', {})):
    if dep.startswith('@oh-my-pi/'):
        pkg['dependencies'][dep] = '17.0.0'
with open('package.json', 'w') as f:
    json.dump(pkg, f, indent=2)
    f.write('\n')
"
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
