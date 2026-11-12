{
  lib,
  rustPlatform,
  imagemagick,
  jq,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-theme";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: every case gets a temporary HOME/XDG tree and draws
  # its fixture wallpapers with ImageMagick, so there is no network and no
  # wallpaper collection. ImageMagick and jq are the pipeline's own external
  # tools — the 48x48 sample and --from-json — and the test suite uses both.
  nativeCheckInputs = [
    imagemagick
    jq
  ];
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar theme pipeline (wallpaper colours and theme files to ~/.config/pleamar/theme.plm)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-theme";
  };
}
