##
# Package: guttersynth-sc
# Purpose: GutterSynth — SC UGen plugin: physical-ish synth using coupled
#   duffing oscillators resonating through modal synthesis (by Tom Mudd,
#   ported to C++/SC by Scott Carver & Mads Kjeldgaard). Server plugin + class.
# Source: https://github.com/madskjeldgaard/guttersynth-sc
{
  lib,
  mkScPlugin,
  fetchFromGitHub,
  scPluginFarm,
}:
mkScPlugin {
  pname = "guttersynth-sc";
  version = "unstable-2026-06-16";

  src = fetchFromGitHub {
    owner = "madskjeldgaard";
    repo = "guttersynth-sc";
    rev = "fb481d47336cdf45c1c19ca8392d982657a8c136";
    hash = "sha256-AvN5Kvig0b2mmrESsBhuweOdrO0YAvu7O5mfTp1bCc4=";
  };

  inherit scPluginFarm;

  cmakeFlags = [ "-DSCSYNTH=ON" ];

  installDir = "GutterSynth";
  install = ''
    find "$out/GutterSynth" -name '*_scsynth.so' -exec mv {} "$pluginsDir/" \;
    find "$out/GutterSynth" -name '*.sc' -exec cp {} "$extdir/" \;
    find "$out/GutterSynth" -type d -name HelpSource -exec cp -r {} "$extdir/" \;
    rm -rf "$out/GutterSynth"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider GutterSynth UGen — coupled duffing oscillators through modal synthesis";
    homepage = "https://github.com/madskjeldgaard/guttersynth-sc";
    license = lib.licenses.gpl3Plus;
  };
}
