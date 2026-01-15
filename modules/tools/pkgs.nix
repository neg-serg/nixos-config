{
  pkgs,

  ...
}:
{
  environment.systemPackages = [
    pkgs.nixfmt # Nix formatter
    pkgs.cached-nix-shell # nix-shell with instant startup
    # pkgs.cachix # download pre-built binaries (BROKEN BUILD 1.9.1)
    pkgs.dconf2nix # convert dconf to nix config
    pkgs.deadnix # scan for dead nix code
    pkgs.manix # nixos documentation
    pkgs.niv # pin dependencies
    pkgs.nix-diff # show what makes derivations differ
    pkgs.nix-init # easier creation of nix packages
    pkgs.nixos-shell # create VM for current config
    pkgs.nix-output-monitor # fancy nix output (nom)
    pkgs.nix-tree # interactive derivation dependency inspector
    pkgs.npins # alternative to niv
    pkgs.nurl # generate Nix fetcher calls from repository URLs
    pkgs.nvd # compare versions: nvd diff /run/current-system result
    pkgs.nix-melt # TUI for nix flake lock --update
    pkgs.statix # static analyzer for nix

  ];
}
