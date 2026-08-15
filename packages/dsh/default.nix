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
  version = "0.1.0-rc.6";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-G4qaCtPH/q7OR5JuC9N8oVHHzPqZeVOvpf0BJheE6tw=";
  };

  # Registry tarballs ship no lockfile; npm ci needs one.
  src = runCommand "dsh-src" { } ''
    mkdir -p $out
    tar xzf ${tarball} -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
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
  postInstall = ''
    rm -f $out/bin/dsh
    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --add-flags "--expose-internals $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';

  # Prefetched dependency tree; hash from `prefetch-npm-deps package-lock.json`
  npmDepsHash = "sha256-9Cx3OhIK3xuyd6o+HZhAs+2eGsIrys8fNdtRePd4GnQ=";

  meta = with lib; {
    description = "DeepSeek Harness (dsh) — open-source agent harness, everything is a plugin";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dsh";
    maintainers = [ ];
  };
}
