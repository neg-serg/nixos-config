{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-kbdlayout";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "pleamar keyboard-layout worker (hyprctl, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-kbdlayout";
  };
}
