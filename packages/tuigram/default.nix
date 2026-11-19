{
  lib,
  fetchurl,
  runCommand,
  jq,
  buildNpmPackage,
  nodejs_26,
}:
let
  version = "1.6.0";

  tarball = fetchurl {
    url = "https://registry.npmjs.org/tuigram/-/tuigram-${version}.tgz";
    hash = "sha256-WCzzs+39VGrj4bEgs6uz2mhZU2BfICyC5ZKVr4jfp8U=";
  };

  # The published tarball carries no lockfile, so the one beside this file was
  # generated from it (`npm install --package-lock-only`) and is injected here.
  # devDependencies are dropped from the manifest and the lockfile: the package
  # ships its sources, `dontNpmBuild` has nothing to run, and the dev tree
  # (typescript, eslint, @mtcute/test) would only bloat the dependency fetch.
  src = runCommand "tuigram-src" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar xzf ${tarball} -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
    jq 'del(.devDependencies)' "$out/package.json" > "$out/package.json.tmp"
    mv "$out/package.json.tmp" "$out/package.json"
  '';
in
buildNpmPackage {
  pname = "tuigram";
  inherit version src;

  # tuigram requires Node >= 26.4: the opentui renderer reaches its bundled Zig
  # library through node:ffi, which only that series exposes. The launcher
  # re-execs itself with --experimental-ffi, so the wrapper needs no extra
  # flags.
  nodejs = nodejs_26;

  # Published sources are runnable as-is; package.json has no build script.
  dontNpmBuild = true;

  # Hash of the production dependency tree only (devDependencies are removed by
  # `src`); from `prefetch-npm-deps package-lock.json`.
  npmDepsHash = "sha256-EIs9Svdo73Cg5/3a8iShtLL1n8wuXbdMhr/ZI63sVXQ=";

  meta = {
    description = "Terminal UI client for Telegram";
    homepage = "https://github.com/leonid-shutov/tuigram";
    license = lib.licenses.mit;
    mainProgram = "tuigram";
    # @opentui/core installs a prebuilt native library for the host platform
    # (optionalDependency), so the dependency hash is pinned for x86_64-linux.
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
