## VapourSynth NCNN Vulkan runtime plugin (vs-mlrt subproject)
## Runs Real-ESRGAN / RIFE / Real-CUGAN / DPIR / SCUNet inference inside
## VapourSynth on any Vulkan GPU (AMD RDNA4 works via generic Vulkan, no ROCm).
## License: GPL-3.0 (fine for local personal use; note if ever redistributing).
{
  lib,
  stdenv,
  cmake,
  git,
  fetchFromGitHub,
  ncnn,
  onnx,
  protobuf,
  vapoursynth,
  zlib,
}:

stdenv.mkDerivation rec {
  pname = "vsncnn";
  version = "15.16";

  src = fetchFromGitHub {
    owner = "AmusementClub";
    repo = "vs-mlrt";
    rev = "v${version}";
    hash = "sha256-mcIPNrPsVNgtGSSzLpwm7QYEbFOcB6IH2pepS9pVGCc=";
  };

  # vs-mlrt has no top-level CMakeLists: build the vsncnn subproject directly.
  # nixpkgs keeps the unpacked tree intact, so ../common stays reachable.
  sourceRoot = "source/vsncnn";

  nativeBuildInputs = [
    cmake
    git # find_package(Git REQUIRED); git describe tolerates missing .git
  ];

  buildInputs = [
    ncnn # nixpkgs ncnn is built with NCNN_VULKAN=1 + shared lib
    onnx # C++ ONNX lib used for on-the-fly ONNX -> ncnn conversion
    protobuf
    zlib
    vapoursynth
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    # nixpkgs vapoursynth installs headers under include/vapoursynth/
    "-DVAPOURSYNTH_INCLUDE_DIRECTORY=${lib.getDev vapoursynth}/include/vapoursynth"
  ];

  # The source tarball is not a git repo, so `git describe` yields an empty
  # VCS_TAG and `string(STRIP ...)` fails; fall back to the package version.
  # (CMake requires the if/endif block to span separate lines.)
  postPatch = ''
        substituteInPlace CMakeLists.txt \
          --replace-fail 'string(STRIP ''${VCS_TAG} VCS_TAG)' 'if(NOT VCS_TAG)
      set(VCS_TAG "v${version}")
    endif()'
  '';

  meta = with lib; {
    description = "VapourSynth NCNN (Vulkan) plugin for AI upscaling/interpolation/denoising (vs-mlrt)";
    homepage = "https://github.com/AmusementClub/vs-mlrt";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
