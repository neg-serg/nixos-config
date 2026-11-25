{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-theme";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "pleamar theme pipeline (wallpaper colours and theme files to ~/.config/pleamar/theme.plm)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-theme";
  };
}
