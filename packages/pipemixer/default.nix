{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  pipewire,
  ncurses,
  inih,
}:

stdenv.mkDerivation rec {
  pname = "pipemixer";
  version = "0.4.0-unstable-2025-01-28";

  src = fetchFromGitHub {
    owner = "heather7283";
    repo = "pipemixer";
    rev = "master";
    sha256 = "sha256-dVw8x9c3DFSL5eLbBOe7ExNzeKsj3xB5Spl516XFqTQ=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    pipewire
    ncurses
    inih
  ];

  meta = with lib; {
    description = "A TUI mixer for PipeWire";
    homepage = "https://github.com/heather7283/pipemixer";
    license = licenses.gpl3Only;
    mainProgram = "pipemixer";
    platforms = platforms.linux;
  };
}
