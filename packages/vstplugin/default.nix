##
# Package: vstplugin
# Purpose: VSTPlugin — host VST2/VST3 plugins directly inside scsynth
#   (Spacechild1). Includes the SC UGen (VSTPlugin.so), plugin bridge host
#   binary, SC classes and help. VST2 SDK (Steinberg 3.6.10) is vendored from
#   files/sources (web.archive.org, region-blocked); VST3 SDK pluginterfaces
#   come from the steinbergmedia/vst3_pluginterfaces repo (open).
# Source: https://github.com/Spacechild1/vstplugin
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  libx11,
  python3,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "vstplugin";
  version = "unstable-2025-10-28";

  src = fetchFromGitHub {
    owner = "Spacechild1";
    repo = "vstplugin";
    rev = "d83c171a6cb37cfb7835f7aa50e1fc2920e05bfa";
    hash = "sha256-REp+x7mKzKrf+CW1mRQxYHHDN7MAxazc1RwC2AEyDJI=";
  };

  # VST3 pluginterfaces (open SDK headers) — content of VST3_SDK/pluginterfaces/
  vst3Pluginterfaces = fetchFromGitHub {
    owner = "steinbergmedia";
    repo = "vst3_pluginterfaces";
    rev = "4f547e8e102b47de4a8b8aaf343c73b700786372";
    hash = "sha256-Ey9+zHhsVuj9bqmBqCOQ/Ls6uwYcOzfgxxWefZJHIm0=";
  };

  postUnpack = ''
    # VST2 SDK zip (contains VST_SDK/{VST2_SDK,VST3_SDK})
    python3 -c "import zipfile; zipfile.ZipFile('${sdkZip}').extractall('$sourceRoot/vst')"
    # VST2 headers stay at vst/VST_SDK/VST2_SDK (cmake VST2DIR default)
    # Replace the SDK's stale VST3_SDK with the current pluginterfaces
    rm -rf "$sourceRoot/vst/VST_SDK/VST3_SDK"
    mkdir -p "$sourceRoot/vst/VST_SDK/VST3_SDK"
    cp -r ${vst3Pluginterfaces} "$sourceRoot/vst/VST_SDK/VST3_SDK/pluginterfaces"
  '';

  sdkZip = ../../files/sources/vst2sdk-3.6.10.zip;

  nativeBuildInputs = [
    cmake
    python3
  ];
  buildInputs = [ libx11 ];

  cmakeFlags = [
    "-DSC_INCLUDEDIR=${scPluginFarm}"
    "-DSC_INSTALLDIR=${placeholder "out"}/share/SuperCollider/Extensions"
    "-DPD=OFF"
    "-DSC=ON"
    "-DTESTSUITE=OFF"
    "-DVST2=ON"
    "-DVST3=ON"
    "-DBRIDGE=ON"
    "-DSUPERNOVA=OFF"
  ];

  meta = with lib; {
    description = "SuperCollider plugin: host VST2/VST3 plugins inside scsynth";
    homepage = "https://github.com/Spacechild1/vstplugin";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
