##
# Package: crucial-library
# Purpose: crucial-library — the AbstractPlayer system for SuperCollider:
#   Patch, Instr, Sample, players and scheduling tools for live coding
#   (by felix / crucialfelix). Pure sclang classes.
# Source: https://github.com/crucialfelix/crucial-library
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "crucial-library";
  version = "4.1.6-unstable-2018-01-04";

  owner = "crucialfelix";
  repo = "crucial-library";
  rev = "b4f5f23cee2a37d1134506e8bccdfc5ad880610c";
  hash = "sha256-FSy9tb5H6CoPKvIcHPrYqL6b03fLsVgutxYpAsdIzmo=";

  installDir = "crucial-library";
  install = ''
    # Top-level .sc files + class subdirectories + help
    cp *.sc "$extdir/" 2>/dev/null || true
    for d in apis Control Editors Gui Instr JITLibCrucialWrappers Players Sample Scheduling; do
      [ -d "$d" ] && cp -r "$d" "$extdir/"
    done
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp crucial-library.quark "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: AbstractPlayer system (Patch, Instr, Sample, scheduling) for live coding";
    homepage = "https://github.com/crucialfelix/crucial-library";
    license = lib.licenses.gpl2Plus;
  };
}
