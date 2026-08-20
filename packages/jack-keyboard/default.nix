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
    hash = "sha256-juV3wkz2BEoBXKUOI3rLQQXC1WYX6ykKAOgnJDAv3rs=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  # Upstream CMakeLists pins a pre-3.5 minimum; modern CMake refuses it.
  cmakeFlags = [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DLashEnable=OFF" # LASH session handler is dead; not in nixpkgs
  ];

  # 2022-era code trips modern -Werror=format-security / deprecations.
  CFLAGS = [
    "-Wno-error=format-security"
    "-Wno-deprecated-declarations"
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
