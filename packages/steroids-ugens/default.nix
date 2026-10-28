##
# Package: steroids-ugens
# Purpose: SuperCollider "Steroids" UGens by tai-studio (SSinOscFB, TDemand) —
#   server plugins (.so) plus SC class files.
# Source: https://github.com/tai-studio/steroids-ugens
{
  lib,
  mkScPlugin,
  fetchFromGitHub,
  scPluginFarm,
}:
mkScPlugin {
  pname = "steroids-ugens";
  version = "unstable-2020-11-14";

  src = fetchFromGitHub {
    owner = "tai-studio";
    repo = "steroids-ugens";
    rev = "1d4a9b2a0aa439bf9aac9d4257f3d7867cad36c1";
    hash = "sha256-IR02yiwMbS0/fYgLVFw+ShRCBQ9mpoht/M7Z2XoUNU0=";
  };

  inherit scPluginFarm;

  # The repo pins C++11, but SC 3.14 headers need C++14+ (SC_Unit.h uses
  # std::remove_cv_t / auto return types). Bump the standard at configure time.
  preConfigure = ''
    sed -i 's/set(CMAKE_CXX_STANDARD 11)/set(CMAKE_CXX_STANDARD 17)/' CMakeLists.txt
  '';

  cmakeFlags = [
    "-DSCSYNTH=ON"
    "-DNOVA_SIMD=OFF"
  ];

  installDir = "Steroids";
  install = ''
    for dir in "$out"/Steroids/*/; do
      name="$(basename "$dir")"
      mv "$dir"/*_scsynth.so "$pluginsDir/"
      mkdir -p "$extdir/$name"
      cp -r "$dir/Classes" "$extdir/$name/" 2>/dev/null || true
      cp -r "$dir/HelpSource" "$extdir/$name/" 2>/dev/null || true
    done
    rm -rf "$out/Steroids"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider Steroids UGens (SSinOscFB, TDemand)";
    homepage = "https://github.com/tai-studio/steroids-ugens";
    license = lib.licenses.gpl3Plus;
  };
}
