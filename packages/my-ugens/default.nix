##
# Package: my-ugens
# Purpose: MyUGens — sonoro1234's suite of SuperCollider UGen plugins:
#   DWGClarinet, DWGFlute, KLJunction, SonLPC, Karplus, IIRf, AdachiAyers,
#   PitchTracker, PluckSynth, MembraneV, MyPlucked. DWGReverb (embedded as a
#   submodule) ships as the separate dwg-reverb package instead, so its CMake
#   target is skipped here — but its dwglib/ is kept, since the other DWG
#   projects compile shared sources from it (DWG.cpp).
# Source: https://github.com/sonoro1234/MyUGens
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "my-ugens";
  version = "unstable-2025-02-10";

  src = fetchFromGitHub {
    owner = "sonoro1234";
    repo = "MyUGens";
    rev = "f62135a1314076a30e1bafd2229ba9b85264b373";
    hash = "sha256-isjJG7qoVWxYsg15siskCA9ukNoEhzeQNsDNMkezk38=";
  };

  # fetchFromGitHub does not fetch submodules; DWGReverb is one. Fetch the
  # same rev the submodule pins and unpack it into place.
  dwgReverb = fetchFromGitHub {
    owner = "sonoro1234";
    repo = "DWGReverb";
    rev = "25a51cab241af0198b7a1d25949808684668a315";
    hash = "sha256-VUW4k2tYegZkRPD/b8gdVEcLnV1QcIevLFv2jNrq9ic=";
  };

  postUnpack = ''
    rm -rf "$sourceRoot/DWGReverb"
    cp -r ${dwgReverb} "$sourceRoot/DWGReverb"
    chmod -R u+w "$sourceRoot/DWGReverb"
    # Don't build the embedded DWGReverb UGen (separate dwg-reverb package)
    sed -i '/^add_subdirectory(DWGReverb)/d' "$sourceRoot/CMakeLists.txt"
    rm -f "$sourceRoot/DWGReverb/CMakeLists.txt"
  '';

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
  ];

  postInstall = ''
    # Upstream installs straight into the standard SC layout:
    #   lib/SuperCollider/plugins/*.so
    #   share/SuperCollider/Extensions/Myplugins/<Name>/
    test -d "$out/lib/SuperCollider/plugins"
    test -d "$out/share/SuperCollider/Extensions/Myplugins"
  '';

  meta = with lib; {
    description = "Sonoro1234 MyUGens — DWG instruments, Karplus, IIR filters, pitch tracking, plucked strings";
    homepage = "https://github.com/sonoro1234/MyUGens";
    license = licenses.gpl2Plus; # MyUGens suite (no LICENSE file; DWG code is GPL)
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
