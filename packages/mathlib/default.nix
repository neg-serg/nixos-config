##
# Package: mathlib
# Purpose: MathLib — SC quark: math classes (matrices, linear algebra,
#   distributions, solving). Dependency of ATK.
# Source: https://github.com/supercollider-quarks/MathLib
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "mathlib";
  version = "unstable-2022-08-18";

  src = fetchFromGitHub {
    owner = "supercollider-quarks";
    repo = "MathLib";
    rev = "c539982578da73ad29ea291ddb82babd9465df12";
    hash = "sha256-S2rX71+0Acl/sWHEyRfZdMrSjuafnmB7tU8w+mkCgCg=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/MathLib"
    mkdir -p "$extdir"
    cp -r classes "$extdir/"
    cp -r help "$extdir/" 2>/dev/null || true
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp MathLib.quark LICENSE "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: math classes (matrices, linear algebra, distributions)";
    homepage = "https://github.com/supercollider-quarks/MathLib";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
