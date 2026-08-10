{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.guestfs-tools # tools for accessing and modifying virtual machine disk images
    pkgs.lima # Linux virtual machines
    pkgs.quickemu # quickly create and run highly optimised desktop virtual machines
  ];
}
