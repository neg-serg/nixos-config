##
# CamillaEQ — the browser equalizer for CamillaDSP (the neg-serg fork).
#
# Upstream is a two-workspace npm monorepo: a Svelte/Vite client that talks to
# CamillaDSP over its own websocket, and a Fastify server for the config
# library, the settings and the static build. `npm run build` is vite -> tsc ->
# client copied into `server/dist/client`, which is the tree this installs and
# the only thing the unit runs.
#
# The runtime tree is a *production* install (`npm ci --omit=dev`) built from
# the same lockfile the derivation already fetched: the client's toolchain
# (vite, svelte-check, vitest) is build-time only and must not sit in the
# closure. `server/dist` is written before that step and survives it — npm ci
# only rewrites `node_modules`.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:
let
  # Upstream `package.json` `version`; the app is a web UI and reports it on
  # `/api/version`, so a bump is this line plus the two hashes.
  version = "0.1.5";
in
buildNpmPackage {
  pname = "camillaeq";
  inherit version;

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "camillaeq";
    rev = "e8afd8de351b1d759c5a7b6a93aa2a7e8418d64c";
    hash = "sha256-35s5bIgd9545Agta+FZkgpstN/dpKCdNgl9KkipWXcs=";
  };

  # Filled from the build's own "got:" hash on the first failed run.
  npmDepsHash = "sha256-c4Kh5LIw9ymm/9BjXR2pWMVqUnbidTow0KrwU8g6Go8=";

  installPhase = ''
    runHook preInstall

    app=$out/lib/camillaeq
    mkdir -p $app/server $app/client

    # What the server resolves at runtime: the compiled Fastify app with the
    # built client inside it, and the workspace manifests npm ci needs to
    # replay the lockfile (the workspaces are `server` and `client`).
    cp package.json package-lock.json $app/
    cp server/package.json $app/server/
    cp client/package.json $app/client/
    cp -r server/dist $app/server/dist

    pushd $app
    npm ci --omit=dev --offline --no-audit --no-fund
    popd

    mkdir -p $out/bin
    cat > $out/bin/camillaeq <<'SH'
    #!/bin/sh
    # CamillaEQ keeps its config library in CONFIG_DIR (./data by default,
    # relative to the process), so the tree gets an absolute XDG one and the
    # directory exists before the server opens it.
    set -eu
    state="''${CONFIG_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/camillaeq}"
    mkdir -p "$state/configs"
    export CONFIG_DIR="$state"
    exec @node@ @app@/server/dist/index.js "$@"
    SH
    substituteInPlace $out/bin/camillaeq \
      --replace-fail "@node@" "${lib.getExe nodejs}" \
      --replace-fail "@app@" "$app"
    chmod +x $out/bin/camillaeq

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Browser-based graphical equalizer and spectrum analyzer for CamillaDSP";
    homepage = "https://github.com/neg-serg/camillaeq";
    license = lib.licenses.mit;
    mainProgram = "camillaeq";
  };
}
