{
  lib,
  fetchurl,
  python3,
  makeWrapper,
  buildNpmPackage,
  runCommand,
  callPackage,
}:
let
  version = "0.2.0-rc.2";

  # The launcher runs on the official Node build, not nixpkgs' — see
  # nodejs-official.nix for why (the harness's native loader cannot locate its
  # getter in any nixpkgs Node). npm/build phases still use nixpkgs' nodejs.
  nodejsRuntime = callPackage ./nodejs-official.nix { };

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-vSeEfERc1opWWsH5HAa7vMdjnvkwcfZ4u1nF66/ziFk=";
  };

  # Registry tarballs ship no lockfile; npm ci needs one.
  #
  # The published package.json declares a 47-package devDependency tree (mostly
  # internal @deepseek-ai prereleases, plus types/ajv/execa/ws) that this build
  # never touches — dsh ships prebuilt lib/ and has no build script — so
  # devDependencies are dropped here and in the lockfile (generated the same
  # way). The 0.1.x-era failure that forced this (npm ci refusing the tree
  # because @deepseek-ai/dsh-experimental-code-runtime-python@^0.1.5-rc.1 was
  # not on the registry, 404) does not reproduce on 0.2.0-rc.2: every devDep
  # resolves now. Dropping them keeps the closure and the npmDepsHash fetch
  # small; re-check this note if npm ci ever fails again.
  src = runCommand "dsh-src" { nativeBuildInputs = [ python3 ]; } ''
        mkdir -p $out
        tar xzf ${tarball} -C $out --strip-components=1
        cp ${./package-lock.json} $out/package-lock.json
        python3 - "$out/package.json" <<'PY'
    import json
    import sys

    path = sys.argv[1]
    pkg = json.load(open(path))
    pkg.pop("devDependencies", None)
    # Security overrides, kept in sync with package-lock.json. npm ci replays
    # the lockfile offline and re-resolves anything an override does not cover
    # (the lockfile itself cannot carry overrides), so this must match the
    # npm `overrides` the lockfile was generated with.
    pkg["overrides"] = {
        "@modelcontextprotocol/client": "2.2.0",
        "fflate": "0.8.3",
    }
    json.dump(pkg, open(path, "w"), indent=2, ensure_ascii=False)
    PY
  '';
in
buildNpmPackage {
  pname = "dsh";
  inherit version src;

  # dsh ships prebuilt lib/; its package.json has no build script.
  dontNpmBuild = true;

  nativeBuildInputs = [
    python3 # node-gyp compiles native deps (node-pty) during npm rebuild
    makeWrapper # rewrap the dsh launcher with node --expose-internals (HMR)
  ];

  # The HMR plugin requires node --expose-internals, which the default wrapper
  # omits. Rewrap the launcher the same way the dsh systemd service does.
  # The patch scripts import the shared count-assert helper (./lib/patchlib.py)
  # through PYTHONPATH, so that directory is substituted in alongside them.
  # (patch-preset-names.py retired with 0.2.0-rc.2: the preset names are
  # localized upstream now — see post-install.sh.)
  postInstall =
    builtins.replaceStrings
      [
        "@NODEJS@"
        "@NODELIB@"
        "@PY@"
        "@PY_V2@"
        "@PY_MIG@"
        "@PY_PTC@"
        "@PATCHLIB_DIR@"
      ]
      [
        (lib.getExe nodejsRuntime)
        nodejsRuntime.libraryPath
        "${./patch-widgets.py}"
        "${./patch-session-format.py}"
        "${./patch-session-migration.py}"
        "${./patch-ptc-env.py}"
        "${./lib}"
      ]
      (builtins.readFile ./post-install.sh);

  # Prefetched dependency tree; hash from `prefetch-npm-deps package-lock.json`.
  # The lockfile carries two security overrides: fflate 0.8.2 -> 0.8.3
  # (GHSA-px8p-9vwx-vf98) and @modelcontextprotocol/client 2.0.0 -> 2.2.0
  # (GHSA-6qxp-vccf-f47h, OAuth credential leak; dsh-mcp-client pins it
  # exactly). They are injected into package.json by `src` below, because npm ci
  # cannot replay a lockfile that resolves past a declared pin without them.
  npmDepsHash = "sha256-pA4usAobMGeYgWpo07+bOJC0yoK990hCJ1cWReYon2c=";

  meta = {
    description = "DeepSeek Harness (dsh) — open-source agent harness, everything is a plugin";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "dsh";
    maintainers = [ ];
  };
}
