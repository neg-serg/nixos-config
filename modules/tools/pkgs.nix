{
  pkgs,
  config,

  ...
}:
let
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    pkgs.nixfmt # Nix formatter
    pkgs.cached-nix-shell # nix-shell with instant startup
    pkgs.deadnix # scan for dead nix code
    pkgs.manix # nixos documentation
    (onDemand {
      name = "nix-init";
      attr = "nix-init";
    }) # easier creation of nix packages, on demand
    pkgs.nixos-shell # create VM for current config
    pkgs.nix-output-monitor # fancy nix output (nom)
    (onDemand {
      name = "npins";
      attr = "npins";
    }) # dependency pinning (Rust, alternative to niv), on demand
    pkgs.nix-fast-build # parallel evaluation+building with log renderer
    pkgs.nix-eval-jobs # parallel flake evaluator behind nix-fast-build; does the cache-status preflight for `just preflight`
    pkgs.dix # diff closures: dix /run/current-system result (Rust rewrite of nvd)
    pkgs.nix-melt # TUI for nix flake lock --update
    pkgs.neg.nixard # TUI for exploring NixOS package closures and generating Nix declarations
    pkgs.statix # static analyzer for nix
  ];
}
