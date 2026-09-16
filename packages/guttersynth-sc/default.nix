##
# Package: guttersynth-sc
# Purpose: GutterSynth — SC UGen plugin: physical-ish synth using coupled
#   duffing oscillators resonating through modal synthesis (by Tom Mudd,
#   ported to C++/SC by Scott Carver & Mads Kjeldgaard). Server plugin + class.
# Source: https://github.com/madskjeldgaard/guttersynth-sc
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "guttersynth-sc";
  version = "unstable-2026-06-16";

  src = fetchFromGitHub {
    owner = "madskjeldgaard";
    repo = "guttersynth-sc";
    rev = "fb481d47336cdf45c1c19ca8392d982657a8c136";
    hash = "sha256-AvN5Kvig0b2mmrESsBhuweOdrO0YAvu7O5mfTp1bCc4=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DSCSYNTH=ON"
  ];

  postInstall = ''
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/GutterSynth"
    find "$out/GutterSynth" -name '*_scsynth.so' -exec mv {} "$out/lib/SuperCollider/plugins/" \;
    find "$out/GutterSynth" -name '*.sc' -exec cp {} "$out/share/SuperCollider/extensions/GutterSynth/" \;
    find "$out/GutterSynth" -type d -name HelpSource -exec cp -r {} "$out/share/SuperCollider/extensions/GutterSynth/" \;
    rm -rf "$out/GutterSynth"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider GutterSynth UGen — coupled duffing oscillators through modal synthesis";
    homepage = "https://github.com/madskjeldgaard/guttersynth-sc";
    license = lib.licenses.gpl3Plus;
  };
}
