{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  node-gyp,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  python3,
  removeReferencesTo,
  srcOnly,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "sola-mpd";
  version = "4.11.0";

  src = fetchFromGitHub {
    owner = "prokosna";
    repo = "sola_mpd";
    tag = "v${finalAttrs.version}";
    hash = "sha256-FOGTaK5odKHR2nh6r+vMS4ymGIvMjxHRSG+cLZPpIbs=";
  };

  # The upstream server binds every interface (server.listen(PORT)); the patch
  # adds the HOST override and defaults it to loopback — see the patch header.
  patches = [ ./listen-loopback.patch ];

  # The workspace ships a lockfile for pnpm 10 (packageManager: pnpm@10.33.2), and
  # nixpkgs' default pnpm is 11 — a different lockfile dialect.
  nativeBuildInputs = [
    node-gyp # better-sqlite3 builds from source (its prebuild-install would fetch)
    nodejs
    pnpm_10
    pnpmConfigHook
    python3 # node-gyp needs it
  ];

  # Only the packages this server is made of: without the filter the install also
  # pulls the desktop (Electron), website and plugin workspaces plus the root dev
  # tooling (biome, buf, electron-builder) — none of which run here.
  pnpmWorkspaces = [
    "@sola_mpd/backend"
    "@sola_mpd/frontend"
    "@sola_mpd/shared"
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-i4TdfBk9n3tZKZ+IEncqTmFvggTQEQJ9UbUT4vbFhlU=";
  };

  # The generated protobuf models are committed (CI checks they are current), so
  # no buf/network step is needed here.
  buildPhase = ''
    runHook preBuild

    pnpm --filter @sola_mpd/shared --filter @sola_mpd/frontend --filter @sola_mpd/backend -r run build:no_types

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Runtime tree: the backend package (dist + the UI copied into dist/public),
    # the workspace package @sola_mpd/shared — its package.json maps ./src/* to
    # ./dist/*, so the built dist must travel — and a production install.
    #
    # The frontend is already built at this point, so its own dependencies
    # (Mantine, the Tabler icon set — hundreds of MB) are deliberately not part
    # of the runtime install: they would only sit in the closure.
    mkdir -p $out/lib/sola-mpd/packages
    cp -r packages/frontend/dist packages/backend/dist/public
    cp -r packages/backend packages/shared $out/lib/sola-mpd/packages/
    cp package.json pnpm-workspace.yaml pnpm-lock.yaml $out/lib/sola-mpd/

    pushd $out/lib/sola-mpd
    pnpm install --offline --prod --frozen-lockfile --ignore-scripts \
      --store-dir "$STORE_PATH" \
      --filter @sola_mpd/backend --filter @sola_mpd/shared
    popd

    # The install leaves links to the packages' dev-only tools (tsdown, buf) in
    # place; nothing at runtime reaches them.
    find $out/lib/sola-mpd -xtype l -delete

    # better-sqlite3 is the one native module, and --ignore-scripts means it was
    # installed without its binary: compile it against this node, in the tree it
    # will actually run from.
    pushd "$(readlink -f $out/lib/sola-mpd/packages/backend/node_modules/better-sqlite3)"
    npm run build-release --offline "--nodedir=${srcOnly nodejs}"
    find build -type f -exec ${removeReferencesTo}/bin/remove-references-to -t "${srcOnly nodejs}" {} \;
    popd

    mkdir -p $out/bin
    cat > $out/bin/sola-mpd <<'SH'
    #!/bin/sh
    # Sola MPD keeps its state in ./db relative to the process' working directory
    # (DB_DIRECTORY in @sola_mpd/shared), which is why the cwd is set here rather
    # than left to whoever starts the service.
    set -eu
    data_dir="''${SOLA_MPD_DATA_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/sola_mpd}"
    mkdir -p "$data_dir"
    cd "$data_dir"
    exec @node@ @app@/packages/backend/dist/index.mjs "$@"
    SH
    substituteInPlace $out/bin/sola-mpd \
      --replace-fail "@node@" "${lib.getExe nodejs}" \
      --replace-fail "@app@" "$out/lib/sola-mpd"
    chmod +x $out/bin/sola-mpd

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "Browser-based MPD client (Node backend + React UI) for large libraries";
    homepage = "https://github.com/prokosna/sola_mpd";
    license = lib.licenses.mit;
    mainProgram = "sola-mpd";
  };
})
