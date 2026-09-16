##
# Package: portedplugins
# Purpose: Mads Kjeldgaard's ported SC UGens (~30): VA filters (Korg35, OB SEM,
#   Diode Ladder, VASEM12, VadimFilter), wavefolders (Lockhart, AnalogFold),
#   analog drum synths (Bass/Snare Drum), StringVoice, VOSIM, Fverb, Resonator.
# Source: https://github.com/madskjeldgaard/portedplugins (GPL-3)
{
  lib,
  stdenv,
  cmake,

  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "portedplugins";
  version = "unstable-2025-02-06";

  # GitHub is blocked on this host — source archived locally.
  # In-repo copies so pure evaluation works (absolute paths outside the flake are forbidden).
  src = ./portedplugins.tar.gz;

  # CMakeLists downloads CPM.cmake from GitHub at configure time; vendor it
  # from the locally staged copy (GitHub is blocked on this host).
  cpm = ./CPM_0.36.0.cmake;

  nativeBuildInputs = [ cmake ];

  postPatch = ''
    mkdir -p cmake build/cmake
    cp ${cpm} cmake/CPM_0.36.0.cmake
    cp ${cpm} build/cmake/CPM_0.36.0.cmake
  '';

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSCSYNTH=ON"
    "-DSUPERNOVA=OFF"
    "-DUSE_DAISYSP_LIB=OFF"
  ];

  postInstall = ''
    # Reorganize the per-plugin install tree into the standard SC layout:
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/portedplugins"
    cp -v "$out/PortedPlugins"/*_scsynth.so "$out/lib/SuperCollider/plugins/"
    cp -rv "$out/PortedPlugins/Classes" "$out/share/SuperCollider/extensions/portedplugins/"
    cp -rv "$out/PortedPlugins/HelpSource" "$out/share/SuperCollider/extensions/portedplugins/"
    rm -rf "$out/PortedPlugins"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider plugin: 30+ ported analog-style UGens (VA filters, drum synths, Fverb reverb)";
    homepage = "https://github.com/madskjeldgaard/portedplugins";
    license = lib.licenses.gpl3;
  };
}
