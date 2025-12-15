{inputs, ...}: {
  imports = [
    inputs.nix-maid.nixosModules.default
    ./git.nix
  ];

  users.users.neg.maid = {};
}
