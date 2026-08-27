##
# Package: jsonlib
# Purpose: JSONlib — SuperCollider quark, JSON encoder/decoder.
#   Dependency of SuperDirtMixer (preset files are JSON).
# Source: https://github.com/musikinformatik/JSONlib
{
  lib,
  stdenvNoCC,
  fetchgit,
}:
stdenvNoCC.mkDerivation {
  pname = "jsonlib";
  version = "0.1-unstable-2023-02-18";

  src = fetchgit {
    url = "https://github.com/musikinformatik/JSONlib.git";
    rev = "f737156ecbe8045f77e96ca5cf92e48b90db860a";
    hash = "sha256-CIvBSbpkinNgsF7RRMSjOvJrDkMf3W1qHTOPrOJxBUo=";
  };

  installPhase = ''
    runHook preInstall

    extdir="$out/share/SuperCollider/extensions/JSONlib"
    mkdir -p "$extdir"

    cp -r classes "$extdir/"
    cp -r HelpSource "$extdir/"
    cp -r Tests "$extdir/"
    cp JSONlib.quark "$extdir/"
    cp LICENSE README.md "$extdir/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: JSON encoder/decoder";
    longDescription = ''
      JSONlib is a SuperCollider quark that provides a JSON en- and decoder.
      It is a dependency of SuperDirtMixer, whose preset files are stored as
      JSON.
    '';
    homepage = "https://github.com/musikinformatik/JSONlib";
    license = licenses.gpl2; # JSONlib LICENSE is GPL-2.0
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
