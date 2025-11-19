{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.secrets.enable or true;
  packages = [
    pkgs.tomb
    pkgs.keepass
    pkgs.pass-git-helper
    (pkgs.pass.withExtensions (ext: with ext; [pass-import pass-otp pass-tomb pass-update]))
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
