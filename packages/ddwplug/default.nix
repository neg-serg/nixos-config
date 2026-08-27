##
# Package: ddwplug
# Purpose: ddwPlug — SC quark by James Harkins: dynamic per-note synth
#   patching (AbstractPatchableNode, Plug, Syn, Pmsyn) for live coding.
# Source: https://github.com/jamshark70/ddwPlug
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "ddwplug";
  version = "0.1-unstable-2026-06-19";

  src = fetchFromGitHub {
    owner = "jamshark70";
    repo = "ddwPlug";
    rev = "0df52243b8a8fb34fbf6904ede483a23f8db9b1e";
    hash = "sha256-8WAknHqQoybdXH8T010cpPVRz0J3Ck4nBAXXQG7GXxs=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/ddwPlug"
    mkdir -p "$extdir"
    cp *.sc "$extdir/" 2>/dev/null || true
    cp -r SystemOverwrites "$extdir/" 2>/dev/null || true
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp ddwPlug.quark LICENSE "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: dynamic per-note synth patching";
    homepage = "https://github.com/jamshark70/ddwPlug";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
