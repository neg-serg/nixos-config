{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.secrets.enable or true;
  packages = [
    pkgs.tomb # simple encrypted vaults (LUKS+dm-crypt) for secrets
    pkgs.keepass # KeePassXC CLI for migrating legacy vaults
    pkgs.pass-git-helper # Git credential helper backed by pass
    (pkgs.pass.withExtensions (
      # Stores, retrieves, generates, and synchronizes passwords ...
      ext: with ext; [
        pass-import
        pass-otp
        pass-tomb
        pass-update
      ]
    )) # pass + OTP/import/tomb/update extensions
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
