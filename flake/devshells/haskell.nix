{
  pkgs,
  lib,
  ...
}:
let
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
    pkgs.tidal-ghci # TidalCycles GHCi wrapper (defined once in packages/overlay.nix)
    pkgs.haskellPackages.tidal # TidalCycles library
  ]
  ++ optionalHaskellTools;
}
