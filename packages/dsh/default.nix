{
  lib,
  fetchurl,
  python3,
  jq,
  dsh-patch,
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
  src = runCommand "dsh-src" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar xzf ${tarball} -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
    # Drop the devDependency tree the published package.json declares (this
    # build never runs its scripts) and inject the security overrides kept in
    # sync with package-lock.json: npm ci replays the lockfile offline and
    # re-resolves anything an override does not cover (the lockfile cannot
    # carry overrides itself), so these must match what the lockfile was
    # generated with. jq keeps the JSON semantics of the former python step.
    jq 'del(.devDependencies)
        | .overrides = {
            "@modelcontextprotocol/client": "2.2.0",
            "fflate": "0.8.3"
          }' "$out/package.json" > "$out/package.json.tmp"
    mv "$out/package.json.tmp" "$out/package.json"
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
  # The post-install patches run as `dsh-patch <set> <dir>` (packages/dsh-patch,
  # a Rust port of the former patch-*.py scripts): exact-string replacements
  # with count assertions, so a dsh upgrade that drifts an anchor fails the
  # build instead of shipping a half-patched tree.
  postInstall =
    builtins.replaceStrings
      [
        "@NODEJS@"
        "@NODELIB@"
        "@DSHPATCH@"
      ]
      [
        (lib.getExe nodejsRuntime)
        nodejsRuntime.libraryPath
        (lib.getExe dsh-patch)
      ]
      (builtins.readFile ./post-install.sh)
    + ''
      # @deepseek-ai/libreoffice-kit-wasm rides along in the lockfile but nothing
      # in lib/node_modules references it (checked with `rg -a` over the whole
      # tree, package.json files included). It carries a 128 MiB soffice.wasm
      # plus 23 MiB soffice.data — pure dead weight in every switch and in the
      # dsh profile. Remove the directory, not just the assets, so an upgrade
      # that starts to import it fails loudly instead of silently losing files.
      rm -rf "$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/libreoffice-kit-wasm"
    '';

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
