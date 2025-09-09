{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    alejandra # the uncompromising nix code formatter
    cached-nix-shell # nix-shell with instant startup
    cachix # download pre-built binaries
    dconf2nix # convert dconf to nix config
    deadnix # scan for dead nix code
    manix # nixos documentation
    nh # nice nix commands
    niv # pin dependencies
    nix-diff # show what makes derivations differ
    nix-index # index for nix-locate
    nix-init # easier creation of nix packages
    nixos-shell # create VM for current config
    nix-output-monitor # fancy nix output (nom)
    nix-tree # interactive derivation dependency inspector
    npins # alternative to niv
    nurl # generate Nix fetcher calls from repository URLs
    nvd # compare versions: nvd diff /run/current-system result
    statix # static analyzer for nix
  ];
}
