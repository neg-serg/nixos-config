##
# Package: f0plugins
# Purpose: redFrik's SuperCollider plugins — 19 UGens (sound-chip emulations,
#   euclidean rhythms, wavesets, sives, DPCM codecs, …). Server plugins (.so)
#   plus SC class files.
# Source: https://github.com/redFrik/f0plugins
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "f0plugins";
  version = "unstable-2025-02-11";

  src = fetchFromGitHub {
    owner = "redFrik";
    repo = "f0plugins";
    rev = "fe6a42a1a1a9e86e68d3d0416a582a07adf302aa";
    hash = "sha256-yNSDoX4yJ9f0mXiUGfvX9kHZbzNwGg4C21BUsJPZzxg=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DSCSYNTH=ON"
  ];

  postInstall = ''
    # Reorganize the per-plugin install tree into the standard SC layout:
    #   .so files  -> $out/lib/SuperCollider/plugins/
    #   classes    -> $out/share/SuperCollider/extensions/f0plugins/<Name>/
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/f0plugins"

    for dir in "$out"/f0plugins/*/; do
      name="$(basename "$dir")"
      # server plugin .so
      find "$dir/linux" -name '*_scsynth.so' -exec mv {} "$out/lib/SuperCollider/plugins/" \;
      # class file + help + tests
      mkdir -p "$out/share/SuperCollider/extensions/f0plugins/$name"
      cp "$dir"/*.sc "$out/share/SuperCollider/extensions/f0plugins/$name/" 2>/dev/null || true
      cp -r "$dir/HelpSource" "$out/share/SuperCollider/extensions/f0plugins/$name/" 2>/dev/null || true
      cp -r "$dir/Tests" "$out/share/SuperCollider/extensions/f0plugins/$name/" 2>/dev/null || true
    done
    rm -rf "$out/f0plugins"
  '';

  meta = with lib; {
    description = "redFrik SuperCollider plugins (sound chips, rhythms, wavesets, sives)";
    homepage = "https://github.com/redFrik/f0plugins";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
