{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  packages = [
    pkgs.gallery-dl # download image galleries
    pkgs.monolith # single-file webpage archiver
  ];
}
