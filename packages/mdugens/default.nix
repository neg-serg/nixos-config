##
# Package: mdugens
# Purpose: Michael Dzjaparidze's SuperCollider UGens — TPTFilter (SVF filters
#   via topology-preserving transform), SOSBank (bank of 2nd-order sections)
#   and sclang FX classes: PlateReverb, Phaser, Chorus, Reverser, TapDelay,
#   VariableDelay, Transposer, GaussianNoise.
# Source: https://github.com/michaeldzjap/MDUGens (MIT)
{
  lib,
  stdenv,
  cmake,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "mdugens";
  version = "unstable-2025-02-12";

  # GitHub is blocked on this host — source archived locally.
  # In-repo copy so pure evaluation works (absolute paths outside the flake are forbidden).
  src = ./mdugens.tar.gz;

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DCPP14=ON"
    "-DSUPERNOVA=OFF"
    # CMakeLists declares cmake_minimum_required(2.8); modern CMake dropped
    # compatibility below 3.5 — opt back in.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/mdugens/Classes"
    cp -v *.so "$out/lib/SuperCollider/plugins/"
    scdir="$(find "$NIX_BUILD_TOP" -type d -path '*MDUGens*/sc' | head -1)"
    cp -v "$scdir"/*.sc "$out/share/SuperCollider/extensions/mdugens/Classes/"
    cp -rv "$scdir/HelpSource" "$out/share/SuperCollider/extensions/mdugens/"

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "SuperCollider plugin: TPT SVF filters + SOSBank + PlateReverb/Phaser/Chorus FX classes";
    homepage = "https://github.com/michaeldzjap/MDUGens";
    license = lib.licenses.mit;
  };
}
