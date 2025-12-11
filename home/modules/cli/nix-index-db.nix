{
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.features.cli.nixIndexDB;
in {
  imports = [
    inputs.nix-index-database.homeModules.nix-index
  ];

  config = lib.mkIf cfg.enable {
    programs.nix-index-database.comma.enable = true;
    # metadata about the module usage
    programs.nix-index.enable = true;
  };
}
