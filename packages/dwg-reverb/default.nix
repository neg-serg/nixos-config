##
# Package: dwg-reverb
# Purpose: DWGReverb — compiled SuperCollider UGen plugin (C++): very
#   efficient virtual room generator with early impulse generators and FDN
#   late reverbs. Builds Reverb.cpp + PartitionedConvolutionTrig.cpp into a
#   server plugin .so, plus the SC class files.
# Source: https://github.com/sonoro1234/DWGReverb
{
  lib,
  stdenv,
  fetchgit,
  supercollider,
}:
stdenv.mkDerivation {
  pname = "dwg-reverb";
  version = "unstable-2022-02-21";

  src = fetchgit {
    url = "https://github.com/sonoro1234/DWGReverb.git";
    rev = "25a51cab241af0198b7a1d25949808684668a315";
    hash = "sha256-VUW4k2tYegZkRPD/b8gdVEcLnV1QcIevLFv2jNrq9ic=";
  };

  # nova-simd (SSE/AVX vector helpers) — SuperCollider's external_libraries
  # submodule; DWG.cpp uses nova::vec / times_vec_simd / horizontal_sum.
  novaSimd = fetchgit {
    url = "https://github.com/supercollider/nova-simd.git";
    rev = "32a44ef83877cf74f92edeb46030023ff3c948a1";
    hash = "sha256-QGv/s2RQfPHg3T2swSJuWEg5O2KjLNsRGW+3rpUcGTo=";
  };

  nativeBuildInputs = [ ];
  buildInputs = [ supercollider ];

  buildPhase = ''
    runHook preBuild

    # SC server plugin headers: SC_PlugIn.h / FFT_UGens.h live in the
    # supercollider package's include/SuperCollider tree (same layout the
    # nixpkgs sc3-plugins build uses). nova-simd provides the SIMD helpers.
    # Realtime UGen: -O3 + -march=native (Zen 5). No -ffast-math — audio
    # correctness (NaN/denormal semantics) matters more than raw FLOPs.
    g++ -shared -fPIC -std=c++17 -O3 -march=native -DNOVA_SIMD \
      -I${supercollider}/include/SuperCollider/plugin_interface \
      -I${supercollider}/include/SuperCollider/common \
      -I${supercollider}/include/SuperCollider \
      -I$novaSimd \
      Reverb.cpp PartitionedConvolutionTrig.cpp \
      -o DWGReverb.so

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Server-side UGen plugin — scsynth finds it via SC_PLUGIN_PATH
    # (appended in the supercollider nix-maid module).
    install -Dm644 DWGReverb.so "$out/lib/SuperCollider/plugins/DWGReverb.so"

    # Client-side class files + help — symlinked into
    # ~/.local/share/SuperCollider/Extensions by the supercollider module.
    mkdir -p "$out/share/SuperCollider/extensions/DWGReverb"
    cp -r sc/classes "$out/share/SuperCollider/extensions/DWGReverb/"
    cp -r sc/HelpSource "$out/share/SuperCollider/extensions/DWGReverb/"

    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "SuperCollider plugin: efficient virtual room generator (early reflections + FDN late reverb)";
    longDescription = ''
      DWGReverb is a SuperCollider UGen plugin providing a very efficient
      virtual room generator: early impulse generators (EarlyRef,
      EarlyRefGen, EarlyRefAtkGen) and FDN (feedback delay network) late
      reverbs (DWGReverbC1C3, DWGReverb3Band and 16-channel variants) plus
      partitioned-convolution triggers. C++ implementation using nova-simd.
    '';
    homepage = "https://github.com/sonoro1234/DWGReverb";
    license = lib.licenses.gpl2Plus; # MyUGens suite is GPL; DWGReverb ships no LICENSE file
  };
}
