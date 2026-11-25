{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "sing-box-proxy";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "sing-box proxy controller — on/off/status/refresh/gen/run (Rust port of packages/local-bin/bin/proxy)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "proxy";
  };
}
