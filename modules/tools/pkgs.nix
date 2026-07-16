{
  pkgs,

  ...
}:
{
  environment.systemPackages = [
    pkgs.nixfmt # Nix formatter
    pkgs.cached-nix-shell # nix-shell with instant startup
    pkgs.deadnix # scan for dead nix code
    pkgs.manix # nixos documentation
    pkgs.nix-init # easier creation of nix packages
    pkgs.nixos-shell # create VM for current config
    pkgs.nix-output-monitor # fancy nix output (nom)
    pkgs.npins # dependency pinning (Rust, alternative to niv)
    pkgs.nix-fast-build # parallel evaluation+building with log renderer
    pkgs.dix # diff closures: dix /run/current-system result (Rust rewrite of nvd)
    pkgs.nix-melt # TUI for nix flake lock --update
    pkgs.statix # static analyzer for nix
  ];
}
