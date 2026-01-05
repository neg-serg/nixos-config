{
  lib,
  rustPlatform,
  pkg-config,
  dbus,
  openssl,
}:
rustPlatform.buildRustPackage {
  pname = "rescrobbled";
  version = "0.8.0";

  src = /home/neg/src/rescrobbled;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [pkg-config];
  buildInputs = [dbus openssl];

  doCheck = false;

  meta = with lib; {
    description = "MPRIS music scrobbler daemon";
    homepage = "https://github.com/InputUsername/rescrobbled";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.linux;
  };
}
