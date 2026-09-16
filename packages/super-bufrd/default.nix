##
# Package: super-bufrd
# Purpose: SuperCollider UGens for subsample-accurate buffer reading
#   (SuperBufRd, SuperPoll, SuperBinaryOpUGen + SC classes SuperPhasor,
#   SuperPlayBuf, SuperBufFrames, …). No install rules upstream — files are
#   copied into the standard SC layout here.
# Source: https://github.com/elgiano/super-bufrd
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  boost,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "super-bufrd";
  version = "unstable-2020-04-29";

  src = fetchFromGitHub {
    owner = "elgiano";
    repo = "super-bufrd";
    rev = "6deb736e4c885e7f13af16a5544076fae1df7321";
    hash = "sha256-r1kcxvQm5qnyeukPmWWM7NwzfT+l1BWATMLTQiVMDI0=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ boost ];

  # Upstream CMakeLists requires cmake < 3.5 (removed in cmake 4.x); bump.
  # It also defaults to -std=c++11 (CPP11=ON) which breaks on SC 3.14 headers
  # (need C++14+), so force C++17 via CXXFLAGS and disable the CPP11 option.
  preConfigure = ''
    sed -i 's/cmake_minimum_required (VERSION 2.8)/cmake_minimum_required (VERSION 3.5)/' CMakeLists.txt
  '';

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DCPP11=OFF"
    "-DCMAKE_CXX_FLAGS=-std=c++17"
  ];

  # NOTE: phases run inside the cmake build dir. The .so files land here
  # (no install rules upstream); the .sc sources are one level up.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/SuperBufRd"

    install -m755 SuperBufRd.so SuperPoll.so SuperBinaryOpUGen.so "$out/lib/SuperCollider/plugins/"
    install -m644 ../SuperBufRd.sc ../SuperPair.sc ../extSuperPair.sc "$out/share/SuperCollider/extensions/SuperBufRd/"
    cp -r ../HelpSource "$out/share/SuperCollider/extensions/SuperBufRd/"
    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "SuperCollider UGens for subsample-accurate buffer reading";
    homepage = "https://github.com/elgiano/super-bufrd";
    license = lib.licenses.gpl3Plus;
  };
}
