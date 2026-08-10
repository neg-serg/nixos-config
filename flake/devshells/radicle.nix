{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.radicle-node # Radicle node and CLI for decentralized code collaboration
    pkgs.radicle-explorer # Web frontend for Radicle
  ];
}
