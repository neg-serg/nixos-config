##
# Package: f0plugins
# Purpose: redFrik's SuperCollider plugins — 19 UGens (sound-chip emulations,
#   euclidean rhythms, wavesets, sives, DPCM codecs, …). Server plugins (.so)
#   plus SC class files.
# Source: https://github.com/redFrik/f0plugins
{
  lib,
  mkScPlugin,
  fetchFromGitHub,
  scPluginFarm,
}:
mkScPlugin {
  pname = "f0plugins";
  version = "unstable-2025-02-11";

  src = fetchFromGitHub {
    owner = "redFrik";
    repo = "f0plugins";
    rev = "fe6a42a1a1a9e86e68d3d0416a582a07adf302aa";
    hash = "sha256-yNSDoX4yJ9f0mXiUGfvX9kHZbzNwGg4C21BUsJPZzxg=";
  };

  inherit scPluginFarm;

  cmakeFlags = [ "-DSCSYNTH=ON" ];

  # Every plugin gets its own directory under the extension root (upstream
  # builds one install tree per plugin, so one shared extensions/ dir would
  # merge 19 unrelated class sets into one namespace).
  installDir = "f0plugins";
  install = ''
    for dir in "$out"/f0plugins/*/; do
      name="$(basename "$dir")"
      # server plugin .so
      find "$dir/linux" -name '*_scsynth.so' -exec mv {} "$pluginsDir/" \;
      # class file + help + tests
      mkdir -p "$extdir/$name"
      cp "$dir"/*.sc "$extdir/$name/" 2>/dev/null || true
      cp -r "$dir/HelpSource" "$extdir/$name/" 2>/dev/null || true
      cp -r "$dir/Tests" "$extdir/$name/" 2>/dev/null || true
    done
    rm -rf "$out/f0plugins"
  '';

  meta = lib.mkMeta {
    description = "redFrik SuperCollider plugins (sound chips, rhythms, wavesets, sives)";
    homepage = "https://github.com/redFrik/f0plugins";
    license = lib.licenses.gpl2Plus;
  };
}
