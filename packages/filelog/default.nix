##
# Package: filelog
# Purpose: FileLog — SC quark: file logging, file player, streamed file IO
#   (classes FilePlayer, FileWriter, extFileReader…). Dependency of ATK.
# Source: https://github.com/supercollider-quarks/FileLog
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "filelog";
  version = "unstable-2014-11-30";

  src = fetchFromGitHub {
    owner = "supercollider-quarks";
    repo = "FileLog";
    rev = "fea7ba8625307ca69c57a5ef9501dd7f6433308e";
    hash = "sha256-AIFUxa2d3K9zki3fBpe6yjChf8zbNA+emKubeDfwMb0=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/FileLog"
    mkdir -p "$extdir"
    cp *.sc "$extdir/" 2>/dev/null || true
    cp -r Help "$extdir/" 2>/dev/null || true
    cp FileLog.quark "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: file logging, file player, streamed file IO";
    homepage = "https://github.com/supercollider-quarks/FileLog";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
