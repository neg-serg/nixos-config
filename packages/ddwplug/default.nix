##
# Package: ddwplug
# Purpose: ddwPlug — SC quark by James Harkins: dynamic per-note synth
#   patching (AbstractPatchableNode, Plug, Syn, Pmsyn) for live coding.
# Source: https://github.com/jamshark70/ddwPlug
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "ddwplug";
  version = "0.1-unstable-2026-06-19";

  owner = "jamshark70";
  repo = "ddwPlug";
  rev = "0df52243b8a8fb34fbf6904ede483a23f8db9b1e";
  hash = "sha256-8WAknHqQoybdXH8T010cpPVRz0J3Ck4nBAXXQG7GXxs=";

  installDir = "ddwPlug";
  install = ''
    cp *.sc "$extdir/" 2>/dev/null || true
    cp -r SystemOverwrites "$extdir/" 2>/dev/null || true
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp ddwPlug.quark LICENSE "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: dynamic per-note synth patching";
    homepage = "https://github.com/jamshark70/ddwPlug";
    license = lib.licenses.gpl2Plus;
  };
}
