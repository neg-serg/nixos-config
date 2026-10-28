##
# Package: portedplugins
# Purpose: Mads Kjeldgaard's ported SC UGens (~30): VA filters (Korg35, OB SEM,
#   Diode Ladder, VASEM12, VadimFilter), wavefolders (Lockhart, AnalogFold),
#   analog drum synths (Bass/Snare Drum), StringVoice, VOSIM, Fverb, Resonator.
# Source: https://github.com/madskjeldgaard/portedplugins (GPL-3)
{
  lib,
  mkScPlugin,
  scPluginFarm,
}:
let
  # CMakeLists downloads CPM.cmake from GitHub at configure time; vendor it
  # from the locally staged copy (GitHub is blocked on this host).
  cpm = ./CPM_0.36.0.cmake;
in
mkScPlugin {
  pname = "portedplugins";
  version = "unstable-2025-02-06";

  # GitHub is blocked on this host — source archived locally.
  # In-repo copies so pure evaluation works (absolute paths outside the flake are forbidden).
  src = ./portedplugins.tar.gz;

  inherit scPluginFarm;

  postPatch = ''
    mkdir -p cmake build/cmake
    cp ${cpm} cmake/CPM_0.36.0.cmake
    cp ${cpm} build/cmake/CPM_0.36.0.cmake
  '';

  cmakeFlags = [
    "-DSCSYNTH=ON"
    "-DUSE_DAISYSP_LIB=OFF"
  ];

  installDir = "portedplugins";
  install = ''
    cp -v "$out/PortedPlugins"/*_scsynth.so "$pluginsDir/"
    cp -rv "$out/PortedPlugins/Classes" "$extdir/"
    cp -rv "$out/PortedPlugins/HelpSource" "$extdir/"
    rm -rf "$out/PortedPlugins"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider plugin: 30+ ported analog-style UGens (VA filters, drum synths, Fverb reverb)";
    homepage = "https://github.com/madskjeldgaard/portedplugins";
    license = lib.licenses.gpl3;
  };
}
