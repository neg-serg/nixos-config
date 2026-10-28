##
# Package: xplaybuf
# Purpose: XPlayBuf — SuperCollider UGen for granular playback with xfade
#   (elgiano). Server plugin (.so) plus SC class files.
# Source: https://github.com/elgiano/XPlayBuf
{
  lib,
  mkScPlugin,
  fetchFromGitHub,
  scPluginFarm,
}:
mkScPlugin {
  pname = "xplaybuf";
  version = "unstable-2024-06-26";

  src = fetchFromGitHub {
    owner = "elgiano";
    repo = "XPlayBuf";
    rev = "44b90771c4508913ad76cb7347b6b10183395351";
    hash = "sha256-SBXl1RWyDQn23joBMtULQWyXtuwB6AnmfSCZJ0s4nk8=";
  };

  inherit scPluginFarm;

  cmakeFlags = [
    "-DSCSYNTH=ON"
    "-DNOVA_SIMD=OFF"
  ];

  installDir = "XPlayBuf";
  # Upstream installs one tree per plugin; hoist it into the SC layout.
  install = ''
    mv "$out/XPlayBuf"/*_scsynth.so "$pluginsDir/"
    cp -r "$out/XPlayBuf/Classes" "$extdir/" 2>/dev/null || true
    cp -r "$out/XPlayBuf/HelpSource" "$extdir/" 2>/dev/null || true
    rm -rf "$out/XPlayBuf"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider XPlayBuf UGen — granular playback with crossfade";
    homepage = "https://github.com/elgiano/XPlayBuf";
    license = lib.licenses.gpl3Plus;
  };
}
