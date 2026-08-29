##
# Package: flucoma
# Purpose: FluCoMa - Fluid Corpus Manipulation Toolkit for SuperCollider:
#   57 UGen plugins for corpus-based music (analysis, transformation,
#   machine learning: FluidBuf*, FluidML*, FluidNMF, FluidPitch...).
#   Upstream fetches flucoma-core + 6 deps via FetchContent; all are vendored
#   here and pointed at via FETCHCONTENT_SOURCE_DIR_* (sandbox-safe).
# Source: https://github.com/flucoma/flucoma-sc
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  fetchFromGitLab,
  boost,
  git,
  scPluginFarm,
}:
let
  core = fetchFromGitHub {
    owner = "flucoma";
    repo = "flucoma-core";
    rev = "0626d7a3438060965231f034eca07b981ec36fc4";
    hash = "sha256-gXkV+oOLZ+Jwm4A9TZv9F7OQKfeErKkuuyq00E1NZlA=";
  };
  hisstools = fetchFromGitHub {
    owner = "AlexHarker";
    repo = "HISSTools_Library";
    rev = "f3292adbc978c09dc43bedbfe2faa6e791b87594";
    hash = "sha256-LHhmbcfa7tRSYwiT4Dv6h1NE2xCyU8hcnj2DYL4mCqQ=";
  };
  eigen = fetchFromGitLab {
    owner = "libeigen";
    repo = "eigen";
    rev = "3147391d946bb4b6c68edd901f2add6ac1f31f8c";
    hash = "sha256-1/4xMetKMDOgZgzz3WMxfHUEpmdAm52RqZvz6i0mLEw=";
  };
  spectra = fetchFromGitHub {
    owner = "yixuan";
    repo = "spectra";
    rev = "bdd707b9a872bb17622696ed3cca2a27b743a5b7";
    hash = "sha256-HaJmMo4jYmO/j53/nHrL3bvdQMAvp4Nuhhe8Yc7pL88=";
  };
  json = fetchFromGitHub {
    owner = "nlohmann";
    repo = "json";
    rev = "9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03";
    hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
  };
  memory = fetchFromGitHub {
    owner = "foonathan";
    repo = "memory";
    rev = "92a5bfc53b97955b3d685af679636e87d0f5d15a";
    hash = "sha256-VdZd8NmsUQJiurcDvaFoTjiET8CcO1CK1sTpXC3b/YA=";
  };
  fmt = fetchFromGitHub {
    owner = "fmtlib";
    repo = "fmt";
    rev = "e76a9520a3c339d2cb6a1510db43a05ea9bd8ae6";
    hash = "sha256-Q5gHquCY7eDmAKzqIgpJSiut+/bcb9vWn6twF1UcOQM=";
  };
in
stdenv.mkDerivation rec {
  pname = "flucoma";
  version = "unstable-2026-06-24";

  src = fetchFromGitHub {
    owner = "flucoma";
    repo = "flucoma-sc";
    rev = "50be4067acb2c5b486d8224be5e9949a2e97311b";
    hash = "sha256-NLZkaCCpSy3F7Brbpf8kXcQrTxpyQbKzSZf3yqw/G5c=";
  };

  nativeBuildInputs = [
    cmake
    git
  ];
  buildInputs = [ boost ];

  # Local-only build (substitute=false). x86-64-v3 = AVX2/FMA/BMI2: HISSTools
  # FFT only implements zip/unzip for up to 256-bit vectors, so -march=native
  # (AVX-512 on Zen 5) fails to compile. v3 still beats the generic baseline.
  # Realtime audio: no -ffast-math (NaN/denormal semantics must stay IEEE-754).
  env.NIX_CFLAGS_COMPILE = "-march=x86-64-v3";

  # boost >=1.69 has header-only system; FindBoost can't satisfy the
  # COMPONENTS system requirement -> drop it (thread is what is linked).
  postPatch = ''
    sed -i 's/COMPONENTS thread system REQUIRED/COMPONENTS thread REQUIRED/' CMakeLists.txt
  '';

  # FluCoMa writes generated version files into flucoma-core's own directory
  # at configure time; the store path is read-only, so copy it into the build
  # tree first.
  postUnpack = ''
    mkdir -p "$sourceRoot/vendored"
    cp -r ${core} "$sourceRoot/vendored/flucoma-core"
    chmod -R u+w "$sourceRoot/vendored/flucoma-core"
    # the vendored deps are read-only store paths; copy the ones FluCoMa
    # writes into (core) is done above; the rest are header-only reads.
  '';

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DDOCS=OFF"
    "-DSYSTEM_BOOST=ON"
    # Vendored deps - stop FetchContent from hitting the network
    "-DFLUID_PATH=../vendored/flucoma-core"
    "-DFETCHCONTENT_SOURCE_DIR_HISSTOOLS=${hisstools}"
    "-DFETCHCONTENT_SOURCE_DIR_EIGEN=${eigen}"
    "-DFETCHCONTENT_SOURCE_DIR_SPECTRA=${spectra}"
    "-DFETCHCONTENT_SOURCE_DIR_JSON=${json}"
    "-DFETCHCONTENT_SOURCE_DIR_MEMORY=${memory}"
    "-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}"
  ];

  # Upstream installs a complete quark dir FluidCorpusManipulation/
  # (Plugins/ + Classes/ + HelpSource/ + Resources/ + Examples/). Split into
  # the standard SC layout: .so files in lib/SuperCollider/plugins, the quark
  # content under share/SuperCollider/extensions/FluCoMa (matching the
  # user's existing manual install name).
  postInstall = ''
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/FluCoMa"
    mv "$out/FluidCorpusManipulation/Plugins"/*.so "$out/lib/SuperCollider/plugins/"
    rm -rf "$out/FluidCorpusManipulation/Plugins"
    mv "$out/FluidCorpusManipulation"/* "$out/share/SuperCollider/extensions/FluCoMa/"
    rmdir "$out/FluidCorpusManipulation"
  '';

  meta = with lib; {
    description = "Fluid Corpus Manipulation Toolkit for SuperCollider (57 UGen plugins)";
    homepage = "https://github.com/flucoma/flucoma-sc";
    license = licenses.bsd3; # BSD-3-Clause
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
