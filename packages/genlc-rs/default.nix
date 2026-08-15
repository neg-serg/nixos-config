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

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    udev
    libusb1
    hidapi
  ];

  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath [ libusb1 ]} $out/bin/genlc
  '';

  meta = with lib; {
    description = "Genelec SAM loudspeaker CLI volume control (Rust)";
    homepage = "https://github.com/neg-serg/genlc";
    license = licenses.mit;
    mainProgram = "genlc";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
