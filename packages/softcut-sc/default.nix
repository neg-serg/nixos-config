##
# Package: softcut-sc
# Purpose: Softcut — SuperCollider UGen plugin version of monome's Softcut
#   multi-voice sample player/recorder (6 voices, interpolated overdub,
#   matrix mixing, per-voice loop/fade/rate). Server plugin + SC class.
#   The softcut-lib dependency (monome) is vendored: upstream pulls it via
#   CPM during cmake configure, which breaks in the nix sandbox — we fetch it
#   and point cmake at the local copy instead.
# Source: https://github.com/madskjeldgaard/softcut-sc
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "softcut-sc";
  version = "unstable-2025-02-09";

  src = fetchFromGitHub {
    owner = "madskjeldgaard";
    repo = "softcut-sc";
    rev = "b1828ee2774943163d0d64fd246ce070e396dc8a";
    hash = "sha256-zXeGyAtD6wVtMRctFZzTimpDLV+Yz1SPK9h0zOuJte8=";
  };

  # monome softcut-lib (same rev the plugin's CPM pins: main @ 2024-12-31)
  softcutLib = fetchFromGitHub {
    owner = "monome";
    repo = "softcut-lib";
    rev = "14241f2a94a7cd2e6c91b9bdc4e500d68abef907";
    hash = "sha256-0bkkDwQE3vaiFqmc5Opqhnm0oFczdscBab39B3jzIOM=";
  };

  postUnpack = ''
    cp -r ${softcutLib} "$sourceRoot/softcut-lib"
    chmod -R u+w "$sourceRoot/softcut-lib"
  '';

  # Replace upstream's CPM-based dependency download (softcut-lib, and the
  # SC source fallback) with the vendored copy — CPM fetches from the network
  # at configure time, which is not allowed in the nix sandbox.
  patches = [ ./no-cpm.patch ];

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DSCSYNTH=ON"
    "-DNOVA_SIMD=OFF"
  ];

  postInstall = ''
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/Softcut"
    find "$out/Softcut" -name '*_scsynth.so' -exec mv {} "$out/lib/SuperCollider/plugins/" \;
    find "$out/Softcut" -name '*.sc' -exec cp {} "$out/share/SuperCollider/extensions/Softcut/" \;
    find "$out/Softcut" -type d -name HelpSource -exec cp -r {} "$out/share/SuperCollider/extensions/Softcut/" \;
    rm -rf "$out/Softcut"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider UGen: monome Softcut multi-voice looper/sampler";
    homepage = "https://github.com/madskjeldgaard/softcut-sc";
    license = lib.licenses.mit; # softcut-lib is MIT; plugin code MIT (LICENSE)
  };
}
