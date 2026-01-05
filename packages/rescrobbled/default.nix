{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  dbus,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "rescrobbled";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "InputUsername";
    repo = "rescrobbled";
    rev = "v${version}";
    hash = "sha256-+5BkM4L2eB54idZ6X2ESw6ERMhG5CM4AF4BMEJm3xLU=";
  };

  cargoHash = "sha256-ZawdZdP87X7xMdSdZ1VJDJxz7dBGVYo+8jR8qb2Jgq8=";

  nativeBuildInputs = [pkg-config];
  buildInputs = [dbus openssl];

  # Tests require environment specific filters which are not active in build sandbox
  doCheck = false;

  meta = with lib; {
    description = "MPRIS music scrobbler daemon";
    homepage = "https://github.com/InputUsername/rescrobbled";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.linux;
  };
}
