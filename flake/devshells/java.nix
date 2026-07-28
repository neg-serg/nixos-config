{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.jdk # Open-source Java Development Kit
    pkgs.gradle # Enterprise-grade build system
  ];
}
