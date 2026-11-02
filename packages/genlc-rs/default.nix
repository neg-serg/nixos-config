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
  version = "0.2.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # The crate carries unit tests for the GNet framing and the forbidden-frame
  # guard (src/protocol.rs); they are cheap and need no hardware, so the package
  # build runs them instead of letting them rot.
  doCheck = true;

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
