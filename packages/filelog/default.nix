##
# Package: filelog
# Purpose: FileLog — SC quark: file logging, file player, streamed file IO
#   (classes FilePlayer, FileWriter, extFileReader…). Dependency of ATK.
# Source: https://github.com/supercollider-quarks/FileLog
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "filelog";
  version = "unstable-2014-11-30";

  owner = "supercollider-quarks";
  repo = "FileLog";
  rev = "fea7ba8625307ca69c57a5ef9501dd7f6433308e";
  hash = "sha256-AIFUxa2d3K9zki3fBpe6yjChf8zbNA+emKubeDfwMb0=";

  installDir = "FileLog";
  install = ''
    cp *.sc "$extdir/" 2>/dev/null || true
    cp -r Help "$extdir/" 2>/dev/null || true
    cp FileLog.quark "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: file logging, file player, streamed file IO";
    homepage = "https://github.com/supercollider-quarks/FileLog";
    license = lib.licenses.gpl2Plus;
  };
}
