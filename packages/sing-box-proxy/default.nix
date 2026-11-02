{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "sing-box-proxy";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The whole suite is offline: the config goldens are committed, and the
  # CLI/validation tests replace every external command with a POSIX stub on
  # PATH. The shell-parity suite skips itself unless PROXY_SHELL is set.
  doCheck = true;

  meta = lib.mkMeta {
    description = "sing-box proxy controller — on/off/status/refresh/gen/run (Rust port of packages/local-bin/bin/proxy)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "proxy";
  };
}
