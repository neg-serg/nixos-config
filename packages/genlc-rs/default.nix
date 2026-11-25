{
  lib,
  rustPlatform,
  pkg-config,
  udev,
  libusb1,
  hidapi,
}:

rustPlatform.buildRustPackage {
  pname = "genlc";
  # Single source of truth: clap reports CARGO_PKG_VERSION from this manifest,
  # and the derivation reads the same file, so the CLI and the store path cannot
  # drift (they did: 0.1.0 in the binary, 0.2.0 in the package attr).
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    udev
    libusb1
    hidapi
  ];

  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath [ libusb1 ]} $out/bin/genlc
  '';

  meta = lib.mkMeta {
    description = "Genelec SAM loudspeaker CLI volume control (Rust)";
    homepage = "https://github.com/neg-serg/genlc";
    license = lib.licenses.mit;
    mainProgram = "genlc";
  };
}
