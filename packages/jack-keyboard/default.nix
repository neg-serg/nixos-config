{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  gtk2,
  jack2,
}:

stdenv.mkDerivation {
  pname = "jack-keyboard";
  version = "unstable-2022-10-08";

  src = fetchFromGitHub {
    owner = "Stazed";
    repo = "jack-keyboard";
    rev = "c68bd8698179ae9a9f7c0e79bdf4fda9767c7537";
    hash = "sha256-vxDHhEasegqa15qzN66hFBcI88mxkReGzPe7/z8IHGQ=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    gtk2
    jack2
  ];

  meta = {
    description = "Virtual MIDI keyboard for JACK (PipeWire) — sends notes to a MIDI out port";
    homepage = "https://github.com/Stazed/jack-keyboard";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
