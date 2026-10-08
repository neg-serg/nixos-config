# Official nodejs.org build, used as dsh's *runtime* Node.
#
# The harness boots its plugin runtime through a native addon
# (node-addon-require-builtin) that locates an internal V8 getter inside the
# running Node binary by pattern-matching x64 code. Every nixpkgs Node build
# tried here defeats that search — requireBuiltin('internal/modules/esm/loader')
# fails with "Unsupported/no-getter" on 22.23.3, 24.19.0, 24.20.0 and 26.10.0 —
# while the official binary of the same version answers OK, so dsh runs on it.
#
# Only patchelf --set-interpreter is applied: patching the 120 MB image with
# --set-rpath as well produces a binary that segfaults on startup, and no RPATH
# is needed because the launcher exports LD_LIBRARY_PATH (children spawned
# through process.execPath inherit it). The file stays a real ELF at
# $out/bin/node on purpose — a shell wrapper there would break every re-exec
# the harness does (subagents, kernels, `dsh plugin ...`).
{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  glibc,
}:
let
  version = "24.20.0";
in
stdenv.mkDerivation {
  pname = "nodejs-official";
  inherit version;

  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz";
    hash = "sha256-LywNoWIxjw3kdmVBDHyMLtPTbI8xBd5LvGEXbHCny/I=";
  };

  nativeBuildInputs = [ patchelf ];

  # The tarball ships npm, corepack and headers; only the runtime is needed.
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp bin/node $out/bin/node
    chmod u+w $out/bin/node
    patchelf --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 $out/bin/node
    runHook postInstall
  '';

  # What the launcher exports as LD_LIBRARY_PATH: libstdc++ (the official build
  # links it) and glibc, in that order.
  passthru.libraryPath = lib.makeLibraryPath [ stdenv.cc.cc.lib glibc ];

  meta = {
    description = "Official Node.js build (nodejs.org) — the runtime dsh's native loader supports";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "node";
  };
}
