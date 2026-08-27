##
# Package: sc-plugin-farm
# Purpose: Fake SuperCollider *source root* layout for third-party UGen builds.
#   The old-style cmake modules (SuperColliderServerPlugin.cmake etc.) expect
#   SC_PATH to point at a directory containing include/plugin_interface,
#   include/common, common/ and SCVersion.txt — i.e. an SC source tree.
#   The nix supercollider package ships headers under include/SuperCollider/,
#   so we symlink them into the layout the plugin cmake scripts look for.
#   Also provides external_libraries/nova-simd (MyUGens/DWGReverb use it).
{
  lib,
  stdenv,
  supercollider,
  fetchFromGitHub,
}:
let
  # nova-simd (SC's SIMD helper headers) — needed by MyUGens / DWGReverb via
  # ${SC_PATH}/external_libraries/nova-simd. Pinned to the rev the plugins use.
  novaSimd = fetchFromGitHub {
    owner = "supercollider";
    repo = "nova-simd";
    rev = "32a44ef83877cf74f92edeb46030023ff3c948a1";
    hash = "sha256-QGv/s2RQfPHg3T2swSJuWEg5O2KjLNsRGW+3rpUcGTo=";
  };
in
stdenv.mkDerivation {
  pname = "sc-plugin-farm";
  version = supercollider.version;

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p $out/include $out/external_libraries
    ln -s ${supercollider}/include/SuperCollider/plugin_interface $out/include/plugin_interface
    ln -s ${supercollider}/include/SuperCollider/common $out/include/common
    ln -s ${supercollider}/include/SuperCollider/common $out/common
    ln -s ${supercollider}/include/SuperCollider/SCVersion.txt $out/SCVersion.txt
    ln -s ${novaSimd} $out/external_libraries/nova-simd
  '';

  meta = with lib; {
    description = "SuperCollider header layout for building third-party UGens";
    platforms = platforms.linux;
    license = licenses.gpl3Plus;
  };
}
