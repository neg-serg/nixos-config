{
  pkgs,
  lib,
  ...
}:
let
  optionalIaCTools = lib.optionals (pkgs ? aiac) [ pkgs.aiac ];
in
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.ansible # IT automation platform
    pkgs.terraform # Tool for building, changing, and versioning infrastructure
    pkgs.opentofu # Tool for building, changing, and versioning infrastructure
  ]
  ++ optionalIaCTools;
}
