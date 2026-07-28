{
  pkgs,
  lib,
  ...
}:
let
  tidalGhci = pkgs.writeShellScriptBin "tidal-ghci" ''
    exec ${pkgs.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@" # Glasgow Haskell Compiler
  '';
  optionalHaskellTools =
    lib.optionals (pkgs ? fourmolu) [ pkgs.fourmolu ] # haskell formatter
    ++ lib.optionals (pkgs ? hindent) [ pkgs.hindent ]; # alternative haskell formatter
in
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.ghc # compiler
    pkgs.cabal-install # package/build tool
    pkgs.stack # alternative build tool
    pkgs.haskell-language-server # IDE/LSP backend
    pkgs.hlint # linter
    pkgs.ormolu # formatter
    pkgs.ghcid # fast GHCi reload loop
    tidalGhci # TidalCycles GHCi wrapper
    pkgs.haskellPackages.tidal # TidalCycles library
  ]
  ++ optionalHaskellTools;
}
