{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.alejandra # the uncompromising nix code formatter
    pkgs.cached-nix-shell # nix-shell with instant startup
    pkgs.cachix # download pre-built binaries
    pkgs.dconf2nix # convert dconf to nix config
    pkgs.deadnix # scan for dead nix code
    pkgs.manix # nixos documentation
    pkgs.nh # nice nix commands
    pkgs.niv # pin dependencies
    pkgs.nix-diff # show what makes derivations differ
    pkgs.nix-index # index for nix-locate
    pkgs.nix-init # easier creation of nix packages
    pkgs.nixos-shell # create VM for current config
    pkgs.nix-output-monitor # fancy nix output (nom)
    pkgs.nix-tree # interactive derivation dependency inspector
    pkgs.npins # alternative to niv
    pkgs.nurl # generate Nix fetcher calls from repository URLs
    pkgs.nvd # compare versions: nvd diff /run/current-system result
    pkgs.statix # static analyzer for nix
  ];
}
