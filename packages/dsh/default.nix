{
  lib,
  fetchurl,
  python3,
  makeWrapper,
  nodejs,
  buildNpmPackage,
  runCommand,
}:
let
  version = "0.1.5-rc.1";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-Gnlxnxx2ORisMOgZTfeDqTMMaxLV8EyVBzGj+KHD2dA=";
  };

  # Registry tarballs ship no lockfile; npm ci needs one.
  #
  # The published package.json declares devDependencies on internal
  # prereleases that are not on the registry at all
  # (@deepseek-ai/dsh-experimental-code-runtime-python@^0.1.5-rc.1 -> 404),
  # and npm resolves devDependencies before honouring --omit=dev, so `npm ci`
  # cannot run against the shipped package.json. dsh ships prebuilt lib/ and
  # never runs its dev tooling in this build, so devDependencies are dropped
  # here and in the lockfile (generated the same way).
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
  postInstall =
    builtins.replaceStrings
      [ "@NODEJS@" "@PY@" "@PY_V2@" "@PY_V3@" ]
      [
        (lib.getExe nodejs)
        "${./patch-widgets.py}"
        "${./patch-session-format.py}"
        "${./patch-preset-names.py}"
      ]
      (builtins.readFile ./post-install.sh);

  # Prefetched dependency tree; hash from `prefetch-npm-deps package-lock.json`
  npmDepsHash = "sha256-cqN2pdqnxEqJ/dPKW/cNSLICI4kB6qSJ7PqKqsQAMRo=";

  meta = with lib; {
    description = "DeepSeek Harness (dsh) — open-source agent harness, everything is a plugin";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dsh";
    maintainers = [ ];
  };
}
